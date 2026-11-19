import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let model = AlertModel()
    private var host: UIHostingController<AlertView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Theme.canvas)
        let host = UIHostingController(rootView: AlertView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host
    }

    func didReceive(_ notification: UNNotification) {
        model.receive(notification.request.content)
        fitHeight()
    }

    /// La proporción del Info.plist es solo la altura inicial: con letra grande o un texto largo
    /// la vista crece hasta lo que pide SwiftUI, en vez de recortar.
    private func fitHeight() {
        let width = view.bounds.width
        guard width > 0 else { return }
        let probe = UIHostingController(rootView: AlertView(model: model, measuring: true))
        let fitted = probe.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        guard fitted.height > 0, abs(fitted.height - preferredContentSize.height) > 1 else { return }
        preferredContentSize = CGSize(width: width, height: ceil(fitted.height))
    }
}
