import AppKit
import Foundation

struct AppIdentity {
    let appName: String?
    let bundleIdentifier: String?

    init(appName: String?, bundleIdentifier: String?) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
    }

    init(application: NSRunningApplication?) {
        self.appName = application?.localizedName
        self.bundleIdentifier = application?.bundleIdentifier
    }

    var isEmpty: Bool {
        (appName?.isEmpty ?? true) && (bundleIdentifier?.isEmpty ?? true)
    }
}

struct CompletedSession: Codable {
    let appName: String?
    let bundleIdentifier: String?
    let startedAt: String
    let endedAt: String
    let durationMs: Int64
    let source: String
}

struct ActiveSession: Codable {
    let appName: String?
    let bundleIdentifier: String?
    let startedAt: String
    var lastSeenAt: String
}

struct UsageData: Codable {
    var version = 1
    var completedSessions: [CompletedSession] = []
    var activeSession: ActiveSession? = nil
}

struct DashboardSnapshot: Codable {
    struct TodaySnapshot: Codable {
        let date: String
        let totalTrackedMs: Int64
        let apps: [AppSummary]
        let sessions: [SessionSummary]
    }

    struct AppSummary: Codable {
        let appName: String?
        let bundleIdentifier: String?
        let totalMs: Int64
        let share: Double
    }

    struct SessionSummary: Codable {
        let appName: String?
        let bundleIdentifier: String?
        let startedAt: String
        let endedAt: String
        let durationMs: Int64
        let isActive: Bool
    }

    struct CurrentSession: Codable {
        let appName: String?
        let bundleIdentifier: String?
        let startedAt: String
        let elapsedMs: Int64
    }

    let generatedAt: String
    let today: TodaySnapshot
    let current: CurrentSession?

    static func empty() -> DashboardSnapshot {
        DashboardSnapshot(
            generatedAt: ISO8601Formatter.shared.string(from: Date()),
            today: TodaySnapshot(
                date: "0000-00-00",
                totalTrackedMs: 0,
                apps: [],
                sessions: []
            ),
            current: nil
        )
    }
}

enum Paths {
    static func usageDataFileURL() -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Waid", isDirectory: true)
        return root.appendingPathComponent("usage-data.json")
    }
}

final class UsageStore {
    private let dataFileURL: URL
    private var data = UsageData()

    init(dataFileURL: URL) throws {
        self.dataFileURL = dataFileURL
        try FileManager.default.createDirectory(
            at: dataFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func load() throws {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
            data = UsageData()
            try persist()
            return
        }

        let contents = try Data(contentsOf: dataFileURL)
        data = try JSONDecoder().decode(UsageData.self, from: contents)
    }

    func recoverActiveSession() throws {
        guard let active = data.activeSession else {
            return
        }

        let startedAt = date(from: active.startedAt)
        let endedAt = date(from: active.lastSeenAt)

        if endedAt > startedAt {
            data.completedSessions.append(
                CompletedSession(
                    appName: active.appName,
                    bundleIdentifier: active.bundleIdentifier,
                    startedAt: isoString(startedAt),
                    endedAt: isoString(endedAt),
                    durationMs: Int64(endedAt.timeIntervalSince(startedAt) * 1000),
                    source: "recovered"
                )
            )
        }

        data.activeSession = nil
        try persist()
    }

    func beginActiveSession(app: AppIdentity, startedAt: Date) throws {
        data.activeSession = ActiveSession(
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            startedAt: isoString(startedAt),
            lastSeenAt: isoString(startedAt)
        )
        try persist()
    }

    func touchActiveSession(at: Date) throws {
        guard var active = data.activeSession else {
            return
        }

        active.lastSeenAt = isoString(at)
        data.activeSession = active
        try persist()
    }

    func finishActiveSession(at endedAt: Date, source: String) throws {
        guard let active = data.activeSession else {
            return
        }

        let startedAt = date(from: active.startedAt)

        if endedAt > startedAt {
            data.completedSessions.append(
                CompletedSession(
                    appName: active.appName,
                    bundleIdentifier: active.bundleIdentifier,
                    startedAt: isoString(startedAt),
                    endedAt: isoString(endedAt),
                    durationMs: Int64(endedAt.timeIntervalSince(startedAt) * 1000),
                    source: source
                )
            )
        }

        data.activeSession = nil
        try persist()
    }

    func buildSnapshot(now: Date = Date()) -> DashboardSnapshot {
        let dayStart = startOfLocalDay(now)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        var totals: [String: (appName: String?, bundleIdentifier: String?, totalMs: Int64)] = [:]
        var sessions: [DashboardSnapshot.SessionSummary] = []

        func addSession(
            appName: String?,
            bundleIdentifier: String?,
            startedAt: String,
            endedAt: String,
            isActive: Bool
        ) {
            let sessionStart = date(from: startedAt)
            let sessionEnd = date(from: endedAt)
            let durationMs = overlapMs(
                sessionStart: sessionStart,
                sessionEnd: sessionEnd,
                rangeStart: dayStart,
                rangeEnd: dayEnd
            )

            if durationMs <= 0 {
                return
            }

            let clippedStart = max(sessionStart, dayStart)
            let clippedEnd = min(sessionEnd, dayEnd)
            let key = bundleIdentifier ?? appName ?? "unknown-app"
            let previous = totals[key] ?? (appName, bundleIdentifier, 0)
            totals[key] = (previous.appName, previous.bundleIdentifier, previous.totalMs + durationMs)
            sessions.append(
                DashboardSnapshot.SessionSummary(
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    startedAt: isoString(clippedStart),
                    endedAt: isoString(clippedEnd),
                    durationMs: durationMs,
                    isActive: isActive
                )
            )
        }

        for session in data.completedSessions {
            addSession(
                appName: session.appName,
                bundleIdentifier: session.bundleIdentifier,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                isActive: false
            )
        }

        if let active = data.activeSession {
            addSession(
                appName: active.appName,
                bundleIdentifier: active.bundleIdentifier,
                startedAt: active.startedAt,
                endedAt: isoString(now),
                isActive: true
            )
        }

        sessions.sort { $0.startedAt > $1.startedAt }

        let totalTrackedMs = totals.values.reduce(Int64(0)) { $0 + $1.totalMs }
        let apps = totals.values
            .map {
                DashboardSnapshot.AppSummary(
                    appName: $0.appName,
                    bundleIdentifier: $0.bundleIdentifier,
                    totalMs: $0.totalMs,
                    share: totalTrackedMs == 0 ? 0 : Double($0.totalMs) / Double(totalTrackedMs)
                )
            }
            .sorted { $0.totalMs > $1.totalMs }

        let current: DashboardSnapshot.CurrentSession?

        if let active = data.activeSession {
            let startedAt = date(from: active.startedAt)
            let elapsedMs = max(Int64(now.timeIntervalSince(startedAt) * 1000), 0)
            current = DashboardSnapshot.CurrentSession(
                appName: active.appName,
                bundleIdentifier: active.bundleIdentifier,
                startedAt: active.startedAt,
                elapsedMs: elapsedMs
            )
        } else {
            current = nil
        }

        return DashboardSnapshot(
            generatedAt: isoString(now),
            today: DashboardSnapshot.TodaySnapshot(
                date: localDateKey(now),
                totalTrackedMs: totalTrackedMs,
                apps: apps,
                sessions: sessions
            ),
            current: current
        )
    }

    func hasSameActiveApp(_ app: AppIdentity) -> Bool {
        guard let active = data.activeSession else {
            return false
        }

        if let left = active.bundleIdentifier,
           let right = app.bundleIdentifier,
           left == right {
            return true
        }

        return active.appName == app.appName
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contents = try encoder.encode(data)
        try contents.write(to: dataFileURL, options: .atomic)
    }

    private func isoString(_ date: Date) -> String {
        ISO8601Formatter.shared.string(from: date)
    }

    private func date(from value: String) -> Date {
        ISO8601Formatter.shared.date(from: value) ?? Date()
    }

    private func localDateKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = String(components.year ?? 0)
        let month = String(components.month ?? 0).leftPad(toLength: 2)
        let day = String(components.day ?? 0).leftPad(toLength: 2)
        return "\(year)-\(month)-\(day)"
    }

    private func startOfLocalDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func overlapMs(sessionStart: Date, sessionEnd: Date, rangeStart: Date, rangeEnd: Date) -> Int64 {
        let start = max(sessionStart, rangeStart)
        let end = min(sessionEnd, rangeEnd)
        return max(Int64(end.timeIntervalSince(start) * 1000), 0)
    }
}

final class TrackerService {
    private let workspace = NSWorkspace.shared
    private let store: UsageStore
    private let onUpdate: (DashboardSnapshot) -> Void
    private var observers: [NSObjectProtocol] = []
    private var heartbeatTimer: Timer?
    private var started = false

    init(store: UsageStore, onUpdate: @escaping (DashboardSnapshot) -> Void) {
        self.store = store
        self.onUpdate = onUpdate
    }

    func start() throws {
        guard !started else {
            return
        }

        try store.load()
        try store.recoverActiveSession()
        installObservers()
        installHeartbeat()
        try handleActivation(AppIdentity(application: workspace.frontmostApplication), at: Date())
        started = true
        onUpdate(store.buildSnapshot())
    }

    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }

        observers.removeAll()

        try? store.finishActiveSession(at: Date(), source: "shutdown")
        onUpdate(store.buildSnapshot())
    }

    func snapshot() -> DashboardSnapshot {
        store.buildSnapshot()
    }

    private func installObservers() {
        let center = workspace.notificationCenter

        observers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.processActivation(application: application ?? self?.workspace.frontmostApplication)
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.processPause(source: "pause")
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.processActivation(application: self?.workspace.frontmostApplication)
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.processPause(source: "pause")
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.processActivation(application: self?.workspace.frontmostApplication)
            }
        )
    }

    private func installHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            do {
                try self.store.touchActiveSession(at: Date())
                self.onUpdate(self.store.buildSnapshot())
            } catch {
                NSLog("Heartbeat failed: \(error.localizedDescription)")
            }
        }
    }

    private func processActivation(application: NSRunningApplication?) {
        do {
            try handleActivation(AppIdentity(application: application), at: Date())
            onUpdate(store.buildSnapshot())
        } catch {
            NSLog("Activation handling failed: \(error.localizedDescription)")
        }
    }

    private func processPause(source: String) {
        do {
            try store.finishActiveSession(at: Date(), source: source)
            onUpdate(store.buildSnapshot())
        } catch {
            NSLog("Pause handling failed: \(error.localizedDescription)")
        }
    }

    private func handleActivation(_ app: AppIdentity, at: Date) throws {
        if app.isEmpty {
            try store.finishActiveSession(at: at, source: "missing-app")
            return
        }

        if store.hasSameActiveApp(app) {
            try store.touchActiveSession(at: at)
            return
        }

        try store.finishActiveSession(at: at, source: "switch")
        try store.beginActiveSession(app: app, startedAt: at)
    }
}

enum ISO8601Formatter {
    static let shared: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension String {
    func leftPad(toLength: Int) -> String {
        if count >= toLength {
            return self
        }

        return String(repeating: "0", count: toLength - count) + self
    }
}
