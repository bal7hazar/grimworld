import Capacitor
import UIKit

/// The shell's bridge: registers the app's own plugin, and in a Debug build takes the sandbox's URL
/// parameters from a launch argument (`-startQuery 'fixture=zone&scale=fit'`), so that
/// `xcrun simctl launch` can open the sandbox as `?fixture=…` does in Safari.
class ShellViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(DeviceStatePlugin())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        let scrolls = webView?.scrollView.isScrollEnabled ?? true
        var inspectable = false
        if #available(iOS 16.4, *) { inspectable = webView?.isInspectable ?? false }
        NSLog("[shell] native start inspectable=%@ scrollEnabled=%@ state=%@",
              String(inspectable), String(scrolls), String(describing: DeviceStatePlugin.state()))
        if let query = UserDefaults.standard.string(forKey: "startQuery"), let start = bridge?.config.appStartServerURL,
           var url = URLComponents(url: start, resolvingAgainstBaseURL: false) {
            url.percentEncodedQuery = query
            if let target = url.url {
                NSLog("[shell] native startQuery %@", target.absoluteString)
                webView?.load(URLRequest(url: target))
            }
        }
        #endif
    }
}
