import Foundation

enum IdentityKeyAPI: HTTPService {

    case registerIdentity(cacao: Cacao)
    case resolveIdentity(publicKey: String)
    case removeIdentity(idAuth: String)
    case registerInvite(idAuth: String)
    case resolveInvite(account: String)
    case removeInvite(idAuth: String)

    var path: String {
        switch self {
        case .registerIdentity, .resolveIdentity, .removeIdentity:
            return "/identity"
        case .registerInvite, .resolveInvite, .removeInvite:
            return "/invite"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .registerIdentity, .registerInvite:
            return .post
        case .resolveIdentity, .resolveInvite:
            return .get
        case .removeInvite, .removeIdentity:
            return .delete
        }
    }

    var body: Data? {
        switch self {
        case .registerIdentity(let cacao):
            return try? JSONEncoder().encode(RegisterIdentityRequest(cacao: cacao))
        case .registerInvite(let idAuth), .removeInvite(let idAuth), .removeIdentity(let idAuth):
            return try? JSONEncoder().encode(IdAuthRequest(idAuth: idAuth))
        case .resolveIdentity, .resolveInvite:
            return nil
        }
    }

    var queryParameters: [String : String]? {
        switch self {
        case .resolveIdentity(let publicKey):
            return ["publicKey": publicKey]
        case .resolveInvite(let account):
            return ["account": account]
        case .registerIdentity, .registerInvite, .removeInvite, .removeIdentity:
            return nil
        }
    }

    var additionalHeaderFields: [String : String]? {
        return nil
    }
}

private extension IdentityKeyAPI {

    struct RegisterIdentityRequest: Codable {
        let cacao: Cacao
    }

    struct IdAuthRequest: Codable {
        let idAuth: String
    }
}
