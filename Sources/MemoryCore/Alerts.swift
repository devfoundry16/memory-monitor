import Foundation

/// A macOS system sound (from /System/Library/Sounds, e.g. "Sosumi"), played `repeats` times in a row.
public struct AlertSound: Codable, Sendable, Hashable {
    public var name: String
    public var repeats: Int

    public init(name: String, repeats: Int = 1) {
        self.name = name
        self.repeats = repeats
    }
}

/// The text and sound of one kind of alert.
public struct AlertMessage: Codable, Sendable, Hashable {
    public var text: String
    public var sound: AlertSound

    public init(text: String, sound: AlertSound) {
        self.text = text
        self.sound = sound
    }
}

// MARK: - Reminders

public enum ReminderSchedule: Codable, Sendable, Hashable {
    case once(Date)
    case daily(hour: Int, minute: Int)
    /// `days` are Calendar weekdays: 1 = Sunday … 7 = Saturday.
    case weekdays(days: Set<Int>, hour: Int, minute: Int)
    case every(minutes: Int, from: Date)

    /// The first time strictly after `date` the reminder goes off, or `nil` if it never will again.
    public func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .once(let at):
            return at > date ? at : nil
        case .daily(let hour, let minute):
            return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                     matchingPolicy: .nextTime)
        case .weekdays(let days, let hour, let minute):
            return days.compactMap {
                calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: $0),
                                  matchingPolicy: .nextTime)
            }.min()
        case .every(let minutes, let start):
            guard minutes > 0 else { return nil }
            if date < start { return start }
            let step = TimeInterval(minutes * 60)
            return start.addingTimeInterval((floor(date.timeIntervalSince(start) / step) + 1) * step)
        }
    }
}

public struct Reminder: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var enabled: Bool
    public var title: String
    public var body: String
    public var schedule: ReminderSchedule
    public var sound: AlertSound

    public init(id: UUID = UUID(), enabled: Bool = true, title: String, body: String = "",
                schedule: ReminderSchedule, sound: AlertSound = AlertSound(name: "Glass")) {
        self.id = id
        self.enabled = enabled
        self.title = title
        self.body = body
        self.schedule = schedule
        self.sound = sound
    }
}

// MARK: - IP watch

/// Checks, every few minutes, which country a machine's outbound IP is in (from this Mac,
/// or over SSH), and alerts when it leaves the expected country, when the check fails, and
/// when it comes back.
public struct IPWatchSettings: Codable, Sendable, Hashable {
    public var enabled = false
    /// `user@host` to check over SSH; empty checks this Mac's own IP.
    public var sshTarget = ""
    /// SSH private key; empty uses ssh's default keys.
    public var keyPath = ""
    /// systemd unit on the SSH host that runs the VPN, e.g. "wg-quick@us-sea", for the
    /// Restart VPN button. Optional so settings saved before it existed still load.
    public var vpnService: String?
    public var expectedCountry = "US"
    public var intervalMinutes = 5
    public var title = "IP Watch"
    public var notExpected = AlertMessage(
        text: "IP {ip} is in {country}, not {expected}. The VPN may be down.",
        sound: AlertSound(name: "Sosumi", repeats: 3))
    public var failed = AlertMessage(
        text: "Can't check the IP: host unreachable or VPN stalled.",
        sound: AlertSound(name: "Sosumi", repeats: 3))
    public var recovered = AlertMessage(
        text: "Back on a {expected} IP: {ip}",
        sound: AlertSound(name: "Glass"))

    public init() {}

    public func message(for event: IPEvent) -> AlertMessage {
        switch event {
        case .notExpected: notExpected
        case .failed: failed
        case .recovered: recovered
        }
    }
}

public enum IPResult: Sendable, Hashable {
    case located(ip: String, country: String)
    case failed(String)
}

public enum IPEvent: Sendable, Hashable, CaseIterable {
    case notExpected, failed, recovered
}

public enum IPWatch {
    /// What is remembered between checks: the country, or "UNKNOWN" when the check failed.
    public static func state(of result: IPResult) -> String {
        if case .located(_, let country) = result { return country.uppercased() }
        return "UNKNOWN"
    }

    /// The alert for going from `previous` (a saved `state`, `nil` on the first check) to
    /// `result`, or `nil` when nothing changed. A new IP in the same country is not a change.
    public static func event(previous: String?, result: IPResult, expected: String) -> IPEvent? {
        let current = state(of: result)
        guard current != previous else { return nil }
        if current == "UNKNOWN" { return .failed }
        if current == expected.uppercased() { return previous == nil ? nil : .recovered }
        return .notExpected
    }

    /// Fills in `{ip}`, `{country}` and `{expected}`.
    public static func fill(_ template: String, ip: String?, country: String?, expected: String) -> String {
        template
            .replacingOccurrences(of: "{ip}", with: ip ?? "unknown")
            .replacingOccurrences(of: "{country}", with: country ?? "unknown")
            .replacingOccurrences(of: "{expected}", with: expected)
    }

    /// Reads ipinfo.io's JSON.
    public static func parse(_ data: Data) -> IPResult {
        struct Info: Decodable { let ip: String; let country: String }
        guard let info = try? JSONDecoder().decode(Info.self, from: data) else {
            return .failed("Unexpected reply: " + String(decoding: data.prefix(200), as: UTF8.self))
        }
        return .located(ip: info.ip, country: info.country)
    }

    /// A systemd unit name such as `wg-quick@us-sea`: safe to put in a remote shell command.
    public static func isValidServiceName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9@._:-]*/) != nil
    }

    /// `host` or `user@host` made of letters, digits, `.`, `_` and `-`, not starting with `-`,
    /// so the value can only ever be read by ssh as a destination.
    public static func isValidSSHTarget(_ target: String) -> Bool {
        target.wholeMatch(of: /[A-Za-z0-9._][A-Za-z0-9._-]*(@[A-Za-z0-9._][A-Za-z0-9._-]*)?/) != nil
    }
}
