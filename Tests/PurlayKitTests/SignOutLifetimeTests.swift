import PurlayContract
import Testing

@testable import PurlayKit

@MainActor @Suite("explicit sign-out lifetime")
struct SignOutLifetimeTests {
    @Test("a delayed device logout only ends its original credential")
    func replacementDuringLogout() async throws {
        let h = ModelHarness()
        await h.signedIn()
        let address = try #require(h.model.server)
        let original = try #require(try h.sessions.load(for: address))
        let response = Gate()
        h.server.edit { $0.beforeLogoutResponse = { await response.wait() } }

        let logout = Task { await h.model.signOut(.thisDevice) }
        #expect(await eventually { h.server.requests.contains { $0.url.path == "/auth/logout" } })
        let replacement = StoredSession(cookie: "replacement-credential", expiresAt: nil, origin: original.origin)
        try h.sessions.save(replacement, for: address)
        await h.model.connect()
        #expect(h.model.phase == .ready)
        let replacementOwner = try #require(h.model.environment.owner.load())
        let channel = Uuid(channel(1))!
        h.model.setDraft("replacement draft", for: channel)

        await response.open()
        #expect(await logout.value == .done)
        #expect(h.model.phase == .ready)
        #expect(h.model.draft(for: channel) == "replacement draft")
        #expect(try h.sessions.load(for: address) == replacement)
        #expect(h.model.environment.owner.load() == replacementOwner)
        let logoutRequests = h.server.requests.filter { $0.url.path == "/auth/logout" }
        #expect(logoutRequests.map { $0.headers["Cookie"] } == ["__Host-purlay_session=\(original.cookie)"])
    }
}
