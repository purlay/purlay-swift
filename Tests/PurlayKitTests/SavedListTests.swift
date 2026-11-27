import Foundation
import PurlayContract
import Testing

@testable import PurlayKit

@MainActor
@Suite("saved message lists")
struct SavedListTests {
    private func ready() async -> ModelHarness {
        let h = ModelHarness()
        h.server.edit {
            $0.messages[channel(1)] = (1...5).map { makeMessage(idAt($0 * 1_000), content: "saved \($0)") }
            $0.saved = Dictionary(uniqueKeysWithValues: (1...5).map { (idAt($0 * 1_000).value, "in_progress") })
        }
        await h.signedIn()
        return h
    }

    @Test("a failed read is distinct from an empty list, and can be retried")
    func failureAndRetry() async {
        let h = await ready()
        h.server.edit { $0.savedListStatus = 500 }
        await h.model.loadSaved(.inProgress)
        #expect(h.model.savedStatus == .failed)
        #expect(h.model.savedItems.isEmpty)
        h.server.edit { $0.savedListStatus = 200 }
        await h.model.loadSaved(.archived)
        #expect(h.model.savedStatus == .loaded)
        #expect(h.model.savedItems.isEmpty)
    }

    @Test("a closed Chat route dismisses Saved and a new read can land on a healthy node", arguments: [false, true])
    func closedChatRead(paging: Bool) async {
        let h = await ready()
        h.model.savedOpen = true
        h.server.edit { $0.savedPageSize = 2 }
        await h.model.loadSaved(.inProgress)
        #expect(h.model.savedHasMore)
        h.server.edit {
            $0.savedListStatus = 404
            $0.savedListErrorCode = "ROUTE_NOT_FOUND"
        }
        if paging { await h.model.loadMoreSaved() } else { await h.model.loadSaved(.inProgress) }
        #expect(!h.model.savedOpen)
        #expect(h.model.savedStatus == .idle)
        #expect(h.model.savedItems.isEmpty)
        #expect(!h.model.savedHasMore)
        #expect(!h.model.savedFailed)
        #expect(!h.model.savedLoading)
        #expect(h.model.chatAvailable)
        #expect(h.model.phase == .ready)

        h.server.edit { $0.savedListStatus = 200 }
        h.model.savedOpen = true
        await h.model.loadSaved(.inProgress)
        #expect(h.model.savedStatus == .loaded)
        #expect(h.model.savedItems.count == 2)
        #expect(h.model.savedHasMore)
    }

    @Test("authorization and missing resources retain the Saved failure and its retry")
    func ordinaryRefusals() async {
        let h = await ready()
        h.model.savedOpen = true
        for (status, code) in [(403, "FORBIDDEN"), (404, "MESSAGE_NOT_FOUND"), (403, "ROUTE_NOT_FOUND")] {
            h.server.edit {
                $0.savedListStatus = status
                $0.savedListErrorCode = code
            }
            await h.model.loadSaved(.inProgress)
            #expect(h.model.savedOpen)
            #expect(h.model.savedStatus == .failed)
        }
    }

    @Test("all saved messages can be reached one page at a time without duplicates")
    func pages() async {
        let h = await ready()
        h.server.edit { $0.savedPageSize = 2 }
        await h.model.loadSaved(.inProgress)
        #expect(h.model.savedItems.count == 2)
        #expect(h.model.savedHasMore)
        await h.model.loadMoreSaved()
        await h.model.loadMoreSaved()
        #expect(h.model.savedItems.map(\.message.id) == (1...5).reversed().map { idAt($0 * 1_000) })
        #expect(!h.model.savedHasMore)
        let count = h.server.requests.count
        await h.model.loadMoreSaved()
        #expect(h.server.requests.count == count)
    }

    @Test("a failed next page keeps the messages already shown and retries from the same cursor")
    func failedPage() async {
        let h = await ready()
        h.server.edit { $0.savedPageSize = 2 }
        await h.model.loadSaved(.inProgress)
        let held = h.model.savedItems
        h.server.edit { $0.savedListStatus = 500 }
        await h.model.loadMoreSaved()
        #expect(h.model.savedItems == held)
        #expect(h.model.savedStatus == .loaded)
        #expect(h.model.savedPaginationFailed)
        h.server.edit { $0.savedListStatus = 200 }
        await h.model.loadMoreSaved()
        #expect(h.model.savedItems.count == 4)
        #expect(!h.model.savedPaginationFailed)
    }

    @Test("a slow earlier tab cannot overwrite the tab opened after it")
    func staleTab() async {
        let h = await ready()
        h.server.edit { $0.savedDelays["in_progress"] = 120 }
        let slow = Task { await h.model.loadSaved(.inProgress) }
        try? await Task.sleep(for: .milliseconds(20))
        await h.model.loadSaved(.archived)
        await slow.value
        #expect(h.model.savedStatus == .loaded)
        #expect(h.model.savedItems.isEmpty)
        #expect(!h.model.savedHasMore)
    }

    @Test("a late closed route cannot dismiss a newer Saved tab")
    func staleClosedRoute() async {
        let h = await ready()
        h.model.savedOpen = true
        h.server.edit {
            $0.savedListStatus = 404
            $0.savedListErrorCode = "ROUTE_NOT_FOUND"
            $0.savedDelays["in_progress"] = 200
        }
        let old = Task { await h.model.loadSaved(.inProgress) }
        #expect(await eventually { h.server.requests.contains { $0.url.path.hasSuffix("/saved") } })
        h.server.edit { $0.savedListStatus = 200 }
        await h.model.loadSaved(.archived)
        await old.value
        #expect(h.model.savedOpen)
        #expect(h.model.savedFilter == .archived)
        #expect(h.model.savedStatus == .loaded)
    }

    @Test("a saved list that arrives after sign-out cannot bring the previous person's data back")
    func lateAfterSignOut() async {
        let h = await ready()
        h.server.edit { $0.savedDelays["in_progress"] = 120 }
        let slow = Task { await h.model.loadSaved(.inProgress) }
        try? await Task.sleep(for: .milliseconds(20))
        await h.model.signOut(.thisDevice)
        await slow.value
        #expect(h.model.savedStatus == .idle)
        #expect(h.model.savedItems.isEmpty)
        #expect(h.model.savedIDs.isEmpty)
    }

    @Test("closing a loading sheet does not turn its cancelled read into a failure")
    func cancelledRead() async {
        let h = await ready()
        h.server.edit { $0.savedDelays["in_progress"] = 120 }
        let read = Task { await h.model.loadSaved(.inProgress) }
        try? await Task.sleep(for: .milliseconds(20))
        read.cancel()
        await read.value
        #expect(h.model.savedStatus == .idle)
        #expect(h.model.savedItems.isEmpty)
    }

    @Test("completing a saved message moves it out of in progress and into completed on the server")
    func completes() async throws {
        let h = await ready()
        await h.model.loadSaved(.inProgress)
        let item = try #require(h.model.savedItems.first)
        #expect(await h.model.moveSaved(item, to: .completed))
        #expect(!h.model.savedItems.contains { $0.id == item.id })
        #expect(h.model.savedIDs[item.message.id] == .completed)
        await h.model.loadSaved(.completed)
        #expect(h.model.savedItems.map(\.id) == [item.id])
    }

    @Test("a refused move keeps the saved message in its original list")
    func moveRefused() async throws {
        let h = await ready()
        await h.model.loadSaved(.inProgress)
        let item = try #require(h.model.savedItems.first)
        h.server.edit { $0.saveError = (500, "INTERNAL") }
        #expect(!(await h.model.moveSaved(item, to: .archived)))
        #expect(h.model.savedItems.contains { $0.id == item.id })
        #expect(h.model.savedIDs[item.message.id] == .inProgress)
    }

    @Test("a closed Chat write leaves the Saved row and marker as read without a follow-up GET")
    func closedSavedRowWrites() async throws {
        let h = await ready()
        h.model.savedOpen = true
        await h.model.loadSaved(.inProgress)
        let item = try #require(h.model.savedItems.first)
        let rows = h.model.savedItems
        let readCount = h.server.requests.filter { $0.method == "GET" && $0.url.path.hasSuffix("/saved") }.count
        h.server.edit { $0.saveError = (404, "ROUTE_NOT_FOUND") }

        #expect(await h.model.moveSavedWithOutcome(item, to: .completed) == .temporarilyUnavailable)
        #expect(await h.model.moveSaved(item, to: .completed) == false)
        #expect(h.model.savedIDs[item.message.id] == .inProgress)
        #expect(h.model.savedItems == rows)

        // The page and its sidebar markers are read independently.
        h.model.savedIDs[item.message.id] = nil
        #expect(await h.model.removeSavedWithOutcome(item) == .temporarilyUnavailable)
        #expect(h.model.savedItems == rows)
        #expect(!h.model.isSaved(item.message))
        #expect(h.model.savedOpen)
        #expect(h.model.savedUpdating.isEmpty)
        #expect(!h.model.notices.contains { $0.kind == .saveFailed })
        #expect(h.server.requests.filter { $0.method == "GET" && $0.url.path.hasSuffix("/saved") }.count == readCount)
    }

    @Test("the saved action outcomes distinguish real refusals from a confirmed update")
    func savedActionOutcomes() async throws {
        let h = await ready()
        await h.model.loadSaved(.inProgress)
        let item = try #require(h.model.savedItems.first)
        for (status, code) in [(403, "FORBIDDEN"), (404, "MESSAGE_NOT_FOUND"), (403, "ROUTE_NOT_FOUND")] {
            h.server.edit { $0.saveError = (status, code) }
            #expect(await h.model.moveSavedWithOutcome(item, to: .completed) == .failed)
            #expect(await h.model.removeSavedWithOutcome(item) == .failed)
            #expect(h.model.savedIDs[item.message.id] == .inProgress)
        }
        h.server.edit { $0.saveError = nil }
        #expect(await h.model.moveSavedWithOutcome(item, to: .completed) == .updated)
        #expect(h.model.savedIDs[item.message.id] == .completed)
        #expect(await h.model.removeSavedWithOutcome(item) == .updated)
        #expect(!h.model.isSaved(item.message))
    }

    @Test(
        "switching to the destination while a move commits shows the item, whichever response arrives first",
        arguments: [10, 140])
    func moveWhileReading(_ readDelay: Int) async throws {
        let h = await ready()
        await h.model.loadSaved(.inProgress)
        let item = try #require(h.model.savedItems.first)
        h.server.edit {
            $0.savedMutationDelay = 80
            $0.savedDelays["completed"] = readDelay
        }
        let move = Task { await h.model.moveSaved(item, to: .completed) }
        try? await Task.sleep(for: .milliseconds(20))
        let read = Task { await h.model.loadSaved(.completed) }
        #expect(await move.value)
        await read.value
        #expect(h.model.savedStatus == .loaded)
        #expect(h.model.savedItems.map(\.id) == [item.id])
        #expect(h.model.savedIDs[item.message.id] == .completed)
    }
}

@MainActor
@Suite("session and search recovery")
struct SessionRecoveryTests {
    @Test("reopening the app's window does not bootstrap another socket or lose the current channel")
    func launchesOnce() async throws {
        let h = ModelHarness()
        try h.rememberedSession()
        await h.model.launch()
        await h.settle()
        let requests = h.server.requests.count
        let sockets = h.sockets.count
        let channel = h.model.selectedChannel
        await h.model.launch()
        #expect(h.model.phase == .ready)
        #expect(h.model.selectedChannel == channel)
        #expect(h.sockets.count == sockets)
        #expect(h.server.requests.count == requests)
    }

    @Test("searching a channel keeps the separating space ready for typing the search terms")
    func channelSearchInput() async {
        let h = ModelHarness()
        await h.signedIn()
        h.model.openSearch("in:api ")
        await h.settle()
        #expect(h.model.searchInput == "in:api ")
        #expect(h.model.searchQuery == "in:api")
        await h.model.search(h.model.searchInput + "migration")
        #expect(h.model.searchQuery == "in:api migration")
    }
}
