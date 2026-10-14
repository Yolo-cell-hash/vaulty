import EventKit
import Flutter
import UIKit

/// The phone's calendars for lib/services/calendar_service.dart: reads events to
/// import, and keeps Vaulty's own calendar in step with dated items.
///
/// Vaulty's calendar goes where the user's new events go. That's "On My
/// iPhone" when iCloud Calendars is off; otherwise it syncs with that account,
/// and the app says so before turning sync on.
final class CalendarBridge: NSObject, FlutterPlugin {
  private let store = EKEventStore()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "vaulty/calendar", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CalendarBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "hasAccess":
        result(hasAccess)
      case "requestAccess":
        requestAccess(result)
      case "openSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        result(nil)
      case "home":
        let source = home()
        result(["local": source.map { $0.sourceType == .local } ?? true, "name": source.map(name) ?? "this iPhone"])
      case "ensureCalendar":
        result(try ensureCalendar(args["id"] as? String))
      case "removeCalendar":
        if let id = args["id"] as? String, let calendar = store.calendar(withIdentifier: id) {
          try store.removeCalendar(calendar, commit: true)
        }
        result(nil)
      case "upsertEvent":
        result(try upsertEvent(args))
      case "deleteEvent":
        if let id = args["id"] as? String, let event = store.event(withIdentifier: id) {
          try store.remove(event, span: .futureEvents, commit: true)
        }
        result(nil)
      case "events":
        let from = Date(timeIntervalSince1970: (args["from"] as? Double ?? 0) / 1000)
        let to = Date(timeIntervalSince1970: (args["to"] as? Double ?? 0) / 1000)
        let exclude = args["exclude"] as? String
        DispatchQueue.global(qos: .userInitiated).async {
          let found = self.events(from: from, to: to, excluding: exclude)
          DispatchQueue.main.async { result(found) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "CALENDAR", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: Access

  private var hasAccess: Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) { return status == .fullAccess }
    return status == .authorized
  }

  private func requestAccess(_ result: @escaping FlutterResult) {
    let done: (Bool, Error?) -> Void = { granted, _ in
      DispatchQueue.main.async {
        // A store made before access was granted can't see any calendars yet.
        if granted { self.store.reset() }
        result(granted)
      }
    }
    if #available(iOS 17.0, *) {
      store.requestFullAccessToEvents(completion: done)
    } else {
      store.requestAccess(to: .event, completion: done)
    }
  }

  // MARK: Vaulty's calendar

  /// Where new calendars go: the account the user's own new events go to.
  private func home() -> EKSource? {
    store.defaultCalendarForNewEvents?.source
      ?? store.sources.first { $0.sourceType == .local }
      ?? store.sources.first { $0.sourceType == .calDAV }
  }

  private func name(_ source: EKSource) -> String {
    source.sourceType == .local ? "this iPhone" : source.title
  }

  /// The calendar to write to. `fresh` means it was just made, so it holds
  /// none of the events Dart remembers.
  private func ensureCalendar(_ id: String?) throws -> [String: Any] {
    if let id, let calendar = store.calendar(withIdentifier: id) {
      return ["id": calendar.calendarIdentifier, "fresh": false]
    }
    guard let source = home() else { throw BridgeError("There’s no calendar account to add to") }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = "Vaulty"
    calendar.cgColor = UIColor(red: 0x5B / 255, green: 0x44 / 255, blue: 0xF2 / 255, alpha: 1).cgColor
    calendar.source = source
    try store.saveCalendar(calendar, commit: true)
    return ["id": calendar.calendarIdentifier, "fresh": true]
  }

  /// One all-day event, repeating if the item does. No alarms: Vaulty reminds.
  private func upsertEvent(_ args: [String: Any]) throws -> String {
    guard let calendarId = args["calendarId"] as? String, let calendar = store.calendar(withIdentifier: calendarId)
    else { throw BridgeError("The Vaulty calendar is missing") }
    var day = DateComponents()
    day.year = args["year"] as? Int
    day.month = args["month"] as? Int
    day.day = args["day"] as? Int
    guard let start = Calendar.current.date(from: day) else { throw BridgeError("Bad date") }

    let event = (args["eventId"] as? String).flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
    event.calendar = calendar
    event.title = args["title"] as? String
    event.notes = args["notes"] as? String
    event.isAllDay = true
    event.startDate = start
    event.endDate = start
    event.alarms = nil
    switch args["recurrence"] as? String {
    case "YEARLY": event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
    case "MONTHLY": event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)]
    default: event.recurrenceRules = nil
    }
    // A fetched repeating event is its first occurrence, so this covers the series.
    try store.save(event, span: .futureEvents, commit: true)
    guard let id = event.eventIdentifier else { throw BridgeError("The event wasn’t saved") }
    return id
  }

  // MARK: Import

  /// Occurrences between [from] and [to] in other calendars, one per event.
  private func events(from: Date, to: Date, excluding exclude: String?) -> [[String: String]] {
    let calendars = store.calendars(for: .event).filter { $0.calendarIdentifier != exclude }
    if calendars.isEmpty { return [] }
    let day = DateFormatter()
    day.calendar = Calendar(identifier: .gregorian)
    day.locale = Locale(identifier: "en_US_POSIX")
    day.timeZone = .current
    day.dateFormat = "yyyy-MM-dd"
    var seen = Set<String>()
    let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
    return store.events(matching: predicate)
      .sorted { $0.startDate < $1.startDate }
      .compactMap { event in
        guard let id = event.eventIdentifier, seen.insert(id).inserted else { return nil }
        return [
          "id": id,
          "title": event.title ?? "",
          "date": day.string(from: event.startDate),
          "calendar": event.calendar?.title ?? "",
          "kind": kind(event.calendar),
          "recurrence": cadence(event),
        ]
      }
  }

  /// Contact birthdays, and subscribed calendars (public holidays, sports
  /// fixtures), which the import list doesn't tick up front.
  private func kind(_ calendar: EKCalendar?) -> String {
    switch calendar?.type {
    case .birthday: return "birthdays"
    case .subscription: return "subscribed"
    default: return "regular"
    }
  }

  /// Yearly or monthly repeats come across; anything fancier imports as a one-off.
  private func cadence(_ event: EKEvent) -> String {
    guard let rule = event.recurrenceRules?.first, rule.interval == 1 else { return "NONE" }
    switch rule.frequency {
    case .yearly: return "YEARLY"
    case .monthly: return "MONTHLY"
    default: return "NONE"
    }
  }
}

private struct BridgeError: LocalizedError {
  init(_ message: String) { errorDescription = message }
  let errorDescription: String?
}
