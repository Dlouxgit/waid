import AppKit
import Dispatch
import Foundation

struct TrackerEvent: Codable {
    let type: String
    let at: String
    let appName: String?
    let bundleIdentifier: String?
    let processIdentifier: Int32?
}

final class EventEmitter {
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func emit(type: String, application: NSRunningApplication? = nil, at date: Date = Date()) {
        let event = TrackerEvent(
            type: type,
            at: formatter.string(from: date),
            appName: application?.localizedName,
            bundleIdentifier: application?.bundleIdentifier,
            processIdentifier: application?.processIdentifier
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(event) else {
            return
        }

        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}

final class Tracker {
    private let workspace = NSWorkspace.shared
    private let emitter = EventEmitter()
    private var observers: [Any] = []
    private var signalSources: [DispatchSourceSignal] = []

    func start() {
        let center = workspace.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.emitter.emit(type: "activate", application: application ?? self?.workspace.frontmostApplication)
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.emitter.emit(type: "pause")
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else {
                return
            }
            self.emitter.emit(type: "resume")
            self.emitter.emit(type: "current", application: self.workspace.frontmostApplication)
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.emitter.emit(type: "pause")
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else {
                return
            }
            self.emitter.emit(type: "resume")
            self.emitter.emit(type: "current", application: self.workspace.frontmostApplication)
        })

        emitter.emit(type: "current", application: workspace.frontmostApplication)
        installSignalHandlers()
        RunLoop.main.run()
    }

    private func installSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        signalSources = [SIGINT, SIGTERM].map { signalNumber in
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.emitter.emit(type: "shutdown")
                exit(0)
            }
            source.resume()
            return source
        }
    }
}

Tracker().start()
