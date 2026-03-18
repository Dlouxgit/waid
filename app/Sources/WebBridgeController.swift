import AppKit
import Foundation
import WebKit

final class WebBridgeController: NSObject, WKNavigationDelegate {
    private static let mainWindowAutosaveName = "WaidMainWindow"
    private static let pinnedWindowDefaultsKey = "WaidWindowPinned"
    private static let focusOnlyDefaultsKey = "WaidWindowFocusOnly"
    private static let regularWindowFrameDefaultsKey = "WaidRegularWindowFrame"
    private static let defaultContentSize = NSSize(width: 1220, height: 860)
    private static let defaultMinWindowSize = NSSize(width: 980, height: 700)
    private static let focusOnlyContentSize = NSSize(width: 360, height: 156)
    private static let focusOnlyMinWindowSize = NSSize(width: 360, height: 156)
    private static let titlebarBackgroundColor = NSColor(
        calibratedRed: 0.96,
        green: 0.92,
        blue: 0.86,
        alpha: 0.98
    )
    private static let inactiveButtonTintColor = NSColor(
        calibratedRed: 0.42,
        green: 0.38,
        blue: 0.33,
        alpha: 1
    )
    private static let activeButtonTintColor = NSColor(
        calibratedRed: 0.11,
        green: 0.48,
        blue: 0.39,
        alpha: 1
    )

    private let webView: WKWebView
    private let window: NSWindow
    private let pinButton: NSButton
    private let focusOnlyButton: NSButton
    private let titlebarBackgroundView: NSView
    private let titlebarControlsContainer: NSView
    private let controlsStackView: NSStackView
    private(set) var isPinned = false
    private(set) var isFocusOnly = false

    init(webRootURL: URL, snapshotProvider: @escaping () -> DashboardSnapshot) throws {
        let savedPinnedState = UserDefaults.standard.object(forKey: Self.pinnedWindowDefaultsKey) as? Bool ?? false
        let savedFocusOnlyState = UserDefaults.standard.object(forKey: Self.focusOnlyDefaultsKey) as? Bool ?? false
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            AppSchemeHandler(webRootURL: webRootURL, snapshotProvider: snapshotProvider),
            forURLScheme: "waid"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let pinButton = NSButton(title: "", target: nil, action: nil)
        let focusOnlyButton = NSButton(title: "", target: nil, action: nil)
        let titlebarBackgroundView = NSView(frame: .zero)
        let titlebarControlsContainer = NSView(frame: .zero)
        let controlsStackView = NSStackView()

        self.webView = webView
        self.pinButton = pinButton
        self.focusOnlyButton = focusOnlyButton
        self.titlebarBackgroundView = titlebarBackgroundView
        self.titlebarControlsContainer = titlebarControlsContainer
        self.controlsStackView = controlsStackView
        self.window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.defaultContentSize.width,
                height: Self.defaultContentSize.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()

        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        window.title = "Waid"
        window.minSize = savedFocusOnlyState ? Self.focusOnlyMinWindowSize : Self.defaultMinWindowSize
        window.tabbingMode = .disallowed
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.backgroundColor = Self.titlebarBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none

        let restoredWindowFrame = window.setFrameUsingName(Self.mainWindowAutosaveName)

        if !restoredWindowFrame {
            window.center()
        }

        window.setFrameAutosaveName(Self.mainWindowAutosaveName)
        configureTitlebar()
        setPinned(savedPinnedState)
        setFocusOnly(savedFocusOnlyState, resizeWindow: false, syncWebView: false, storeRegularFrame: false)

        if savedFocusOnlyState && shouldResizeIntoFocusOnlyFrame(restoredWindowFrame: restoredWindowFrame) {
            applyFocusOnlyWindowSize(animated: false)
        }

        var indexURLComponents = URLComponents()
        indexURLComponents.scheme = "waid"
        indexURLComponents.host = "app"
        indexURLComponents.path = "/index.html"
        indexURLComponents.queryItems = [
            URLQueryItem(name: "focusOnly", value: savedFocusOnlyState ? "1" : "0")
        ]

        guard let indexURL = indexURLComponents.url else {
            throw AppError.missingResource("Failed to create app URL.")
        }

        webView.load(URLRequest(url: indexURL))
    }

    func showWindow() {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window.performClose(nil)
    }

    func reload() {
        webView.reload()
    }

    func togglePinned() {
        setPinned(!isPinned)
    }

    func toggleFocusOnly() {
        setFocusOnly(!isFocusOnly)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncFocusOnlyModeToWebView()
        NSLog("Waid web view loaded.")
    }

    private func configureTitlebar() {
        configureAccessoryButton(focusOnlyButton)
        configureAccessoryButton(pinButton)

        focusOnlyButton.target = self
        focusOnlyButton.action = #selector(toggleFocusOnlyFromButton(_:))
        pinButton.target = self
        pinButton.action = #selector(togglePinnedFromButton(_:))

        titlebarBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        titlebarBackgroundView.wantsLayer = true
        titlebarBackgroundView.layer?.backgroundColor = Self.titlebarBackgroundColor.cgColor

        titlebarControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        titlebarControlsContainer.setContentHuggingPriority(.required, for: .horizontal)
        titlebarControlsContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

        controlsStackView.orientation = .horizontal
        controlsStackView.alignment = .centerY
        controlsStackView.spacing = 8
        controlsStackView.translatesAutoresizingMaskIntoConstraints = false

        if controlsStackView.arrangedSubviews.isEmpty {
            controlsStackView.addArrangedSubview(focusOnlyButton)
            controlsStackView.addArrangedSubview(pinButton)
        }

        if controlsStackView.superview == nil {
            titlebarControlsContainer.addSubview(controlsStackView)
            NSLayoutConstraint.activate([
                controlsStackView.leadingAnchor.constraint(equalTo: titlebarControlsContainer.leadingAnchor),
                controlsStackView.trailingAnchor.constraint(equalTo: titlebarControlsContainer.trailingAnchor),
                controlsStackView.topAnchor.constraint(equalTo: titlebarControlsContainer.topAnchor),
                controlsStackView.bottomAnchor.constraint(equalTo: titlebarControlsContainer.bottomAnchor)
            ])
        }

        guard
            let closeButton = window.standardWindowButton(.closeButton),
            let titlebarView = closeButton.superview
        else {
            return
        }

        if titlebarBackgroundView.superview == nil {
            titlebarView.addSubview(titlebarBackgroundView, positioned: .below, relativeTo: nil)
            NSLayoutConstraint.activate([
                titlebarBackgroundView.leadingAnchor.constraint(equalTo: titlebarView.leadingAnchor),
                titlebarBackgroundView.trailingAnchor.constraint(equalTo: titlebarView.trailingAnchor),
                titlebarBackgroundView.topAnchor.constraint(equalTo: titlebarView.topAnchor),
                titlebarBackgroundView.bottomAnchor.constraint(equalTo: titlebarView.bottomAnchor)
            ])
        }

        if titlebarControlsContainer.superview == nil {
            titlebarView.addSubview(titlebarControlsContainer)
            NSLayoutConstraint.activate([
                titlebarControlsContainer.trailingAnchor.constraint(equalTo: titlebarView.trailingAnchor, constant: -16),
                titlebarControlsContainer.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                titlebarControlsContainer.heightAnchor.constraint(equalToConstant: 30)
            ])
        }
    }

    private func setPinned(_ pinned: Bool) {
        isPinned = pinned
        window.level = pinned ? .floating : .normal
        var collectionBehavior = window.collectionBehavior

        if pinned {
            collectionBehavior.insert(.moveToActiveSpace)
        } else {
            collectionBehavior.remove(.moveToActiveSpace)
        }

        window.collectionBehavior = collectionBehavior
        updateAccessoryButton(
            pinButton,
            symbolName: pinned ? "pin.fill" : "pin",
            accessibilityDescription: "Pin window on top",
            toolTip: pinned ? "Window stays on top." : "Keep the window on top.",
            active: pinned
        )

        UserDefaults.standard.set(pinned, forKey: Self.pinnedWindowDefaultsKey)
    }

    private func setFocusOnly(
        _ focusOnly: Bool,
        resizeWindow: Bool = true,
        syncWebView: Bool = true,
        storeRegularFrame: Bool = true
    ) {
        let previousState = isFocusOnly
        isFocusOnly = focusOnly
        window.minSize = focusOnly ? Self.focusOnlyMinWindowSize : Self.defaultMinWindowSize
        window.titleVisibility = focusOnly ? .hidden : .visible

        if focusOnly {
            if !previousState && storeRegularFrame {
                saveRegularWindowFrame()
            }

            if resizeWindow {
                applyFocusOnlyWindowSize(animated: true)
            }
        } else if resizeWindow {
            restoreRegularWindowSize(animated: true)
        }

        updateAccessoryButton(
            focusOnlyButton,
            symbolName: focusOnly ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
            accessibilityDescription: "Show current focus only",
            toolTip: focusOnly ? "Show the full dashboard." : "Hide everything except Current Focus.",
            active: focusOnly
        )

        if syncWebView {
            syncFocusOnlyModeToWebView()
        }

        UserDefaults.standard.set(focusOnly, forKey: Self.focusOnlyDefaultsKey)
    }

    private func configureAccessoryButton(_ button: NSButton) {
        button.title = ""
        button.setButtonType(.toggle)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func updateAccessoryButton(
        _ button: NSButton,
        symbolName: String,
        accessibilityDescription: String,
        toolTip: String,
        active: Bool
    ) {
        button.state = active ? .on : .off
        button.toolTip = toolTip
        button.contentTintColor = active ? Self.activeButtonTintColor : Self.inactiveButtonTintColor
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        button.alphaValue = active ? 1 : 0.82
    }

    private func syncFocusOnlyModeToWebView() {
        let enabled = isFocusOnly ? "true" : "false"
        let queryValue = isFocusOnly ? "1" : "0"
        let script = """
        (function() {
          var enabled = \(enabled);
          document.documentElement.dataset.focusMode = enabled ? "true" : "false";
          if (window.WaidDashboard && typeof window.WaidDashboard.setFocusMode === "function") {
            window.WaidDashboard.setFocusMode(enabled);
          }
          var url = new URL(window.location.href);
          url.searchParams.set("focusOnly", "\(queryValue)");
          window.history.replaceState(null, "", url.toString());
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func saveRegularWindowFrame() {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.regularWindowFrameDefaultsKey)
    }

    private func applyFocusOnlyWindowSize(animated: Bool) {
        applyWindowFrame(targetFrame(forContentSize: Self.focusOnlyContentSize), animated: animated)
    }

    private func shouldResizeIntoFocusOnlyFrame(restoredWindowFrame: Bool) -> Bool {
        guard restoredWindowFrame else {
            return true
        }

        let compactFrame = targetFrame(forContentSize: Self.focusOnlyContentSize)
        return window.frame.width > compactFrame.width + 24 || window.frame.height > compactFrame.height + 24
    }

    private func restoreRegularWindowSize(animated: Bool) {
        if let serializedFrame = UserDefaults.standard.string(forKey: Self.regularWindowFrameDefaultsKey) {
            let savedFrame = NSRectFromString(serializedFrame)

            if !savedFrame.equalTo(.zero) && isRegularWindowFrame(savedFrame) {
                applyWindowFrame(clampToVisibleScreen(savedFrame), animated: animated)
                return
            }
        }

        applyWindowFrame(targetFrame(forContentSize: Self.defaultContentSize), animated: animated)
    }

    private func isRegularWindowFrame(_ frame: NSRect) -> Bool {
        let compactFrame = targetFrame(forContentSize: Self.focusOnlyContentSize)
        return frame.width > compactFrame.width + 24 || frame.height > compactFrame.height + 24
    }

    private func targetFrame(forContentSize contentSize: NSSize) -> NSRect {
        let targetSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        var frame = window.frame
        frame.origin.y += frame.height - targetSize.height
        frame.size = targetSize
        return clampToVisibleScreen(frame)
    }

    private func clampToVisibleScreen(_ frame: NSRect) -> NSRect {
        guard let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return frame
        }

        var clampedFrame = frame
        clampedFrame.origin.x = min(
            max(clampedFrame.origin.x, visibleFrame.minX),
            visibleFrame.maxX - clampedFrame.width
        )
        clampedFrame.origin.y = min(
            max(clampedFrame.origin.y, visibleFrame.minY),
            visibleFrame.maxY - clampedFrame.height
        )
        return clampedFrame
    }

    private func applyWindowFrame(_ frame: NSRect, animated: Bool) {
        window.setFrame(frame, display: true, animate: animated)
    }

    @objc private func togglePinnedFromButton(_ sender: Any?) {
        togglePinned()
    }

    @objc private func toggleFocusOnlyFromButton(_ sender: Any?) {
        toggleFocusOnly()
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
