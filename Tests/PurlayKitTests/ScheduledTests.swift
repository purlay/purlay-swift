import Foundation
import PurlayContract
import Testing

@testable import PurlayKit

@Suite("scheduled messages") @MainActor
struct ScheduledTests {
    private let date = Date(timeIntervalSince1970: Double(epochMs) / 1_000 + 3_600)
    private func opened(supported: Bool? = true) async -> ModelHarness {
        let h = ModelHarness()
        h.server.edit { $0.clientInfo = FakeServer.clientInfo(scheduledMessages: supported) }
        await h.signedIn()
        await h.model.open(Uuid(channel(1))!)
        return h
    }

    @Test("old servers do not enable scheduling")
    func capabilities() async {
        let h = await opened(supported: nil)
        #expect(!h.model.supportsScheduling)
        #expect(!h.model.canSchedule(text: "Later", channel: Uuid(channel(1))!, parent: nil))
    }

    @Test("schedule retries keep one id, clear the confirmed draft, and preserve the reply target")
    func create() async throws {
        let h = await opened()
        let channel = Uuid(channel(1))!
        let id = Uuid(UUID())
        let parent = idAt(100)
        h.model.setDraft("Later", for: channel, parent: parent)
        try await h.model.scheduleDraft(id: id, text: "Later", channel: channel, parent: parent, at: date)
        #expect(h.model.draft(for: channel, parent: parent).isEmpty)
        try await h.model.scheduleDraft(id: id, text: "Later", channel: channel, parent: parent, at: date)
        await h.model.loadScheduled()
        #expect(h.model.scheduledItems.count == 1)
        let item = try #require(h.model.scheduledItems.first)
        #expect(item.parentId == parent)
        #expect(item.sendAt.date == date)
        try await h.model.updateScheduled(item, text: "Changed", files: [], at: date.addingTimeInterval(60))
        #expect(h.model.scheduledItems.first?.content == "Changed")
        try await h.model.cancelScheduled(item)
        #expect(h.model.scheduledItems.isEmpty)
    }

    @Test("sending one now takes it off the list, and one already sent is said")
    func sendNow() async throws {
        let h = await opened()
        let channel = Uuid(channel(1))!
        try await h.model.scheduleDraft(id: Uuid(UUID()), text: "Now", channel: channel, parent: nil, at: date)
        await h.model.loadScheduled()
        let item = try #require(h.model.scheduledItems.first)
        try await h.model.sendScheduledNow(item)
        #expect(h.model.scheduledItems.isEmpty)
        #expect(h.server.requests.contains { $0.method == "POST" && $0.url.path.hasSuffix("/send") })
        await #expect(throws: SchedulingFailure.self) { try await h.model.sendScheduledNow(item) }
        #expect(h.model.scheduledItems.isEmpty)
    }

    @Test("a refusal keeps draft text and a retry can finish")
    func retry() async throws {
        let h = await opened()
        let channel = Uuid(channel(1))!
        let id = Uuid(UUID())
        h.model.setDraft("Keep me", for: channel)
        h.server.edit { $0.scheduledError = (500, "INTERNAL") }
        await #expect(throws: SchedulingFailure.failed) {
            try await h.model.scheduleDraft(id: id, text: "Keep me", channel: channel, parent: nil, at: date)
        }
        #expect(h.model.draft(for: channel) == "Keep me")
        #expect(h.model.scheduledItems.isEmpty)
        await h.model.loadScheduled()
        #expect(h.model.scheduledFailed)
        h.server.edit { $0.scheduledError = nil }
        try await h.model.scheduleDraft(id: id, text: "Keep me", channel: channel, parent: nil, at: date)
        await h.model.loadScheduled()
        #expect(!h.model.scheduledFailed)
        #expect(h.model.scheduledItems.count == 1)
    }

    @Test("a missing schedule write preserves the draft and completed attachment for retry")
    func missingDraftWrite() async throws {
        let h = await opened()
        let conversation = Uuid(channel(1))!
        let id = idAt(200)
        let file = Attachment(
            fileName: "a.txt", height: nil, id: idAt(201), kind: .file, mimeType: "text/plain", sizeBytes: 3, width: nil
        )
        h.model.setDraft("Keep me", for: conversation)
        h.model.uploadsByPlace[AppModel.Place(channel: conversation, parent: nil)] = [
            Upload(id: file.id, name: file.fileName, size: file.sizeBytes, state: .done(file))
        ]
        h.server.edit { $0.scheduledError = (404, "ROUTE_NOT_FOUND") }

        await #expect(throws: SchedulingFailure.temporarilyUnavailable) {
            try await h.model.scheduleDraft(id: id, text: "Keep me", channel: conversation, parent: nil, at: date)
        }
        #expect(h.model.draft(for: conversation) == "Keep me")
        #expect(h.model.uploads(channel: conversation, parent: nil).compactMap(\.attachment) == [file])
        #expect(h.model.scheduledItems.isEmpty)
        #expect(h.model.supportsScheduling)
        #expect(h.model.chatAvailable)

        h.server.edit { $0.scheduledError = nil }
        try await h.model.scheduleDraft(id: id, text: "Keep me", channel: conversation, parent: nil, at: date)
        let write = try #require(h.server.requests.last { $0.url.path.hasSuffix("/scheduled/\(id.value)") })
        let body = try JSONDecoder().decode(ScheduleMessageRequest.self, from: #require(write.body))
        #expect(body.attachmentIds == [file.id])
        #expect(h.model.draft(for: conversation).isEmpty)
        #expect(h.model.uploads(channel: conversation, parent: nil).isEmpty)
        #expect(h.model.scheduledItems.map(\.id) == [id])
    }

    @Test("missing scheduled actions leave the confirmed item and list open")
    func missingExistingWrites() async throws {
        let h = await opened()
        let conversation = Uuid(channel(1))!
        try await h.model.scheduleDraft(id: idAt(200), text: "Later", channel: conversation, parent: nil, at: date)
        let item = try #require(h.model.scheduledItems.first)
        h.model.scheduledOpen = true
        h.server.edit { $0.scheduledError = (404, "ROUTE_NOT_FOUND") }
        await #expect(throws: SchedulingFailure.temporarilyUnavailable) {
            try await h.model.updateScheduled(item, text: "Changed", files: [], at: date.addingTimeInterval(60))
        }
        await #expect(throws: SchedulingFailure.temporarilyUnavailable) { try await h.model.cancelScheduled(item) }
        await #expect(throws: SchedulingFailure.temporarilyUnavailable) { try await h.model.sendScheduledNow(item) }
        #expect(h.model.scheduledItems == [item])
        #expect(h.model.scheduledOpen)
        #expect(!h.model.scheduledFailed)

        h.server.edit { $0.scheduledError = (403, "ROUTE_NOT_FOUND") }
        await #expect(throws: SchedulingFailure.failed) { try await h.model.cancelScheduled(item) }
        h.server.edit { $0.scheduledError = (404, "SCHEDULED_MESSAGE_NOT_FOUND") }
        await #expect(throws: SchedulingFailure.access) { try await h.model.sendScheduledNow(item) }
        #expect(h.model.scheduledItems == [item])

        h.server.edit { $0.scheduledError = nil }
        try await h.model.updateScheduled(item, text: "Changed", files: [], at: date.addingTimeInterval(60))
        #expect(h.model.scheduledItems.first?.content == "Changed")
    }

    @Test("a cancelled or stale schedule write cannot report a missing feature", arguments: [false, true])
    func delayedMissingWrite(signingOut: Bool) async throws {
        let h = await opened()
        let response = Gate()
        let conversation = Uuid(channel(1))!
        let id = idAt(200)
        h.server.edit {
            $0.scheduledError = (404, "ROUTE_NOT_FOUND")
            $0.beforeScheduledResponse = { await response.wait() }
        }
        let write = Task {
            try await h.model.scheduleDraft(id: id, text: "Later", channel: conversation, parent: nil, at: date)
        }
        #expect(await eventually { h.server.requests.contains { $0.url.path.hasSuffix("/scheduled/\(id.value)") } })
        if signingOut { await h.model.signOut(.thisDevice) } else { write.cancel() }
        await response.open()
        await #expect(throws: signingOut ? SchedulingFailure.sessionChanged : SchedulingFailure.failed) {
            try await write.value
        }
        #expect(h.model.scheduledItems.isEmpty)
    }

    @Test("a node without the Scheduled route dismisses only that page, and the next open can load")
    func closedRoute() async throws {
        let h = await opened()
        let conversation = Uuid(channel(1))!
        let id = Uuid(UUID())
        try await h.model.scheduleDraft(id: id, text: "Later", channel: conversation, parent: nil, at: date)
        h.model.scheduledOpen = true
        h.server.edit { $0.scheduledError = (404, "ROUTE_NOT_FOUND") }

        await h.model.loadScheduled()

        #expect(!h.model.scheduledOpen)
        #expect(h.model.scheduledItems.isEmpty)
        #expect(!h.model.scheduledLoading)
        #expect(!h.model.scheduledFailed)
        #expect(h.model.chatAvailable)
        #expect(h.model.supportsScheduling)
        #expect(h.model.me != nil)

        h.server.edit { $0.scheduledError = nil }
        h.model.scheduledOpen = true
        await h.model.loadScheduled()
        #expect(h.model.scheduledOpen)
        #expect(h.model.scheduledItems.map(\.id) == [id])
    }

    @Test("an editor opened during a Scheduled refresh can keep its page and item")
    func keepEditingAfterClosedRoute() async throws {
        let h = await opened()
        let item = Uuid(UUID())
        try await h.model.scheduleDraft(
            id: item, text: "Later", channel: Uuid(channel(1))!, parent: nil, at: date)
        h.model.scheduledOpen = true
        let response = Gate()
        h.server.edit {
            $0.scheduledError = (404, "ROUTE_NOT_FOUND")
            $0.beforeScheduledResponse = { await response.wait() }
        }
        var editorOpen = false
        let reading = Task { await h.model.loadScheduled(dismissOnUnavailable: { !editorOpen }) }
        #expect(
            await eventually {
                h.server.requests.contains { $0.method == "GET" && $0.url.path.hasSuffix("/scheduled") }
            })

        editorOpen = true
        await response.open()
        await reading.value

        #expect(h.model.scheduledOpen)
        #expect(h.model.scheduledItems.map(\.id) == [item])
        #expect(!h.model.scheduledFailed)
        #expect(!h.model.scheduledLoading)
    }

    @Test("a missing workspace still reports a Scheduled read failure")
    func missingWorkspace() async {
        let h = await opened()
        h.model.scheduledOpen = true
        h.server.edit { $0.scheduledError = (404, "WORKSPACE_NOT_FOUND") }

        await h.model.loadScheduled()

        #expect(h.model.scheduledOpen)
        #expect(h.model.scheduledFailed)
        #expect(!h.model.scheduledLoading)
    }

    @Test("a cancelled Scheduled read cannot dismiss the page")
    func cancelledRead() async {
        let h = await opened()
        let response = Gate()
        h.model.scheduledOpen = true
        h.server.edit {
            $0.scheduledError = (404, "ROUTE_NOT_FOUND")
            $0.beforeScheduledResponse = { await response.wait() }
        }

        let reading = Task { await h.model.loadScheduled() }
        #expect(await eventually { h.server.requests.contains { $0.url.path.hasSuffix("/scheduled") } })
        reading.cancel()
        await response.open()
        await reading.value

        #expect(h.model.scheduledOpen)
        #expect(!h.model.scheduledFailed)
        #expect(!h.model.scheduledLoading)
    }

    @Test("unfinished uploads and invalid dates cannot become scheduled sends")
    func invalid() async {
        let h = await opened()
        let channel = Uuid(channel(1))!
        h.model.uploadsByPlace[AppModel.Place(channel: channel, parent: nil)] = [
            Upload(id: idAt(200), name: "file", size: 1, state: .uploading)
        ]
        #expect(!h.model.canSchedule(text: "Later", channel: channel, parent: nil))
        h.model.uploadsByPlace = [:]
        await #expect(throws: SchedulingFailure.time) {
            try await h.model.scheduleDraft(
                id: Uuid(UUID()), text: "Later", channel: channel, parent: nil, at: date.addingTimeInterval(-3_600))
        }
        #expect(h.server.requests.filter { $0.url.path.contains("/scheduled") }.isEmpty)
    }

    @Test("a delayed list cannot restore another session's scheduled messages")
    func signOut() async throws {
        let h = await opened()
        try await h.model.scheduleDraft(
            id: Uuid(UUID()), text: "Later", channel: Uuid(channel(1))!, parent: nil, at: date)
        h.server.edit { $0.scheduledDelay = 100 }
        let loading = Task { await h.model.loadScheduled() }
        await Task.yield()
        await h.model.signOut(.thisDevice)
        await loading.value
        #expect(h.model.scheduledItems.isEmpty)
        #expect(!h.model.scheduledLoading)
    }
}
