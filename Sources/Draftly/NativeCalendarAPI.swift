import AppKit
import EventKit
import DraftlyCore

@MainActor extension NativeActionHost {
    func eventAPI(_ values: [String: Any]) throws -> Any? {
        let entity = values["entity"] as? String ?? "event"
        let reminders = entity == "list" || entity == "reminder"
        try requestAccess(reminders: reminders)
        return try authorizedEventAPI(values)
    }

    func eventAPIAsync(_ values: [String: Any], timeout: TimeInterval = 30,
                       presentEvent: NativeEventDialog.Presenter = NativeEventDialog.present) async throws -> Any? {
        let entity = values["entity"] as? String ?? "event"
        let operation = values["operation"] as? String ?? ""
        let reminders = entity == "list" || entity == "reminder"
        try await NativeSystemAdapter(events: events, reportError: onError).requestAccessAsync(reminders: reminders)
        try Task.checkCancellation()
        if entity == "event", operation == "edit" {
            var input = values["value"] as? [String: Any] ?? [:]
            let selected = input["calendar"] as? [String: Any] ?? [:]
            let calendar = (selected["identifier"] as? String).flatMap(events.calendar(withIdentifier:)) ?? events.defaultCalendarForNewEvents
            guard calendar != nil else { throw DraftlyError.message("No writable calendar is available.") }
            let start = APIValues.parseDate(input["startDate"]) ?? Date()
            let initial = EventDialogValues(title: input["title"] as? String ?? "", notes: input["notes"] as? String ?? "",
                                            start: start, end: APIValues.parseDate(input["endDate"]) ?? start.addingTimeInterval(3600))
            var saved: Any?
            let edited = try await EventDialogCommit.run(initial, present: presentEvent) { edited in
                input["title"] = edited.title; input["notes"] = edited.notes
                input["startDate"] = APIValues.date(edited.start); input["endDate"] = APIValues.date(edited.end)
                var update = values
                update["operation"] = "update"; update["value"] = input
                saved = try authorizedEventAPI(update)
            }
            return edited == nil ? nil : saved
        }
        if (entity == "calendar" || entity == "list"), operation == "tasks" {
            let input = values["value"] as? [String: Any] ?? [:]
            let identifier = values["identifier"] as? String ?? input["identifier"] as? String ?? ""
            let type: EKEntityType = reminders ? .reminder : .event
            guard let calendar = events.calendars(for: type).first(where: { $0.calendarIdentifier == identifier }) else {
                throw DraftlyError.message("The Reminders list was not found.")
            }
            let fetch = EventKitReminderFetchRequest { [self] completion in
                let token = events.fetchReminders(matching: events.predicateForReminders(in: [calendar])) { reminders in
                    completion(EventKitReminderResult(reminders: reminders ?? []))
                }
                return { self.events.cancelFetchRequest(token) }
            }
            let result = try await fetch.fetch(timeout: timeout)
            try Task.checkCancellation()
            return result.reminders.map(reminderValue)
        }
        return try authorizedEventAPI(values)
    }

    private func authorizedEventAPI(_ values: [String: Any]) throws -> Any? {
        let entity = values["entity"] as? String ?? "event", operation = values["operation"] as? String ?? ""
        let reminders = entity == "list" || entity == "reminder"
        let type: EKEntityType = reminders ? .reminder : .event
        let input = values["value"] as? [String: Any] ?? [:]
        if entity == "calendar" || entity == "list" {
            let calendars = events.calendars(for: type), title = values["title"] as? String ?? input["title"] as? String ?? ""
            let identifier = values["identifier"] as? String ?? input["identifier"] as? String ?? ""
            switch operation {
            case "getAll": return calendars.map(calendarValue)
            case "default": return (reminders ? events.defaultCalendarForNewReminders() : events.defaultCalendarForNewEvents).map(calendarValue)
            case "find": return calendars.first { $0.title == title }.map(calendarValue)
            case "findOrCreate", "update":
                let existing = calendars.first { operation == "update" ? $0.calendarIdentifier == identifier : $0.title == title }
                let calendar = existing ?? EKCalendar(for: type, eventStore: events)
                if existing == nil {
                    calendar.source = (reminders ? events.defaultCalendarForNewReminders() : events.defaultCalendarForNewEvents)?.source ?? events.sources.first { $0.sourceType == .local || $0.sourceType == .calDAV }
                }
                guard !title.isEmpty else { throw DraftlyError.message("The calendar or list title is empty.") }
                calendar.title = title; try events.saveCalendar(calendar, commit: true); return calendarValue(calendar)
            case "events":
                guard let calendar = calendars.first(where: { $0.calendarIdentifier == identifier }), let start = APIValues.parseDate(values["startDate"]), let end = APIValues.parseDate(values["endDate"]), end >= start else { throw DraftlyError.message("The event date range or calendar is invalid.") }
                return events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: [calendar])).map(eventValue)
            case "tasks":
                guard let calendar = calendars.first(where: { $0.calendarIdentifier == identifier }) else { throw DraftlyError.message("The Reminders list was not found.") }
                let result = ReminderFetchResult()
                events.fetchReminders(matching: events.predicateForReminders(in: [calendar])) { result.set($0 ?? []) }
                let deadline = Date().addingTimeInterval(30)
                while result.get() == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                guard let reminders = result.get() else { throw DraftlyError.message("The Reminders query timed out.") }
                return reminders.map(reminderValue)
            default: throw DraftlyError.message("The calendar operation is invalid.")
            }
        }
        let identifier = input["identifier"] as? String ?? ""
        if entity == "event" {
            let event = events.event(withIdentifier: identifier) ?? EKEvent(eventStore: events)
            let calendar = input["calendar"] as? [String: Any] ?? [:]
            event.calendar = (calendar["identifier"] as? String).flatMap(events.calendar(withIdentifier:)) ?? events.defaultCalendarForNewEvents
            guard event.calendar != nil else { throw DraftlyError.message("No writable calendar is available.") }
            event.title = input["title"] as? String ?? ""; event.notes = input["notes"] as? String ?? ""; event.location = input["location"] as? String ?? ""
            event.startDate = APIValues.parseDate(input["startDate"]) ?? Date(); event.endDate = APIValues.parseDate(input["endDate"]) ?? event.startDate.addingTimeInterval(3600)
            event.isAllDay = input["isAllDay"] as? Bool ?? false
            event.url = (input["url"] as? String).flatMap(URL.init(string:))
            if let availability = input["availability"] as? String { event.availability = ["busy": .busy, "free": .free, "tentative": .tentative, "unavailable": .unavailable, "notSupported": .notSupported][availability] ?? .notSupported }
            event.alarms = try decodeAlarms(input["alarms"])
            guard event.endDate >= event.startDate else { throw DraftlyError.message("The event end date precedes its start date.") }
            if operation == "edit" {
                let alert = NSAlert(); alert.messageText = "Edit calendar event"; alert.addButton(withTitle: "Save Event"); alert.addButton(withTitle: "Cancel")
                let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading
                let title = NSTextField(string: event.title ?? ""), notes = NSTextField(string: event.notes ?? "")
                title.widthAnchor.constraint(equalToConstant: 340).isActive = true
                let start = NSDatePicker(), end = NSDatePicker()
                for (label, control) in [("Title", title as NSView), ("Notes", notes as NSView), ("Start", start as NSView), ("End", end as NSView)] { stack.addArrangedSubview(NSTextField(labelWithString: label)); stack.addArrangedSubview(control) }
                for (picker, date) in [(start, event.startDate!), (end, event.endDate!)] { picker.datePickerElements = [.yearMonthDay, .hourMinute]; picker.dateValue = date }
                stack.frame = NSRect(x: 0, y: 0, width: 340, height: 240); alert.accessoryView = stack
                guard alert.runModal() == .alertFirstButtonReturn else { return nil }
                event.title = title.stringValue; event.notes = notes.stringValue; event.startDate = start.dateValue; event.endDate = end.dateValue
            }
            try events.save(event, span: .thisEvent, commit: true); return eventValue(event)
        }
        if entity == "reminder", operation == "update" {
            let reminder = events.calendarItem(withIdentifier: identifier) as? EKReminder ?? EKReminder(eventStore: events)
            let list = input["list"] as? [String: Any] ?? [:]
            reminder.calendar = (list["identifier"] as? String).flatMap(events.calendar(withIdentifier:)) ?? events.defaultCalendarForNewReminders()
            guard reminder.calendar != nil else { throw DraftlyError.message("No writable Reminders list is available.") }
            reminder.title = input["title"] as? String ?? ""; reminder.notes = input["notes"] as? String ?? ""; reminder.location = input["location"] as? String ?? ""
            reminder.priority = input["priority"] as? Int ?? 0
            reminder.isCompleted = input["isCompleted"] as? Bool ?? false
            if let date = APIValues.parseDate(input["completionDate"]) { reminder.completionDate = date }
            func components(_ key: String) -> DateComponents? {
                guard let date = APIValues.parseDate(input[key]) else { return nil }
                let fields: Set<Calendar.Component> = input[key + "IncludesTime"] as? Bool == true ? [.year, .month, .day, .hour, .minute, .second] : [.year, .month, .day]
                return Calendar.current.dateComponents(fields, from: date)
            }
            reminder.dueDateComponents = components("dueDate"); reminder.startDateComponents = components("startDate")
            reminder.alarms = try decodeAlarms(input["alarms"])
            try events.save(reminder, commit: true); return reminderValue(reminder)
        }
        throw DraftlyError.message("The calendar item operation is invalid.")
    }
    private func calendarValue(_ calendar: EKCalendar) -> [String: Any] {
        ["identifier": calendar.calendarIdentifier, "title": calendar.title, "allowsContentModificationx": calendar.allowsContentModifications, "isImmutable": calendar.isImmutable]
    }
    private func alarmValue(_ alarm: EKAlarm) -> [String: Any] {
        var result: [String: Any] = ["relativeOffset": alarm.relativeOffset]
        if let date = alarm.absoluteDate { result["absoluteDate"] = APIValues.date(date) }; return result
    }
    private func decodeAlarms(_ value: Any?) throws -> [EKAlarm] {
        try (value as? [[String: Any]] ?? []).map { item in
            if let date = APIValues.parseDate(item["absoluteDate"]) { return EKAlarm(absoluteDate: date) }
            guard let offset = item["relativeOffset"] as? Double else { throw DraftlyError.message("The alarm is invalid.") }
            return EKAlarm(relativeOffset: offset)
        }
    }
    private func eventValue(_ event: EKEvent) -> [String: Any] {
        var result: [String: Any] = ["identifier": event.eventIdentifier ?? "", "title": event.title ?? "", "notes": event.notes ?? "", "location": event.location ?? "", "isAllDay": event.isAllDay,
                                   "startDate": APIValues.date(event.startDate), "endDate": APIValues.date(event.endDate), "calendar": calendarValue(event.calendar), "alarms": (event.alarms ?? []).map(alarmValue),
                                   "attendees": (event.attendees ?? []).map { ["name": $0.name ?? "", "isCurrentUser": $0.isCurrentUser, "status": String(describing: $0.participantStatus), "type": String(describing: $0.participantType), "role": String(describing: $0.participantRole)] as [String: Any] }]
        result["availability"] = [EKEventAvailability.busy: "busy", .free: "free", .tentative: "tentative", .unavailable: "unavailable", .notSupported: "notSupported"][event.availability] ?? "notSupported"
        if let date = event.creationDate { result["creationDate"] = APIValues.date(date) }
        if let date = event.lastModifiedDate { result["lastModifiedDate"] = APIValues.date(date) }
        if let url = event.url { result["url"] = url.absoluteString }; return result
    }
    private func reminderValue(_ reminder: EKReminder) -> [String: Any] {
        var result: [String: Any] = ["identifier": reminder.calendarItemIdentifier, "title": reminder.title ?? "", "notes": reminder.notes ?? "", "location": reminder.location ?? "", "priority": reminder.priority,
                                   "isCompleted": reminder.isCompleted, "list": calendarValue(reminder.calendar), "alarms": (reminder.alarms ?? []).map(alarmValue), "dueDateIncludesTime": reminder.dueDateComponents?.hour != nil, "startDateIncludesTime": reminder.startDateComponents?.hour != nil]
        if let date = reminder.completionDate { result["completionDate"] = APIValues.date(date) }
        if let components = reminder.dueDateComponents, let date = Calendar.current.date(from: components) { result["dueDate"] = APIValues.date(date) }
        if let components = reminder.startDateComponents, let date = Calendar.current.date(from: components) { result["startDate"] = APIValues.date(date) }
        return result
    }
}

private final class ReminderFetchResult: @unchecked Sendable {
    private let lock = NSLock(); private var value: [EKReminder]?
    func set(_ value: [EKReminder]) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> [EKReminder]? { lock.lock(); defer { lock.unlock() }; return value }
}

// The EventKit callback transfers ownership. Only MainActor reads these items.
struct EventKitReminderResult: @unchecked Sendable {
    let reminders: [EKReminder]
}

@MainActor
struct EventKitReminderFetchRequest {
    var start: (@escaping @Sendable (EventKitReminderResult) -> Void) -> (() -> Void)

    func fetch(timeout: TimeInterval = 30) async throws -> EventKitReminderResult {
        try await EventKitCallbackWait.wait(timeout: timeout) { completion in
            start { result in completion(.success(result)) }
        }
    }
}
