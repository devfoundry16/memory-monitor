import Foundation
import Testing
@testable import MemoryCore

@Suite struct ReminderScheduleTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func onceFiresOnlyInTheFuture() {
        let at = date(2026, 11, 7, 9, 0)
        #expect(ReminderSchedule.once(at).nextFire(after: date(2026, 11, 7, 8, 0), calendar: calendar) == at)
        #expect(ReminderSchedule.once(at).nextFire(after: at, calendar: calendar) == nil)
    }

    @Test func dailyRollsToTomorrow() {
        let s = ReminderSchedule.daily(hour: 9, minute: 30)
        #expect(s.nextFire(after: date(2026, 11, 7, 8, 0), calendar: calendar) == date(2026, 11, 7, 9, 30))
        #expect(s.nextFire(after: date(2026, 11, 7, 9, 30), calendar: calendar) == date(2026, 11, 8, 9, 30))
    }

    @Test func dailyAcrossDaylightSavingEnd() {
        // US clocks go back on 2026-11-01; 9:00 is still 9:00 local the next day.
        let s = ReminderSchedule.daily(hour: 9, minute: 0)
        #expect(s.nextFire(after: date(2026, 10, 31, 10, 0), calendar: calendar) == date(2026, 11, 1, 9, 0))
    }

    @Test func weekdaysWrapToNextWeek() {
        // 2026-11-07 is a Saturday. Mon (2) and Fri (6) at 18:00.
        let s = ReminderSchedule.weekdays(days: [2, 6], hour: 18, minute: 0)
        #expect(s.nextFire(after: date(2026, 11, 7, 12, 0), calendar: calendar) == date(2026, 11, 9, 18, 0))
        #expect(s.nextFire(after: date(2026, 11, 9, 18, 0), calendar: calendar) == date(2026, 11, 13, 18, 0))
        #expect(ReminderSchedule.weekdays(days: [], hour: 9, minute: 0).nextFire(after: .now, calendar: calendar) == nil)
    }

    @Test func everyStaysOnItsGrid() {
        let start = date(2026, 11, 7, 9, 0)
        let s = ReminderSchedule.every(minutes: 45, from: start)
        #expect(s.nextFire(after: date(2026, 11, 7, 8, 0), calendar: calendar) == start)
        #expect(s.nextFire(after: start, calendar: calendar) == date(2026, 11, 7, 9, 45))
        #expect(s.nextFire(after: date(2026, 11, 7, 10, 0), calendar: calendar) == date(2026, 11, 7, 10, 30))
        #expect(ReminderSchedule.every(minutes: 0, from: start).nextFire(after: start, calendar: calendar) == nil)
    }

    @Test func remindersRoundTripThroughJSON() throws {
        let r = Reminder(title: "Stand up", schedule: .weekdays(days: [2, 3], hour: 10, minute: 0))
        let back = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }
}

@Suite struct IPWatchTests {
    let us = IPResult.located(ip: "1.2.3.4", country: "US")
    let us2 = IPResult.located(ip: "5.6.7.8", country: "US")
    let la = IPResult.located(ip: "9.9.9.9", country: "LA")
    let fail = IPResult.failed("timeout")

    @Test func alertsOnlyOnChanges() {
        #expect(IPWatch.event(previous: nil, result: us, expected: "US") == nil)
        #expect(IPWatch.event(previous: "US", result: us2, expected: "US") == nil)
        #expect(IPWatch.event(previous: "US", result: la, expected: "US") == .notExpected)
        #expect(IPWatch.event(previous: "LA", result: la, expected: "US") == nil)
        #expect(IPWatch.event(previous: "LA", result: fail, expected: "US") == .failed)
        #expect(IPWatch.event(previous: "UNKNOWN", result: fail, expected: "US") == nil)
        #expect(IPWatch.event(previous: "UNKNOWN", result: us, expected: "us") == .recovered)
        #expect(IPWatch.event(previous: nil, result: fail, expected: "US") == .failed)
        #expect(IPWatch.event(previous: nil, result: la, expected: "US") == .notExpected)
    }

    @Test func fillsPlaceholders() {
        let text = IPWatch.fill("IP {ip} is in {country}, not {expected}.", ip: "9.9.9.9", country: "LA", expected: "US")
        #expect(text == "IP 9.9.9.9 is in LA, not US.")
        #expect(IPWatch.fill("{ip}", ip: nil, country: nil, expected: "US") == "unknown")
    }

    @Test func parsesIPInfo() {
        let json = #"{"ip":"1.2.3.4","city":"Seattle","country":"US","org":"x"}"#
        #expect(IPWatch.parse(Data(json.utf8)) == us)
        guard case .failed = IPWatch.parse(Data("<html>".utf8)) else { Issue.record("expected failure"); return }
    }

    @Test func sshTargetValidation() {
        #expect(IPWatch.isValidSSHTarget("admin@192.168.1.20"))
        #expect(IPWatch.isValidSSHTarget("my-vm.local"))
        #expect(!IPWatch.isValidSSHTarget(""))
        #expect(!IPWatch.isValidSSHTarget("-oProxyCommand=evil"))
        #expect(!IPWatch.isValidSSHTarget("user@-oProxyCommand=x"))
        #expect(!IPWatch.isValidSSHTarget("host; rm -rf ~"))
        #expect(!IPWatch.isValidSSHTarget("a@b@c"))
    }
}

@Suite struct VPNServiceTests {
    @Test func serviceNameValidation() {
        #expect(IPWatch.isValidServiceName("wg-quick@us-sea"))
        #expect(IPWatch.isValidServiceName("openvpn-client@surfshark.service"))
        #expect(!IPWatch.isValidServiceName(""))
        #expect(!IPWatch.isValidServiceName("-x"))
        #expect(!IPWatch.isValidServiceName("a; reboot"))
        #expect(!IPWatch.isValidServiceName("a $(id)"))
    }

    @Test func settingsSavedBeforeVPNServiceStillLoad() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(IPWatchSettings())) as! [String: Any]
        old["vpnService"] = nil
        old["sshTarget"] = "admin@vm"
        let loaded = try JSONDecoder().decode(IPWatchSettings.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(loaded.sshTarget == "admin@vm")
        #expect(loaded.vpnService == nil)
    }
}
