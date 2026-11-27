import Foundation
import PurlayContract
import Testing

@testable import PurlayKit

/// Two servers deliberately reuse user, workspace and channel IDs to exercise local isolation.
struct DesktopTransport: HTTPTransport {
    let first: FakeServer
    let second: FakeServer
    static let otherWorkspace = "0199155c-6200-7b7f-8c11-0000000000bb"

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let server = request.url.port == 4391 ? second : first
        var routed = request
        let other = request.url.path.contains(Self.otherWorkspace)
        if other {
            routed.url = URL(
                string: request.url.absoluteString.replacingOccurrences(
                    of: Self.otherWorkspace, with: FakeServer.workspaceID))!
        }
        var response = try await server.send(routed)
        if request.url.path == "/api/me", response.status == 200 {
            var me = try JSONDecoder().decode(MeResponse.self, from: response.body)
            var membership = me.memberships[0]
            membership.workspace.id = Uuid(Self.otherWorkspace)!
            membership.workspace.name = "Studio"
            membership.workspace.slug = "studio"
            me.memberships.append(membership)
            response.body = try JSONEncoder().encode(me)
        } else if other, let body = String(data: response.body, encoding: .utf8) {
            response.body = Data(body.replacingOccurrences(of: FakeServer.workspaceID, with: Self.otherWorkspace).utf8)
        }
        return response
    }
}

@MainActor @Suite("desktop workspace sessions")
struct DesktopSessionsTests {
    private func desktop(_ h: ModelHarness) -> DesktopSessions {
        var environment = h.model.environment
        environment.transport = DesktopTransport(first: h.server, second: FakeServer())
        return DesktopSessions(environment)
    }

    /// Opens the workspace the person belongs to besides the first.
    private func addSecond(_ desktop: DesktopSessions) async {
        guard let first = desktop.sessions.first?.model else { return }
        await desktop.selectWorkspace(Uuid(DesktopTransport.otherWorkspace)!, from: first)
    }

    @Test("switching workspaces retains connections, separate drafts, and separate durable outboxes")
    func isolation() async throws {
        let h = ModelHarness()
        try h.rememberedSession()
        let desktop = desktop(h)
        await desktop.launch()
        let first = desktop.active
        let firstID = desktop.selectedID
        let channel = Uuid(channel(1))!
        first.setDraft("first draft", for: channel)
        #expect(first.send("queued for first"))
        await addSecond(desktop)
        let second = desktop.active
        #expect(first.phase == .ready && second.phase == .ready)
        #expect(first.engine !== second.engine)
        #expect(first.environment.dataDirectory != second.environment.dataDirectory)
        #expect(second.draft(for: channel).isEmpty)
        second.setDraft("second draft", for: channel)
        #expect(second.send("queued for second"))
        #expect(first.pending.count == 1 && second.pending.count == 1)
        #expect(first.draft(for: channel).isEmpty, "sending consumes only the first account's draft")
        first.setDraft("restored first draft", for: channel)
        desktop.select(firstID)
        #expect(desktop.active === first)
        #expect(second.draft(for: channel).isEmpty)
        #expect(h.sockets.count == 2)
        let request = try #require(first.conversationWindowRequest(for: channel))
        #expect(desktop.owner(for: request) === first)
        #expect(first.environment.dataDirectory == h.directory, "the initial account preserves existing storage")
    }

    @Test("a second workspace restores the shared credential, keeps navigation, and signs out together with the first")
    func workspacesAndSignOut() async throws {
        let h = ModelHarness()
        try h.rememberedSession()
        let desktop = desktop(h)
        await desktop.launch()
        let first = desktop.active
        first.setDraft("workspace one", for: Uuid(channel(1))!)
        await desktop.selectWorkspace(Uuid(DesktopTransport.otherWorkspace)!, from: first)
        let studio = desktop.active
        #expect(studio.phase == .ready)
        #expect(studio.workspace?.slug == "studio")
        #expect(studio.draft(for: Uuid(channel(1))!).isEmpty)
        #expect(first.workspace?.slug == "acme")
        #expect(h.server.requests.filter { $0.url.path == "/api/auth/native/token" }.isEmpty)
        _ = await studio.signOut(.thisDevice)
        #expect(first.phase == .signedOut)
        #expect(studio.phase == .signedOut)
        #expect(first.me == nil && first.engine == nil)
    }

    @Test("a terminal socket ends only workspaces sharing its original credential", arguments: [false, true])
    func socketEndWithPeer(replaced: Bool) async throws {
        let h = ModelHarness()
        try h.rememberedSession()
        let desktop = desktop(h)
        await desktop.launch()
        let first = desktop.active
        let firstSocket = try #require(h.sockets.first)
        let address = try #require(first.server)
        let original = try #require(try h.sessions.load(for: address))
        let replacement = StoredSession(cookie: "replacement-credential", expiresAt: nil, origin: original.origin)
        if replaced { try h.sessions.save(replacement, for: address) }
        await addSecond(desktop)
        let studio = desktop.active
        let channel = Uuid(channel(1))!
        studio.setDraft("studio draft", for: channel)
        firstSocket.handlers.opened()
        firstSocket.handlers.message(#"{"event":"SESSION_ENDED","ts":1,"data":{"reason":"account-deleted"}}"#)

        #expect(await eventually { first.phase == .signedOut })
        #expect(studio.phase == (replaced ? .ready : .signedOut))
        #expect(try h.sessions.load(for: address) == (replaced ? replacement : nil))
        if replaced { #expect(studio.draft(for: channel) == "studio draft") }
        #expect(!h.server.requests.contains { $0.url.path == "/auth/logout" })
    }

    @Test("an old in-flight 401 after reconnect does not retire the replacement account")
    func lateUnauthorizedAfterReplacement() async throws {
        let h = ModelHarness()
        await h.signedIn()
        let address = try #require(h.model.server)
        let original = try #require(try h.sessions.load(for: address))
        let replacement = StoredSession(cookie: "replacement-credential", expiresAt: nil, origin: original.origin)
        let old = try #require(h.model.api)
        let response = Gate()
        let prior = h.server.requests.filter { $0.url.path == "/api/me" }.count
        h.server.edit {
            $0.meStatus = 401
            $0.beforeMeResponse = { await response.wait() }
        }
        let pending = Task { try await old.getMe() }
        #expect(await eventually { h.server.requests.filter { $0.url.path == "/api/me" }.count == prior + 1 })
        try h.sessions.save(replacement, for: address)
        h.server.edit {
            $0.meStatus = 200
            $0.beforeMeResponse = nil
        }
        await h.model.connect()
        #expect(h.model.phase == .ready)
        await response.open()
        await #expect(throws: APIError.self) { try await pending.value }

        #expect(h.model.phase == .ready)
        #expect(try h.sessions.load(for: address) == replacement)
        #expect(!h.server.requests.contains { $0.url.path == "/auth/logout" })
    }

    @Test("a refused sign-out holds sends across workspaces that share the credential")
    func signOutHoldsAnotherWorkspace() async throws {
        let h = ModelHarness()
        try h.rememberedSession()
        let desktop = desktop(h)
        await desktop.launch()
        let first = desktop.active
        let channel = Uuid(channel(1))!
        await first.open(channel)
        await addSecond(desktop)
        let second = desktop.active
        for socket in h.sockets { socket.handlers.opened() }
        await h.settle()
        let firstSocket = try #require(h.sockets.first)
        let upload = Gate()
        let logout = Gate()
        h.server.edit {
            $0.beforeUploadResponse = { await upload.wait() }
            $0.beforeLogoutResponse = { await logout.wait() }
            $0.logoutStatus = 500
        }
        let slow = Task {
            await first.attach([PickedFile(name: "held.txt", data: Data([1]))], channel: channel, parent: nil)
        }
        #expect(await eventually { h.server.requests.contains { $0.url.path.hasSuffix("/uploads") } })
        #expect(first.send("from the first workspace"))
        let signingOut = Task { await second.signOut(.everywhere) }
        #expect(await eventually { h.server.requests.contains { $0.url.path == "/auth/logout-all" } })
        await upload.open()
        await slow.value
        #expect(first.isWaiting(channel: channel, parent: nil))
        #expect(firstSocket.sent.allSatisfy { !$0.contains("MESSAGE_SEND") })
        await logout.open()
        guard case .notDone = await signingOut.value else {
            Issue.record("Expected the server to refuse sign-out")
            return
        }
        #expect(first.phase == .ready && second.phase == .ready)
        #expect(firstSocket.sent.filter { $0.contains("MESSAGE_SEND") }.count == 1)
        #expect(first.pending.count == 1 && second.pending.isEmpty)
        #expect(!first.isWaiting(channel: channel, parent: nil))
    }

    @Test("launch restores every workspace, its selected session, and scoped drafts")
    func restore() async throws {
        let h = ModelHarness()
        try h.rememberedSession()
        let desktop = desktop(h)
        await desktop.launch()
        let first = desktop.active
        first.setDraft("first", for: Uuid(channel(1))!)
        await desktop.selectWorkspace(Uuid(DesktopTransport.otherWorkspace)!, from: first)
        desktop.active.setDraft("studio", for: Uuid(channel(1))!)
        let selected = desktop.selectedID
        for session in desktop.sessions { session.model.invalidateLocalSession() }
        let restored = self.desktop(h)
        await restored.launch()
        #expect(restored.sessions.count == 2)
        #expect(restored.selectedID == selected)
        #expect(restored.active.draft(for: Uuid(channel(1))!) == "studio")
        #expect(restored.sessions[0].model.draft(for: Uuid(channel(1))!) == "first")
        #expect(restored.sessions[1].model.draft(for: Uuid(channel(1))!) == "studio")
        #expect(restored.sessions.allSatisfy { $0.model.phase == .ready })
    }

    @Test("badges sum across accounts and notices with identical channel IDs route to their own workspace")
    func notifications() async throws {
        let h = ModelHarness()
        try h.rememberedSession()
        let desktop = desktop(h)
        await desktop.launch()
        let firstID = desktop.selectedID
        await addSecond(desktop)
        for socket in h.sockets { socket.handlers.opened() }
        await h.settle()
        h.sockets[0].handlers.message(Wire.channelState(channel(1), mentions: 2, version: 10))
        h.sockets[1].handlers.message(Wire.channelState(channel(1), mentions: 3, version: 10))
        #expect(h.attention.badge == 5)
        #expect(Set(h.attention.shown.map(\.id)).count == 2)
        let notice = try #require(h.attention.shown.first)
        #expect(notice.sourceID == firstID.uuidString)
        await desktop.openNotification(channel: Uuid(channel(1))!, sourceID: notice.sourceID)
        #expect(desktop.selectedID == firstID)
        _ = await desktop.active.signOut(.thisDevice)
        #expect(h.attention.badge == nil, "one sign-in ends every workspace of the server")
        #expect(h.attention.retracted.contains(notice.id))
    }

    @Test("settings keep the focused conversation's server and reselecting the current session retains focus")
    func focusedContext() async throws {
        let h = ModelHarness()
        try h.rememberedSession()
        let desktop = desktop(h)
        await desktop.launch()
        let first = desktop.active
        let request = try #require(first.conversationWindowRequest(for: Uuid(channel(1))!))
        let window = try #require(await first.makeConversationWindow(request))
        await addSecond(desktop)
        desktop.active.setActive(true)
        desktop.select(desktop.selectedID)
        #expect(desktop.active.isActive)
        window.selectSettingsPage(.account)
        desktop.prepareSettings(for: window)
        #expect(desktop.settingsModel === first)
        #expect(desktop.settingsModel.settingsPage == .account)
        #expect(desktop.active !== first)
    }
}
