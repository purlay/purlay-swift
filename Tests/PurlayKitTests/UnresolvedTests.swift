import Foundation
import PurlayContract
import Testing

@testable import PurlayKit

@MainActor
@Suite("open topics")
struct UnresolvedTests {
    private func root(_ n: Int, in channelNumber: Int = 1) -> Message {
        var message = makeMessage(idAt(n * 1_000), channel: channel(channelNumber), content: "Question \(n)")
        message.thread = ThreadSummary(lastReplyAt: nil, replyCount: 1, resolvedAt: nil, resolvedBy: nil)
        return message
    }

    private func harness() async -> ModelHarness {
        let h = ModelHarness()
        h.server.edit {
            $0.messages = [channel(1): [root(1), root(2), root(3)], channel(2): [root(4, in: 2)]]
            $0.unresolvedPageSize = 2
        }
        await h.signedIn()
        return h
    }

    @Test("open topics span channels, paginate, and preserve a channel filter")
    func lists() async {
        let h = await harness()
        await h.model.openUnresolved()
        #expect(h.model.unresolvedOpen)
        #expect(!h.model.inboxOpen)
        #expect(h.model.unresolvedItems.map(\.id) == [idAt(4_000), idAt(3_000)])
        await h.model.loadMoreUnresolved()
        #expect(h.model.unresolvedItems.count == 4)
        #expect(!h.model.unresolvedHasMore)
        await h.model.setUnresolvedChannel(Uuid(channel(1)))
        await h.model.loadMoreUnresolved()
        #expect(h.model.unresolvedItems.map(\.id) == [idAt(3_000), idAt(2_000), idAt(1_000)])
        await h.model.openInbox()
        #expect(!h.model.unresolvedOpen)
    }

    @Test("a failed read retries, and switching the filter ignores an older response")
    func failureAndRace() async {
        let h = await harness()
        h.server.edit { $0.unresolvedStatus = 500 }
        await h.model.openUnresolved()
        #expect(h.model.unresolvedFailed)
        h.server.edit {
            $0.unresolvedStatus = 200
            $0.unresolvedDelay = 100
        }
        let slow = Task { await h.model.loadUnresolved() }
        try? await Task.sleep(for: .milliseconds(20))
        h.server.edit { $0.unresolvedDelay = 0 }
        await h.model.setUnresolvedChannel(Uuid(channel(2)))
        await slow.value
        #expect(!h.model.unresolvedFailed)
        #expect(h.model.unresolvedItems.map(\.id) == [idAt(4_000)])
    }

    private func reads(_ h: ModelHarness) -> [HTTPRequest] {
        h.server.requests.filter { $0.method == "GET" && $0.url.path.hasSuffix("/unresolved") }
    }

    @Test("a closed Chat route dismisses open topics, and a healthy server can reopen them", arguments: [false, true])
    func closedChatRoute(paging: Bool) async {
        let h = await harness()
        await h.model.openUnresolved()
        await h.model.setUnresolvedChannel(Uuid(channel(1)))
        #expect(h.model.unresolvedHasMore)
        let selected = h.model.selectedChannel
        let workspace = h.model.workspace?.id
        let before = reads(h).count
        h.server.edit {
            $0.unresolvedStatus = 404
            $0.unresolvedErrorCode = "ROUTE_NOT_FOUND"
        }
        if paging { await h.model.loadMoreUnresolved() } else { await h.model.loadUnresolved() }
        #expect(reads(h).count == before + 1)
        #expect(h.model.phase == .ready)
        #expect(h.model.chatAvailable)
        #expect(h.model.selectedChannel == selected)
        #expect(h.model.workspace?.id == workspace)
        #expect(!h.model.unresolvedOpen)
        #expect(h.model.unresolvedItems.isEmpty)
        #expect(!h.model.unresolvedHasMore)
        #expect(!h.model.unresolvedLoading)
        #expect(!h.model.unresolvedFailed)
        #expect(!h.model.notices.contains { $0.kind == .loadFailed })

        h.server.edit { $0.unresolvedStatus = 200 }
        await h.model.openUnresolved()
        #expect(h.model.unresolvedOpen)
        #expect(h.model.unresolvedChannelID == Uuid(channel(1)))
        #expect(h.model.unresolvedItems.map(\.id) == [idAt(3_000), idAt(2_000)])
    }

    @Test("other read failures keep the view open and allow a retry", arguments: [false, true])
    func genuineReadFailures(paging: Bool) async {
        let h = await harness()
        await h.model.openUnresolved()
        let original = h.model.unresolvedItems.map(\.id)
        for (status, code) in [
            (403, "FORBIDDEN"), (404, "WORKSPACE_NOT_FOUND"), (403, "ROUTE_NOT_FOUND"), (500, "INTERNAL"),
        ] {
            h.server.edit {
                $0.unresolvedStatus = status
                $0.unresolvedErrorCode = code
            }
            if paging { await h.model.loadMoreUnresolved() } else { await h.model.loadUnresolved() }
            #expect(h.model.unresolvedOpen)
            #expect(h.model.unresolvedFailed)
            #expect(!h.model.unresolvedLoading)
            #expect(h.model.unresolvedItems.map(\.id) == (paging ? original : []))
            #expect(h.model.unresolvedHasMore == paging)
        }
        h.server.edit { $0.unresolvedStatus = 200 }
        if paging { await h.model.loadMoreUnresolved() } else { await h.model.loadUnresolved() }
        #expect(!h.model.unresolvedFailed)
        #expect(h.model.unresolvedItems.count == (paging ? 4 : 2))
    }

    @Test("a cancelled missing-route response does not dismiss open topics", arguments: [false, true])
    func cancelledMissingRoute(paging: Bool) async {
        let h = await harness()
        await h.model.openUnresolved()
        let original = h.model.unresolvedItems.map(\.id)
        let before = reads(h).count
        let gate = Gate()
        h.server.edit {
            $0.unresolvedStatus = 404
            $0.unresolvedErrorCode = "ROUTE_NOT_FOUND"
            $0.unresolvedGate = gate
        }
        let read = Task {
            if paging { await h.model.loadMoreUnresolved() } else { await h.model.loadUnresolved() }
        }
        #expect(await eventually { reads(h).count == before + 1 })
        read.cancel()
        await gate.open()
        await read.value
        #expect(h.model.unresolvedOpen)
        #expect(!h.model.unresolvedFailed)
        #expect(!h.model.unresolvedLoading)
        #expect(h.model.unresolvedItems.map(\.id) == (paging ? original : []))
        #expect(h.model.unresolvedHasMore == paging)
    }

    @Test("a stale missing route cannot dismiss a new filter result")
    func staleMissingRoute() async {
        let h = await harness()
        let gate = Gate()
        h.server.edit {
            $0.unresolvedStatus = 404
            $0.unresolvedErrorCode = "ROUTE_NOT_FOUND"
            $0.unresolvedGate = gate
        }
        let read = Task { await h.model.openUnresolved() }
        #expect(await eventually { reads(h).count == 1 })
        h.server.edit {
            $0.unresolvedStatus = 200
            $0.unresolvedGate = nil
        }
        await h.model.setUnresolvedChannel(Uuid(channel(2)))
        await gate.open()
        await read.value
        #expect(h.model.unresolvedOpen)
        #expect(!h.model.unresolvedFailed)
        #expect(h.model.unresolvedItems.map(\.id) == [idAt(4_000)])
    }

    @Test("leaving open topics discards a late successful read")
    func leaveWhileReading() async {
        let h = await harness()
        let gate = Gate()
        h.server.edit { $0.unresolvedGate = gate }
        let read = Task { await h.model.openUnresolved() }
        #expect(await eventually { reads(h).count == 1 })
        await h.model.setInboxCategory(.updates)
        await h.model.openInbox()
        await gate.open()
        await read.value
        #expect(h.model.inboxOpen)
        #expect(h.model.inboxCategory == .updates)
        #expect(h.model.updatesStatus == .loaded)
        #expect(!h.model.unresolvedOpen)
        #expect(!h.model.unresolvedLoading)
        #expect(h.model.unresolvedItems.isEmpty)
    }

    @Test("resolving removes the topic, while a refused change leaves it available")
    func resolution() async {
        let h = await harness()
        await h.model.openUnresolved()
        h.server.edit { $0.mutationStatus = 403 }
        await h.model.resolveUnresolved(root(4, in: 2))
        #expect(h.model.unresolvedItems.contains { $0.id == idAt(4_000) })
        #expect(h.model.notices.contains { $0.kind == .resolveFailed })
        h.server.edit { $0.mutationStatus = 200 }
        await h.model.resolveUnresolved(root(4, in: 2))
        #expect(!h.model.unresolvedItems.contains { $0.id == idAt(4_000) })
        #expect(h.model.unresolvedUpdating.isEmpty)
    }

    @Test("opening an item navigates to its channel and thread")
    func opens() async {
        let h = await harness()
        await h.model.openUnresolved()
        await h.model.openUnresolvedThread(root(4, in: 2))
        #expect(!h.model.unresolvedOpen)
        #expect(h.model.selectedChannel == Uuid(channel(2)))
        #expect(h.model.thread?.root == idAt(4_000))
    }

    @Test("a read finishing after sign-out cannot restore open topics")
    func signOut() async {
        let h = await harness()
        h.server.edit { $0.unresolvedDelay = 100 }
        let slow = Task { await h.model.openUnresolved() }
        try? await Task.sleep(for: .milliseconds(20))
        _ = await h.model.signOut(.thisDevice)
        await slow.value
        #expect(!h.model.unresolvedOpen)
        #expect(h.model.unresolvedItems.isEmpty)
        #expect(!h.model.unresolvedLoading)
    }

    @Test("a thread update refreshes the open topics page")
    func liveResolution() async {
        let h = await harness()
        await h.model.openUnresolved()
        h.server.edit { $0.messages[channel(2)] = [] }
        h.last.handlers.message(
            #"{"event":"THREAD_UPDATED","version":2,"ts":1,"data":{"channelId":"\#(channel(2))","messageId":"\#(idAt(4_000).value)","thread":{"lastReplyAt":null,"replyCount":1,"resolvedAt":"2026-10-09T14:00:00.000Z","resolvedBy":null}}}"#
        )
        for _ in 0..<100 {
            if !h.model.unresolvedItems.contains(where: { $0.id == idAt(4_000) }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!h.model.unresolvedItems.contains { $0.id == idAt(4_000) })
    }
}
