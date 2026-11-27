import Foundation
import WebKit
import UniformTypeIdentifiers

/// Sirve rutas del pack cifrado como gcd://app/...
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(PackCrypto.PackError.missing("url"))
            return
        }
        var path = url.path
        while path.hasPrefix("/") { path = String(path.dropFirst()) }
        if path.isEmpty || path.hasSuffix("/") { path += "index.html" }
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        path = path.removingPercentEncoding ?? path

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try PackCrypto.openPath(path)
                let mime = Self.mime(for: path)
                var ct = mime
                if mime.hasPrefix("text/") || mime == "application/json" { ct += "; charset=utf-8" }
                let resp: URLResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": ct, "Content-Length": String(data.count),
                                   "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"])
                    ?? URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
                DispatchQueue.main.async {
                    urlSchemeTask.didReceive(resp)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                }
            } catch {
                NSLog("[GCD] asset error %@: %@", path, String(describing: error))
                DispatchQueue.main.async {
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static func mime(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        if let ut = UTType(filenameExtension: ext), let m = ut.preferredMIMEType { return m }
        switch ext {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "wav": return "audio/wav"
        case "ttf": return "font/ttf"
        case "woff", "woff2": return "font/\(ext)"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}
