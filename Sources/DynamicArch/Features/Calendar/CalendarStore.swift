import AppKit
import EventKit
import SwiftUI

/// Upcoming events for the glance view. Read-only, refreshed on EventKit change
/// notifications instead of polling.
@MainActor
@Observable
final class CalendarStore {
    static let shared = CalendarStore()

    struct Event: Identifiable, Equatable {
        let id: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var location: String?
        var color: Color

        var isNow: Bool { start <= .now && end > .now }
        var timeDescription: String {
            if isAllDay { return "All day" }
            return start.formatted(date: .omitted, time: .shortened)
        }
    }

    private(set) var events: [Event] = []
    private(set) var accessGranted = false

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    private init() {}

    var needsAuthorization: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    func start() {
        guard Preferences.shared.calendarEnabled, observer == nil else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            accessGranted = true
            refresh()
        case .notDetermined:
            // The user just switched the calendar on: this is the right moment
            // to ask, and the only one.
            requestAccess()
        default:
            accessGranted = false
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
                                                          object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                self?.accessGranted = granted
                if granted { self?.refresh() }
            }
        }
    }

    func refresh() {
        guard accessGranted else { return }
        let calendar = Calendar.current
        let start = Date.now
        let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: start)) ?? start
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-3600),
                                                  end: end,
                                                  calendars: nil)
        let found = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(12)
            .map { event in
                Event(id: event.eventIdentifier ?? UUID().uuidString,
                      title: event.title ?? "Event",
                      start: event.startDate,
                      end: event.endDate,
                      isAllDay: event.isAllDay,
                      location: event.location,
                      color: Color(nsColor: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue))
            }
        withAnimation(Motion.content) { events = Array(found) }
    }

    var nextEvent: Event? {
        events.first { $0.end > .now }
    }
}
