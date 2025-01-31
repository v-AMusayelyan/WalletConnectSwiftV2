import Foundation
import XCTest
import WalletConnectUtils
@testable import WalletConnectKMS
import WalletConnectRelay
import Combine
import WalletConnectNetworking
import WalletConnectEcho
@testable import WalletConnectPush
@testable import WalletConnectPairing
import WalletConnectIdentity
import WalletConnectSigner

final class PushTests: XCTestCase {

    var dappPairingClient: PairingClient!
    var walletPairingClient: PairingClient!

    var dappPushClient: DappPushClient!
    var walletPushClient: WalletPushClient!

    var pairingStorage: PairingStorage!

    private var publishers = [AnyCancellable]()

    func makeClientDependencies(prefix: String) -> (PairingClient, NetworkInteracting, KeychainStorageProtocol, KeyValueStorage) {
        let keychain = KeychainStorageMock()
        let keyValueStorage = RuntimeKeyValueStorage()

        let relayLogger = ConsoleLogger(suffix: prefix + " [Relay]", loggingLevel: .debug)
        let pairingLogger = ConsoleLogger(suffix: prefix + " [Pairing]", loggingLevel: .debug)
        let networkingLogger = ConsoleLogger(suffix: prefix + " [Networking]", loggingLevel: .debug)

        let relayClient = RelayClient(
            relayHost: InputConfig.relayHost,
            projectId: InputConfig.projectId,
            keyValueStorage: RuntimeKeyValueStorage(),
            keychainStorage: keychain,
            socketFactory: DefaultSocketFactory(),
            logger: relayLogger)

        let networkingClient = NetworkingClientFactory.create(
            relayClient: relayClient,
            logger: networkingLogger,
            keychainStorage: keychain,
            keyValueStorage: keyValueStorage)

        let pairingClient = PairingClientFactory.create(
            logger: pairingLogger,
            keyValueStorage: keyValueStorage,
            keychainStorage: keychain,
            networkingClient: networkingClient)

        let clientId = try! networkingClient.getClientId()
        networkingLogger.debug("My client id is: \(clientId)")
        
        return (pairingClient, networkingClient, keychain, keyValueStorage)
    }

    func makeDappClients() {
        let prefix = "🦄 Dapp: "
        let (pairingClient, networkingInteractor, keychain, keyValueStorage) = makeClientDependencies(prefix: prefix)
        let pushLogger = ConsoleLogger(suffix: prefix + " [Push]", loggingLevel: .debug)
        dappPairingClient = pairingClient
        dappPushClient = DappPushClientFactory.create(metadata: AppMetadata(name: "GM Dapp", description: "", url: "https://gm-dapp-xi.vercel.app/", icons: []),
                                                      logger: pushLogger,
                                                      keyValueStorage: keyValueStorage,
                                                      keychainStorage: keychain,
                                                      networkInteractor: networkingInteractor)
    }

    func makeWalletClients() {
        let prefix = "🦋 Wallet: "
        let (pairingClient, networkingInteractor, keychain, keyValueStorage) = makeClientDependencies(prefix: prefix)
        let pushLogger = ConsoleLogger(suffix: prefix + " [Push]", loggingLevel: .debug)
        walletPairingClient = pairingClient
        let echoClient = EchoClientFactory.create(projectId: "",
                                                  echoHost: "echo.walletconnect.com",
                                                  keychainStorage: keychain,
                                                  environment: .sandbox)
        let keyserverURL = URL(string: "https://keys.walletconnect.com")!
        walletPushClient = WalletPushClientFactory.create(keyserverURL: keyserverURL,
                                                          logger: pushLogger,
                                                          keyValueStorage: keyValueStorage,
                                                          keychainStorage: keychain,
                                                          groupKeychainStorage: KeychainStorageMock(),
                                                          networkInteractor: networkingInteractor,
                                                          pairingRegisterer: pairingClient,
                                                          echoClient: echoClient)
    }

    override func setUp() {
        makeDappClients()
        makeWalletClients()
    }

    func testPushPropose() async {
        let expectation = expectation(description: "expects dapp to receive error response")

        let uri = try! await dappPairingClient.create()
        try! await walletPairingClient.pair(uri: uri)
        try! await dappPushClient.propose(account: Account.stub(), topic: uri.topic)

        walletPushClient.requestPublisher.sink { [unowned self] (id, _, _) in
            Task(priority: .high) { try! await walletPushClient.approve(id: id, onSign: sign) }
        }.store(in: &publishers)

        dappPushClient.proposalResponsePublisher.sink { (result) in
            guard case .success = result else {
                XCTFail()
                return
            }
            expectation.fulfill()
        }.store(in: &publishers)
        wait(for: [expectation], timeout: InputConfig.defaultTimeout)

    }

    func testWalletRejectsPushPropose() async {
        let expectation = expectation(description: "expects dapp to receive error response")

        let uri = try! await dappPairingClient.create()
        try! await walletPairingClient.pair(uri: uri)
        try! await dappPushClient.propose(account: Account.stub(), topic: uri.topic)

        walletPushClient.requestPublisher.sink { [unowned self] (id, _, _) in
            Task(priority: .high) { try! await walletPushClient.reject(id: id) }
        }.store(in: &publishers)

        dappPushClient.proposalResponsePublisher.sink { (result) in
            guard case .failure = result else {
                XCTFail()
                return
            }
            expectation.fulfill()
        }.store(in: &publishers)

        wait(for: [expectation], timeout: InputConfig.defaultTimeout)
    }

    func testWalletCreatesSubscription() async {
        let expectation = expectation(description: "expects to create push subscription")
        let metadata = AppMetadata(name: "GM Dapp", description: "", url: "https://gm-dapp-xi.vercel.app/", icons: [])
        try! await walletPushClient.subscribe(metadata: metadata, account: Account.stub(), onSign: sign)
        walletPushClient.subscriptionsPublisher
            .first()
            .sink { [unowned self] subscriptions in
                XCTAssertNotNil(subscriptions.first)
                Task { try! await walletPushClient.deleteSubscription(topic: subscriptions.first!.topic) }
                expectation.fulfill()
            }.store(in: &publishers)
        wait(for: [expectation], timeout: InputConfig.defaultTimeout)
    }


    func testDeletePushSubscription() async {
        let expectation = expectation(description: "expects to delete push subscription")
        let uri = try! await dappPairingClient.create()
        try! await walletPairingClient.pair(uri: uri)
        try! await dappPushClient.propose(account: Account.stub(), topic: uri.topic)
        var subscriptionTopic: String!

        walletPushClient.requestPublisher.sink { [unowned self] (id, _, _) in
            Task(priority: .high) { try! await walletPushClient.approve(id: id, onSign: sign) }
        }.store(in: &publishers)

        dappPushClient.proposalResponsePublisher.sink { [unowned self] (result) in
            guard case .success(let pushSubscription) = result else {
                XCTFail()
                return
            }
            subscriptionTopic = pushSubscription.topic
            sleep(1)
            Task(priority: .userInitiated) { try! await walletPushClient.deleteSubscription(topic: pushSubscription.topic)}
        }.store(in: &publishers)

        dappPushClient.deleteSubscriptionPublisher.sink { topic in
            XCTAssertEqual(subscriptionTopic, topic)
            expectation.fulfill()
        }.store(in: &publishers)
        wait(for: [expectation], timeout: InputConfig.defaultTimeout)
    }

    func testWalletCreatesAndUpdatesSubscription() async {
        let expectation = expectation(description: "expects to create and update push subscription")
        let metadata = AppMetadata(name: "GM Dapp", description: "", url: "https://gm-dapp-xi.vercel.app/", icons: [])
        let updateScope: Set<String> = ["alerts"]
        try! await walletPushClient.subscribe(metadata: metadata, account: Account.stub(), onSign: sign)
        walletPushClient.subscriptionsPublisher
            .first()
            .sink { [unowned self] subscriptions in
                Task { try! await walletPushClient.update(topic: subscriptions.first!.topic, scope: updateScope) }
            }
            .store(in: &publishers)

        walletPushClient.updateSubscriptionPublisher
            .sink { [unowned self] result in
                guard case .success(let subscription) = result else { XCTFail(); return }
                let updatedScope = Set(subscription.scope.filter{ $0.value.enabled == true }.keys)
                XCTAssertEqual(updatedScope, updateScope)
                Task { try! await walletPushClient.deleteSubscription(topic: subscription.topic) }
                expectation.fulfill()
            }.store(in: &publishers)

        wait(for: [expectation], timeout: InputConfig.defaultTimeout)
    }

}


private extension PushTests {
    func sign(_ message: String) -> SigningResult {
        let privateKey = Data(hex: "305c6cde3846927892cd32762f6120539f3ec74c9e3a16b9b798b1e85351ae2a")
        let signer = MessageSignerFactory(signerFactory: DefaultSignerFactory()).create(projectId: InputConfig.projectId)
        return .signed(try! signer.sign(message: message, privateKey: privateKey, type: .eip191))
    }
}
