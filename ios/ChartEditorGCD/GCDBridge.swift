import Foundation
import WebKit
import UIKit

final class GCDBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    static var userScript: WKUserScript {
        let js = """
        (function(){
          if (window.__gcdIosBridge) return;
          window.__gcdIosBridge = true;
          document.documentElement.classList.add('gcd-apk');
          function post(name, payload){
            try { window.webkit.messageHandlers.gcd.postMessage(Object.assign({t:name}, payload||{})); } catch(e) {}
          }
          window.GCDAndroid = {
            isAndroidApp: function(){ return true; },
            canPickFolder: function(){ return false; },
            toast: function(msg){ post('toast', {msg: String(msg||'')}); },
            openExternalUrl: function(url){ post('open', {url: String(url||'')}); },
            lockOrientation: function(o){ post('orient', {o: String(o||'any')}); },
            beginDownload: function(){ return 0; },
            appendChunk: function(){},
            finishDownload: function(){},
            pickFolder: function(){},
            releaseFolder: function(){}
          };
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "gcdlog" { NSLog("[GCD] %@", String(describing: message.body)); return }
        guard let body = message.body as? [String: Any], let t = body["t"] as? String else { return }
        switch t {
        case "toast":
            if let msg = body["msg"] as? String {
                DispatchQueue.main.async {
                    guard let root = self.webView?.window?.rootViewController else { return }
                    let a = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
                    root.present(a, animated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { a.dismiss(animated: true) }
                }
            }
        case "open":
            if let s = body["url"] as? String, let u = URL(string: s), ["http","https"].contains(u.scheme?.lowercased() ?? "") {
                DispatchQueue.main.async { UIApplication.shared.open(u) }
            }
        case "orient":
            break
        default:
            break
        }
    }
}
