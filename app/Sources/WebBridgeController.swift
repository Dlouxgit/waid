import AppKit
import Foundation
import WebKit

final class WebBridgeController: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: NSWindow

    init(webRootURL: URL, snapshotProvider: @escaping () -> DashboardSnapshot) throws {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            AppSchemeHandler(webRootURL: webRootURL, snapshotProvider: snapshotProvider),
            forURLScheme: "waid"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)

        self.webView = webView
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()

        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        window.title = "Waid"
        window.center()
        window.contentView = webView
        window.isReleasedWhenClosed = false

        guard let indexURL = URL(string: "waid://app/index.html") else {
            throw AppError.missingResource("Failed to create app URL.")
        }

        webView.load(URLRequest(url: indexURL))
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("Waid web view loaded.")
    }
}

final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    private let webRootURL: URL
    private let snapshotProvider: () -> DashboardSnapshot

    init(webRootURL: URL, snapshotProvider: @escaping () -> DashboardSnapshot) {
        self.webRootURL = webRootURL
        self.snapshotProvider = snapshotProvider
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let url = urlSchemeTask.request.url
        let path = normalizedPath(for: url)

        do {
            if path == "/api/dashboard" {
                let encoder = JSONEncoder()
                let data = try encoder.encode(snapshotProvider())
                let response = try httpResponse(
                    url: url,
                    statusCode: 200,
                    contentType: "application/json; charset=utf-8",
                    contentLength: data.count
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } else {
                let targetPath = path == "/" ? "index.html" : String(path.dropFirst())
                let fileURL = webRootURL.appendingPathComponent(targetPath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    let response = try httpResponse(
                        url: url,
                        statusCode: 404,
                        contentType: "text/plain; charset=utf-8",
                        contentLength: 9
                    )
                    let data = Data("Not found".utf8)
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                    return
                }

                let data = try Data(contentsOf: fileURL)
                let response = try httpResponse(
                    url: url,
                    statusCode: 200,
                    contentType: contentType(for: fileURL.pathExtension),
                    contentLength: data.count
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func normalizedPath(for url: URL?) -> String {
        let path = url?.path ?? "/"
        return path.isEmpty ? "/" : path
    }

    private func contentType(for pathExtension: String) -> String {
        switch pathExtension {
        case "css":
            return "text/css; charset=utf-8"
        case "js":
            return "application/javascript; charset=utf-8"
        case "html":
            return "text/html; charset=utf-8"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        default:
            return "application/octet-stream"
        }
    }

    private func httpResponse(url: URL?, statusCode: Int, contentType: String, contentLength: Int) throws -> HTTPURLResponse {
        guard let resolvedURL = url ?? URL(string: "waid://app/") else {
            throw AppError.missingResource("Failed to resolve app URL.")
        }

        guard let response = HTTPURLResponse(
            url: resolvedURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": contentType,
                "Content-Length": String(contentLength),
                "Cache-Control": "no-store"
            ]
        ) else {
            throw AppError.missingResource("Failed to create app response.")
        }

        return response
    }
}
