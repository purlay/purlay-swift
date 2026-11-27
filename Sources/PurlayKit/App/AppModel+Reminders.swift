import Foundation
import PurlayContract

public enum ReminderFailure: Error, LocalizedError {
    case unavailable, time, validation, access, failed, sessionChanged
    public var errorDescription: String? {
        switch self {
        case .unavailable: "This server does not support message reminders yet."
        case .time: "Choose a time at least a minute from now and within the next year."
        case .validation: "Check the reminder time. You can keep up to 100 pending reminders per workspace."
        case .access: "This message is no longer available to you."
        case .failed: "The reminder change could not be confirmed. Check your connection and try again."
        case .sessionChanged: "The account changed. Open this action again in the current account."
        }
    }
    static func from(_ error: any Error) -> Self {
        guard let error = error as? APIError else { return .failed }
        switch error.code {
        case .messageNotFound, .channelNotFound, .workspaceNotFound: return .access
        case .validationFailed: return .validation
        default: return .failed
        }
    }
}

private enum ReminderRead {
    case handled
    case unavailable(generation: Int)
    case failed
}

extension AppModel {
    public var supportsReminders: Bool { serverInfo?.capabilities?.messageReminders == true }
    public var reminderItems: [MessageReminder] { sessionOwner?.reminderItems ?? storedReminders }
    public var remindersLoading: Bool { sessionOwner?.remindersLoading ?? loadingReminders }
    public var remindersFailed: Bool { sessionOwner?.remindersFailed ?? failedReminders }

    var reminderScope: String? {
        guard let origin, let me, let workspace else { return nil }
        return "\(origin):\(me.user.id):\(workspace.id)"
    }

    public func reminder(for message: Message) -> MessageReminder? {
        reminderItems.first { $0.message.id == message.id }
    }

    @discardableResult public func loadReminders() async -> Bool {
        let owner = sessionOwner ?? self
        let context = contextGeneration
        let result = await owner.readReminders()
        guard context == contextGeneration, !Task.isCancelled else { return true }
        switch result {
        case .handled: return true
        case .unavailable(let generation):
            if generation == owner.reminderGeneration { remindersOpen = false }
            return true
        case .failed: return false
        }
    }

    private func readReminders() async -> ReminderRead {
        guard supportsReminders, let api, let workspace else { return .handled }
        reminderGeneration += 1
        let generation = reminderGeneration
        let context = contextGeneration
        loadingReminders = true
        failedReminders = false
        defer { if generation == reminderGeneration { loadingReminders = false } }
        do {
            let items = try await api.listMessageReminders(workspaceId: workspace.id.value)
            guard generation == reminderGeneration, context == contextGeneration else { return .handled }
            try Task.checkCancellation()
            storedReminders = items.filter { !isPersonallyDeleted($0.message.id) }
            syncReminderNotices()
            return .handled
        } catch {
            guard generation == reminderGeneration, context == contextGeneration,
                !TransportError.isCancellation(error)
            else { return .handled }
            if (error as? APIError)?.isMissingRoute == true {
                // The next node can still serve this list. Keep the alarms already set for the account.
                return .unavailable(generation: generation)
            }
            failedReminders = true
            return .failed
        }
    }

    public func setReminder(for message: Message, at date: Date) async throws {
        if let sessionOwner {
            try await sessionOwner.setReminder(for: message, at: date)
            return
        }
        guard supportsReminders, let api else { throw ReminderFailure.unavailable }
        let ahead = date.timeIntervalSince(environment.clock())
        guard ahead >= 60, ahead <= Double(ContractConstants.scheduleAheadMaxDays) * 86_400 else {
            throw ReminderFailure.time
        }
        guard message.deletedAt == nil else { throw ReminderFailure.access }
        let context = contextGeneration
        let result: MessageReminder
        do {
            result = try await api.setMessageReminder(
                messageId: message.id.value, body: SetMessageReminderRequest(remindAt: Timestamp(date)))
        } catch { throw ReminderFailure.from(error) }
        guard context == contextGeneration else { throw ReminderFailure.sessionChanged }
        guard !isPersonallyDeleted(message.id) else { throw ReminderFailure.access }
        reminderGeneration += 1
        loadingReminders = false
        storedReminders.removeAll { $0.message.id == message.id }
        storedReminders.append(result)
        storedReminders.sort { $0.remindAt < $1.remindAt }
        syncReminderNotices()
    }

    public func cancelReminder(_ reminder: MessageReminder) async throws {
        if let sessionOwner {
            try await sessionOwner.cancelReminder(reminder)
            return
        }
        guard let api else { throw ReminderFailure.unavailable }
        let context = contextGeneration
        do { try await api.cancelMessageReminder(messageId: reminder.message.id.value) } catch {
            throw ReminderFailure.from(error)
        }
        guard context == contextGeneration else { throw ReminderFailure.sessionChanged }
        reminderGeneration += 1
        loadingReminders = false
        storedReminders.removeAll { $0.id == reminder.id }
        if let scope = reminderScope { environment.attention.cancelReminders([reminder.id.value], scope: scope) }
        syncReminderNotices()
    }

    func syncReminderNotices() {
        guard sessionOwner == nil, let scope = reminderScope else { return }
        guard noticesOn else {
            environment.attention.clearReminders(scope: scope)
            return
        }
        let notices = storedReminders.compactMap { reminder -> ReminderNotice? in
            guard let link = appURL(.message(reminder.message.id, in: reminder.message.channelId)) else { return nil }
            return ReminderNotice(
                id: reminder.id.value, date: reminder.remindAt.date,
                label: chat.channels[reminder.message.channelId].map(Self.title) ?? "Purlay", link: link)
        }
        environment.attention.replaceReminders(notices, scope: scope)
    }

    func clearReminders() {
        if sessionOwner == nil, let scope = reminderScope { environment.attention.clearReminders(scope: scope) }
        storedReminders = []
        reminderGeneration += 1
        loadingReminders = false
        failedReminders = false
        remindersOpen = false
        reminderTarget = nil
    }
}
