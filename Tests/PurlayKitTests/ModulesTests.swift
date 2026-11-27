import Foundation
import PurlayContract
import Testing

@testable import PurlayKit

/// The server is made of modules (D-250): a workspace may be without the one this app is made for, and the app says so instead of
/// showing a workspace that answers nothing.
@MainActor
@Suite("which modules a workspace has")
struct ModulesTests {
    private func signedIn(
        modules: [String]? = ["chat", "issues"], workspaceModules: [String]? = nil, role: String = "member"
    ) async
        -> ModelHarness
    {
        let h = ModelHarness()
        h.server.edit {
            $0.role = role
            $0.modules = modules
            $0.workspaceModules = workspaceModules
        }
        await h.signedIn()
        return h
    }

    @Test("chat is there when the server runs it and the workspace is not without it")
    func available() async {
        #expect(await signedIn().model.chatAvailable)
        #expect(await signedIn(workspaceModules: ["chat"]).model.chatAvailable)
    }

    @Test("a server that does not run chat, or a workspace not granted it, has no chat")
    func missing() async {
        #expect(await !signedIn(modules: ["issues"]).model.chatAvailable)
        #expect(await !signedIn(workspaceModules: ["issues"]).model.chatAvailable)
    }

    @Test("a legacy /api/me response without modules keeps chat, subject to the workspace grant")
    func legacyModules() async {
        let h = await signedIn(modules: nil)
        #expect(h.model.phase == .ready)
        #expect(h.model.me?.modules == [.chat])
        #expect(h.model.chatAvailable)
        #expect(!h.model.hasModule(.issues))
        #expect(h.server.requests.contains { $0.url.path.hasSuffix("/channels") })
        #expect(await !signedIn(modules: nil, workspaceModules: []).model.chatAvailable)
    }

    @Test("a core-only server opens the workspace without chat requests or an engine")
    func coreOnly() async {
        let h = await signedIn(modules: [], role: "owner")
        #expect(h.model.phase == .ready)
        #expect(h.model.workspace != nil)
        #expect(h.model.engine == nil)
        #expect(h.sockets.isEmpty)
        #expect(Set(h.model.availableSettingsPages).isSuperset(of: [.workspace, .members, .invitations, .data]))
        #expect(
            Set(h.server.requests.map { $0.url.path }).isSubset(of: [
                "/api/client", "/api/native/token", "/api/me",
            ]))
        #expect(!h.model.availableSettingsPages.contains(.notifications))
        #expect(!h.model.availableSettingsPages.contains(.integrations))
    }

    @Test("a closed channel route during rollout preserves the workspace session")
    func mismatchedNodes() async {
        let h = ModelHarness()
        h.server.edit { $0.channelsStatus = 404 }
        await h.signedIn()
        #expect(h.model.phase == .ready)
        #expect(h.model.workspace != nil)
        #expect(h.model.hasModule(.chat))
        #expect(!h.model.chatAvailable)
        #expect(h.sockets.isEmpty)
        #expect(h.server.requests.filter { $0.url.path.hasSuffix("/channels") }.count == 1)
    }

    @Test("a closed message route preserves the ready workspace without a load failure")
    func closedMessageRoute() async throws {
        let h = await signedIn()
        let selected = try #require(h.model.selectedChannel)
        h.server.edit {
            $0.messagesStatus = 404
            $0.messagesErrorCode = "ROUTE_NOT_FOUND"
        }
        await h.model.open(selected)
        #expect(h.model.phase == .ready)
        #expect(h.model.workspace != nil)
        #expect(!h.model.chatAvailable)
        #expect(h.model.channelLoadFailed.isEmpty)
        #expect(!h.model.notices.contains { $0.kind == .loadFailed })
        let paths = h.server.requests.count
        await h.model.open(selected)
        #expect(h.server.requests.count == paths)
    }

    @Test("a chat operation refusal leaves the workspace ready and leaves no generic notice")
    func mismatchedSocket() async throws {
        let h = await signedIn()
        let socket = try #require(h.sockets.last)
        let subscription = try #require(
            socket.sent.compactMap { text -> SubscribeFrame? in
                guard case .subscribe(let frame) = try? JSONDecoder().decode(ClientFrame.self, from: Data(text.utf8))
                else { return nil }
                return frame
            }.first)
        socket.handlers.message(Wire.operationRefusal(refID: subscription.id.value))
        #expect(h.model.phase == .ready)
        #expect(h.model.workspace != nil)
        #expect(!h.model.chatAvailable)
        #expect(h.model.connection == .open)
        #expect(h.model.degraded.isEmpty)
        #expect(h.model.notices.isEmpty)
        #expect(!h.model.send("do not leave the composer"))
    }

    @Test("a null module list is still a malformed response, not a legacy server")
    func malformedModules() async {
        let h = ModelHarness()
        h.server.edit {
            $0.modules = nil
            $0.meExtraJSON = #", "modules": null"#
        }
        await h.signedIn()
        #expect(h.model.phase == .problem(.notAPurlayServer))
        #expect(!h.server.requests.contains { $0.url.path.hasSuffix("/channels") })
    }

    @Test("a module this app does not know is no reason to refuse the rest")
    func unknownModule() async {
        let mixed = ModelHarness()
        mixed.server.edit {
            $0.modules = ["chat", "notes"]
            $0.workspaceModules = ["chat", "notes"]
            $0.meExtraJSON = #", "futureField": {"any": [1, "two"]}"#
        }
        await mixed.signedIn()
        #expect(mixed.model.phase == .ready)
        #expect(mixed.model.chatAvailable)
        #expect(!mixed.model.hasModule(.unknown("notes")))
        let unknownOnly = await signedIn(modules: ["notes"])
        #expect(unknownOnly.model.phase == .ready)
        #expect(!unknownOnly.model.chatAvailable)
        #expect(unknownOnly.sockets.isEmpty)
        #expect(!unknownOnly.server.requests.contains { $0.url.path.hasSuffix("/channels") })
    }
}
