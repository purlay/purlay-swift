import Foundation
import PurlayContract
import Testing

@testable import PurlayKit

/// Away (D-257): a person who has not used Purlay for a while shows as away, and may say so themselves; the server keeps the choice.
@MainActor
@Suite("setting oneself away")
struct AwayTests {
    private func away(_ h: ModelHarness) -> [HTTPRequest] {
        h.server.requests.filter { $0.method == "PUT" && $0.url.path == "/api/me/away" }
    }

    @Test("a person who chose to be away is read as away, and is not shown as available")
    func read() async {
        let h = ModelHarness()
        h.server.edit { $0.awayChosen = true }
        await h.signedIn()
        #expect(h.model.isAway)
        #expect(!h.model.isOnline(Uuid(FakeServer.userID)!))
    }

    @Test("going away is painted at once and asked of the server; coming back is asked the same way")
    func toggles() async throws {
        let h = ModelHarness()
        await h.signedIn()
        #expect(!h.model.isAway)
        await h.model.setAway(true)
        #expect(h.model.isAway)
        let body = try #require(away(h).last?.body)
        #expect(try JSONDecoder().decode(SetAwayRequest.self, from: body).away)
        await h.model.setAway(false)
        #expect(!h.model.isAway)
        #expect(away(h).count == 2)
    }

    @Test("a choice the server refuses is put back, with a word")
    func refused() async {
        let h = ModelHarness()
        await h.signedIn()
        h.server.edit { $0.awayStatus = 400 }
        await h.model.setAway(true)
        #expect(!h.model.isAway)
    }

    @Test("asking for what is already so asks nothing")
    func idempotent() async {
        let h = ModelHarness()
        await h.signedIn()
        await h.model.setAway(false)
        #expect(away(h).isEmpty)
    }
}

/// Being here (D-143, D-257): the server decides idleness from the `ACTIVE` word, so the app says it while the person uses it, and
/// reads who is here whole instead of trusting a socket that may have been away.
@MainActor
@Suite("telling the server the person is here")
struct ActivityTests {
    private let ada = Uuid("0199155c-6200-7b7f-8c11-0000000000e2")!

    private func signedIn(_ edit: (inout FakeServer.State) -> Void = { _ in }) async -> ModelHarness {
        let h = ModelHarness()
        h.server.edit(edit)
        await h.signedIn()
        await h.settle()
        return h
    }

    private func actives(_ socket: FakeSocket) -> [[String: Any]] {
        socket.sent.compactMap { text in
            guard let frame = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                frame["op"] as? String == "ACTIVE"
            else { return nil }
            return frame
        }
    }

    @Test("connected in front of the person, the app says they are here, for the open workspace")
    func saysActiveOnConnect() async {
        let h = await signedIn()
        let said = actives(h.last)
        #expect(said.count == 1)
        #expect((said.first?["payload"] as? [String: Any])?["workspaceId"] as? String == FakeServer.workspaceID)
    }

    @Test("the word is rationed to one a minute, however much the person does")
    func rationed() async {
        let h = await signedIn()
        for _ in 0..<5 { h.model.noteActivity() }
        #expect(actives(h.last).count == 1)
    }

    @Test("a window that is not in front says nothing")
    func onlyInFront() async {
        let h = await signedIn()
        h.model.setActive(false)
        h.model.noteActivity()
        #expect(actives(h.last).count == 1)
    }

    @Test("after a reconnect the first word goes at once: a server that restarted forgot who is here")
    func afterReconnect() async {
        let h = await signedIn()
        let first = h.last
        first.handlers.closed(1006)
        await h.advance(milliseconds: 60_000)
        #expect(h.last !== first)
        h.last.handlers.opened()
        await h.settle()
        #expect(actives(h.last).count == 1)
    }

    @Test("a word the socket could not carry is not counted as said")
    func notCountedWhenNotSent() async {
        let h = ModelHarness()
        await h.model.connect()
        await h.model.signIn()
        await h.settle()
        h.model.noteActivity()
        h.last.handlers.opened()
        await h.settle()
        #expect(actives(h.last).count == 1, "said once the socket opened, not before")
    }

    @Test("who is here is read whole at the start, so somebody already away is not shown as available")
    func snapshot() async {
        let h = await signedIn {
            $0.presence = [(user: "0199155c-6200-7b7f-8c11-0000000000e2", away: true, version: 4)]
        }
        #expect(h.model.chat.presence[ada] == .init(online: true, away: true, version: 4))
        #expect(!h.model.isOnline(ada))
    }

    @Test("a snapshot older than what the socket already said does not undo it")
    func snapshotIsNotNewer() async {
        let h = await signedIn {
            $0.presence = [(user: "0199155c-6200-7b7f-8c11-0000000000e2", away: true, version: 4)]
        }
        h.last.handlers.message(
            #"{"event":"PRESENCE","ts":1,"data":{"changes":[{"userId":"\#(ada.value)","online":true,"away":false,"version":9}]}}"#
        )
        #expect(h.model.chat.presence[ada]?.version == 9)
        #expect(h.model.isOnline(ada))
    }

    @Test("a snapshot that cannot be read leaves what frames tell, and does not fail the workspace")
    func snapshotUnavailable() async {
        let h = await signedIn { $0.presenceStatus = 500 }
        #expect(h.model.phase == .ready)
        #expect(h.model.chat.presence[ada] == nil)
    }
}
