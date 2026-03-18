import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var trackerService: TrackerService?
    private var bridgeController: WebBridgeController?
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Waid"

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        do {
            let webRootURL = try resourceURL(named: "web")
            let store = try UsageStore(dataFileURL: Paths.usageDataFileURL())
            let trackerService = TrackerService(store: store) { _ in }
            let bridgeController = try WebBridgeController(webRootURL: webRootURL) { [weak trackerService] in
                trackerService?.snapshot() ?? DashboardSnapshot.empty()
            }

            bridgeController.showWindow()

            self.bridgeController = bridgeController
            self.trackerService = trackerService

            try trackerService.start()
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            presentStartupFailure(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trackerService?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showDashboard(nil)
        }

        return true
    }

    @objc private func showAboutPanel(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: appName
        ]
        NSApp.orderFrontStandardAboutPanel(options)
    }

    @objc private func showDashboard(_ sender: Any?) {
        bridgeController?.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reloadDashboard(_ sender: Any?) {
        bridgeController?.reload()
        showDashboard(sender)
    }

    @objc private func closeDashboardWindow(_ sender: Any?) {
        bridgeController?.closeWindow()
    }

    @objc private func togglePinned(_ sender: Any?) {
        bridgeController?.togglePinned()
    }

    @objc private func toggleFocusOnly(_ sender: Any?) {
        bridgeController?.toggleFocusOnly()
    }

    @objc private func openDataFolder(_ sender: Any?) {
        let folderURL = Paths.usageDataFileURL().deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        } catch {
            presentOperationFailure(
                title: "Waid could not open the data folder.",
                description: error.localizedDescription
            )
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu(title: appName)

        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: appName)
        mainMenu.addItem(appMenuItem)
        mainMenu.setSubmenu(appMenu, for: appMenuItem)

        appMenu.addItem(makeMenuItem(title: "About \(appName)", action: #selector(showAboutPanel(_:)), keyEquivalent: "", target: self))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(makeMenuItem(title: "Show Dashboard", action: #selector(showDashboard(_:)), keyEquivalent: "1", target: self))
        appMenu.addItem(makeMenuItem(title: "Reload Dashboard", action: #selector(reloadDashboard(_:)), keyEquivalent: "r", target: self))
        appMenu.addItem(
            makeMenuItem(
                title: "Open Data Folder",
                action: #selector(openDataFolder(_:)),
                keyEquivalent: "d",
                modifiers: [.command, .shift],
                target: self
            )
        )
        appMenu.addItem(NSMenuItem.separator())

        let servicesMenuItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        appMenu.addItem(servicesMenuItem)
        appMenu.setSubmenu(servicesMenu, for: servicesMenuItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(makeMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h", target: nil))
        appMenu.addItem(
            makeMenuItem(
                title: "Hide Others",
                action: #selector(NSApplication.hideOtherApplications(_:)),
                keyEquivalent: "h",
                modifiers: [.command, .option],
                target: nil
            )
        )
        appMenu.addItem(
            makeMenuItem(
                title: "Show All",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                keyEquivalent: "",
                target: nil
            )
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(makeMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", target: nil))

        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        mainMenu.addItem(fileMenuItem)
        mainMenu.setSubmenu(fileMenu, for: fileMenuItem)
        fileMenu.addItem(makeMenuItem(title: "Show Dashboard", action: #selector(showDashboard(_:)), keyEquivalent: "1", target: self))
        fileMenu.addItem(makeMenuItem(title: "Open Data Folder", action: #selector(openDataFolder(_:)), keyEquivalent: "d", modifiers: [.command, .shift], target: self))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(makeMenuItem(title: "Close Window", action: #selector(closeDashboardWindow(_:)), keyEquivalent: "w", target: self))

        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        mainMenu.addItem(viewMenuItem)
        mainMenu.setSubmenu(viewMenu, for: viewMenuItem)
        viewMenu.addItem(makeMenuItem(title: "Reload Dashboard", action: #selector(reloadDashboard(_:)), keyEquivalent: "r", target: self))
        viewMenu.addItem(
            makeMenuItem(
                title: "Pin Window on Top",
                action: #selector(togglePinned(_:)),
                keyEquivalent: "p",
                modifiers: [.command, .shift],
                target: self
            )
        )
        viewMenu.addItem(
            makeMenuItem(
                title: "Show Current Focus Only",
                action: #selector(toggleFocusOnly(_:)),
                keyEquivalent: "",
                target: self
            )
        )
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(
            makeMenuItem(
                title: "Enter Full Screen",
                action: #selector(NSWindow.toggleFullScreen(_:)),
                keyEquivalent: "f",
                modifiers: [.command, .control],
                target: nil
            )
        )

        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        mainMenu.addItem(windowMenuItem)
        mainMenu.setSubmenu(windowMenu, for: windowMenuItem)
        windowMenu.addItem(
            makeMenuItem(
                title: "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)),
                keyEquivalent: "m",
                target: nil
            )
        )
        windowMenu.addItem(
            makeMenuItem(
                title: "Zoom",
                action: #selector(NSWindow.performZoom(_:)),
                keyEquivalent: "",
                target: nil
            )
        )
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(
            makeMenuItem(
                title: "Bring All to Front",
                action: #selector(NSApplication.arrangeInFront(_:)),
                keyEquivalent: "",
                target: nil
            )
        )
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func resourceURL(named name: String) throws -> URL {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw AppError.missingResource("App bundle resources are unavailable.")
        }

        let targetURL = resourceURL.appendingPathComponent(name, isDirectory: true)

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw AppError.missingResource("Missing bundled resource: \(name)")
        }

        return targetURL
    }

    private func presentStartupFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Waid could not start."
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func presentOperationFailure(title: String, description: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = description
        alert.runModal()
    }

    private func makeMenuItem(
        title: String,
        action: Selector?,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePinned(_:)) {
            menuItem.state = bridgeController?.isPinned == true ? .on : .off
            return bridgeController != nil
        }

        if menuItem.action == #selector(toggleFocusOnly(_:)) {
            let focusOnly = bridgeController?.isFocusOnly == true
            menuItem.state = focusOnly ? .on : .off
            menuItem.title = focusOnly ? "Show Full Dashboard" : "Show Current Focus Only"
            return bridgeController != nil
        }

        return true
    }
}

enum AppError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let message):
            return message
        }
    }
}
