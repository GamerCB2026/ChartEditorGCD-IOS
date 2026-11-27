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

        wv.configuration.userContentController.add(bridge, name: "gcdlog")
        let errJS = """
        window.addEventListener('error',function(e){try{webkit.messageHandlers.gcdlog.postMessage('JS: '+(e.message||'')+' @ '+(e.filename||e.target&&e.target.src||'')+':'+(e.lineno||0))}catch(x){}},true);
        window.addEventListener('unhandledrejection',function(e){try{webkit.messageHandlers.gcdlog.postMessage('Promise: '+String(e.reason&&e.reason.message||e.reason))}catch(x){}});
        """
        wv.configuration.userContentController.addUserScript(WKUserScript(source: errJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        // Comprobar que g.dat existe y se descifra antes de cargar
        do {
            _ = try PackCrypto.openPath("index.html")
        } catch {
            showError("No se pudo abrir el contenido (g.dat): \(error)")
            return
        }
        // Misma entrada que el APK (index + testsong dentro de g.dat)
        if let url = URL(string: "gcd://app/index.html") {
            wv.load(URLRequest(url: url))
        }
    }

    private func showError(_ msg: String) {
        NSLog("[GCD] %@", msg)
        let safe = msg.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let html = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>" +
            "<body style='background:#111;color:#fff;font:16px -apple-system;padding:24px'>" +
            "<h2 style='color:#ff5b84'>Chart Editor GCD V0.8.3 B1</h2><p>Error al cargar:</p><pre style='white-space:pre-wrap;color:#ffd27d'>" +
            safe + "</pre></body></html>"
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError("Navegación: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError("Carga: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let url = URL(string: "gcd://app/index.html") { webView.load(URLRequest(url: url)) }
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
