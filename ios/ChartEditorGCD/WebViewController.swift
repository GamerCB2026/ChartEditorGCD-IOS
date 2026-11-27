import UIKit
import WebKit

final class WebViewController: UIViewController, WKUIDelegate, WKNavigationDelegate {
    private var webView: WKWebView!
    private let bridge = GCDBridge()
    private let scheme = AssetSchemeHandler()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.setURLSchemeHandler(scheme, forURLScheme: "gcd")
        cfg.userContentController.addUserScript(GCDBridge.userScript)
        cfg.userContentController.add(bridge, name: "gcd")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) { wv.isInspectable = false }
        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        webView = wv
        bridge.webView = wv

        // Misma entrada que el APK (index + testsong dentro de g.dat)
        if let url = URL(string: "gcd://app/index.html") {
            wv.load(URLRequest(url: url))
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if url.scheme == "gcd" {
                let child = WKWebView(frame: view.bounds, configuration: configuration)
                child.navigationDelegate = self
                child.uiDelegate = self
                // Popup interno: cargar en el mismo webView (Test Song / playtest)
                webView.load(navigationAction.request)
                return nil
            }
            if let s = url.scheme, ["http","https"].contains(s) {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        if url.scheme == "gcd" {
            decisionHandler(.allow); return
        }
        if let host = url.host, host.contains("gamercb2026.github.io"),
           url.path.hasPrefix("/Soporte-De-Errores") {
            UIApplication.shared.open(url)
            decisionHandler(.cancel); return
        }
        if let s = url.scheme, ["http","https"].contains(s) {
            // Enlaces externos → Safari; el resto del contenido va por gcd://
            UIApplication.shared.open(url)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
}
