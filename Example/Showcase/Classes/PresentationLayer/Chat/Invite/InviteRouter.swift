import UIKit

final class InviteRouter {

    weak var viewController: UIViewController!

    private let app: Application

    init(app: Application) {
        self.app = app
    }

    func dismiss() {
        viewController.dismiss()
    }
}
