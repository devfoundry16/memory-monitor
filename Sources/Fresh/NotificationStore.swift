import AppKit
import MemoryCore
import Observation
import UserNotifications

/// The Alerts tab: the IP watch and the user's own reminders. Saved in UserDefaults, run by
/// one timer while Fresh is open. Reminders that fall due while Fresh is quit are skipped.
@MainActor
@Observable
final class NotificationStore {
    var reminders: [Reminder] {
        didSet { save(reminders, Self.remindersKey); recomputeDue(); askPermissionIfNeeded() }
    }
    var ipWatch: IPWatchSettings {
        didSet { save(ipWatch, Self.ipWatchKey); askPermissionIfNeeded() }
    }
    /// When each enabled reminder next goes off.
    private(set) var nextDue: [UUID: Date] = [:]
    private(set) var lastCheck: (date: Date, result: IPResult)?
    private(set) var checking = false
    private(set) var restarting = false
    /// What the last Restart VPN did, shown under the button.
    private(set) var restartMessage: String?
    /// "Off" in System Settings ▸ Notifications, so banners won't show (sounds still play).
    private(set) var notificationsDenied = false

    /// System sound names for the pickers.
    let soundNames: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    @ObservationIgnored private var ipState: String? {
        didSet { UserDefaults.standard.set(ipState, forKey: Self.ipStateKey) }
    }
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var askedPermission = false
    @ObservationIgnored private let bannerDelegate = BannerDelegate()

    private static let remindersKey = "reminders"
    private static let ipWatchKey = "ipWatch"
    private static let ipStateKey = "ipWatchState"

    /// `swift run` has no bundle, and UNUserNotificationCenter crashes without one.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    init() {
        reminders = Self.load(Self.remindersKey) ?? []
        ipWatch = Self.load(Self.ipWatchKey) ?? IPWatchSettings()
        ipState = UserDefaults.standard.string(forKey: Self.ipStateKey)
        recomputeDue()
    }

    func start() {
        center?.delegate = bannerDelegate
        askPermissionIfNeeded()
        // 10 s keeps reminders within seconds of their time at negligible cost.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 2
        tick()
    }

    private func tick() {
        let now = Date()
        for reminder in reminders where reminder.enabled {
            guard let due = nextDue[reminder.id], due <= now else { continue }
            post(title: reminder.title, body: reminder.body, sound: reminder.sound)
            if case .once = reminder.schedule { setEnabled(reminder.id, false) }
        }
        recomputeDue(from: now)

        if ipWatch.enabled, !checking,
           lastAttempt.map({ now.timeIntervalSince($0) >= Double(max(ipWatch.intervalMinutes, 1) * 60) }) ?? true {
            Task { await checkNow() }
        }
    }

    private func recomputeDue(from now: Date = Date()) {
        var due: [UUID: Date] = [:]
        for reminder in reminders where reminder.enabled {
            due[reminder.id] = reminder.schedule.nextFire(after: now)
        }
        if due != nextDue { nextDue = due }
    }

    // MARK: Reminders

    func add(_ reminder: Reminder) { reminders.append(reminder) }

    func update(_ reminder: Reminder) {
        guard let i = reminders.firstIndex(where: { $0.id == reminder.id }) else { return add(reminder) }
        reminders[i] = reminder
    }

    func delete(_ reminder: Reminder) { reminders.removeAll { $0.id == reminder.id } }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].enabled = enabled
    }

    func test(_ reminder: Reminder) { post(title: reminder.title, body: reminder.body, sound: reminder.sound) }

    // MARK: IP watch

    /// Runs one check now and alerts if the country changed since the last one.
    func checkNow() async {
        guard !checking else { return }
        checking = true
        lastAttempt = Date()
        let settings = ipWatch
        let result = await Self.lookUp(settings)
        checking = false
        lastCheck = (Date(), result)
        let previous = ipState
        ipState = IPWatch.state(of: result)
        if let event = IPWatch.event(previous: previous, result: result, expected: settings.expectedCountry) {
            alert(event, result: result)
        }
    }

    /// Shows the event's alert with sample values, without touching the saved state.
    func testAlert(_ event: IPEvent) {
        let sample: IPResult = switch event {
        case .notExpected: .located(ip: "203.0.113.7", country: "LA")
        case .failed: .failed("test")
        case .recovered: .located(ip: "203.0.113.8", country: ipWatch.expectedCountry)
        }
        alert(event, result: sample)
    }

    private func alert(_ event: IPEvent, result: IPResult) {
        var ip: String?, country: String?
        if case .located(let i, let c) = result { (ip, country) = (i, c) }
        let message = ipWatch.message(for: event)
        post(title: ipWatch.title,
             body: IPWatch.fill(message.text, ip: ip, country: country, expected: ipWatch.expectedCountry),
             sound: message.sound)
    }

    private nonisolated static func lookUp(_ settings: IPWatchSettings) async -> IPResult {
        let target = settings.sshTarget.trimmingCharacters(in: .whitespaces)
        if target.isEmpty {
            var request = URLRequest(url: URL(string: "https://ipinfo.io/json")!)
            request.timeoutInterval = 15
            do { return IPWatch.parse(try await URLSession.shared.data(for: request).0) } catch {
                return .failed(error.localizedDescription)
            }
        }
        guard IPWatch.isValidSSHTarget(target) else { return .failed("“\(target)” isn't a valid SSH host.") }
        switch await ssh(settings, "curl -s --max-time 10 https://ipinfo.io/json") {
        case .success(let data): return IPWatch.parse(data)
        case .failure(let reason): return .failed(reason.message)
        }
    }

    // MARK: Restarting the VPN

    /// The service to restart, when Restart VPN can work: an SSH host and a valid unit name.
    var restartableService: String? {
        let service = (ipWatch.vpnService ?? "").trimmingCharacters(in: .whitespaces)
        guard IPWatch.isValidSSHTarget(ipWatch.sshTarget.trimmingCharacters(in: .whitespaces)),
              IPWatch.isValidServiceName(service) else { return nil }
        return service
    }

    /// The last check found the IP outside the expected country, or couldn't check.
    var vpnLooksDown: Bool {
        guard let result = lastCheck?.result else { return false }
        return IPWatch.state(of: result) != ipWatch.expectedCountry.uppercased()
    }

    /// Runs `sudo -n systemctl restart <service>` on the SSH host, then checks the IP again.
    func restartVPN() async {
        guard !restarting, let service = restartableService else { return }
        restarting = true
        restartMessage = "Restarting \(service)…"
        let result = await Self.ssh(ipWatch, "sudo -n systemctl restart \(service)")
        switch result {
        case .success:
            restartMessage = "Restarted \(service). Checking again…"
            // The tunnel takes 5–10 s to route again; checking sooner raises a false "check failed".
            try? await Task.sleep(for: .seconds(12))
            restarting = false
            await checkNow()
            restartMessage = "Restarted \(service) at \(Date().formatted(date: .omitted, time: .shortened))."
        case .failure(let reason):
            restarting = false
            restartMessage = reason.message.contains("password is required")
                ? "The host's sudo asks for a password. Allow this one command without a password (see README)."
                : "Couldn't restart \(service): \(reason.message)"
        }
    }

    struct SSHFailure: Error { let message: String }

    /// Runs one fixed command on the SSH host, non-interactively, and returns its output.
    private nonisolated static func ssh(_ settings: IPWatchSettings, _ command: String) async -> Result<Data, SSHFailure> {
        let target = settings.sshTarget.trimmingCharacters(in: .whitespaces)
        var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                    "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2"]
        let key = settings.keyPath.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { args += ["-i", (key as NSString).expandingTildeInPath] }
        args += ["--", target, command]
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return .failure(SSHFailure(message: error.localizedDescription)) }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let reason = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(SSHFailure(message: reason.isEmpty ? "ssh exited with \(process.terminationStatus)" : reason))
            }
            return .success(data)
        }.value
    }

    // MARK: Posting

    private func post(title: String, body: String, sound: AlertSound) {
        if let center {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            // No notification sound: `play` makes it, so it repeats and isn't muted by Focus.
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        play(sound)
    }

    func play(_ sound: AlertSound) {
        guard let player = NSSound(named: NSSound.Name(sound.name)) else { return }
        Task {
            for _ in 0..<min(max(sound.repeats, 1), 10) {
                player.stop()
                player.play()
                try? await Task.sleep(for: .seconds(player.duration + 0.15))
            }
        }
    }

    private func askPermissionIfNeeded() {
        guard !askedPermission, let center, ipWatch.enabled || reminders.contains(where: \.enabled) else { return }
        askedPermission = true
        center.requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor in self.notificationsDenied = !granted }
        }
    }

    // MARK: Saving

    private func save(_ value: some Encodable, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

/// Shows banners even while Fresh's window is in front (macOS hides them by default then).
private final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
