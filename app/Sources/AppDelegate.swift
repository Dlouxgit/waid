import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var trackerService: TrackerService?
    private var bridgeController: WebBridgeController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        true
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
