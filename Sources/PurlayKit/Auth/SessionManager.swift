import Foundation

/// Data the app keeps for a person between runs: the outbox, drafts, a window's state. Removed when that person signs
/// out, and when somebody else signs in where they were (M-1 of §10: no message of one person is ever sent as another's).
public protocol UserDataWiper: Sendable {
    func wipe() async
}

/// Who the retained data belongs to, kept beside it.
public protocol OwnerMemory: Sendable {
    func load() -> String?
    func save(_ owner: String?)
}

public enum SignOutScope: Sendable, Equatable {
    /// This app's session.
    case thisDevice
    /// Every session of the person, the browsers' and the other apps' too.
    case everywhere
}

/// Whether a signed-in app is signed in, why it is not, and what ends it (§7.5). One per run.
public actor SessionManager {
    public enum Reason: Sendable, Equatable {
        /// The time the server gave it has passed.
        case expired
        /// The server said so (`401`, or the socket closed with `SESSION_ENDED`): revoked, or the account is gone.
        case endedByServer
        case signedOutByPerson
        case signedOutEverywhere
    }

    public enum State: Sendable, Equatable {
        case signedOut(Reason?)
        case signedIn(StoredSession, server: ServerAddress)
    }

    public enum SignOutResult: Sendable, Equatable {
        case done
        /// This device is signed out, and the server could not be told: its session lives until it expires or is ended
        /// from elsewhere. Said to the person, since "signed out" would be more than is true.
        case serverNotTold
        /// `.everywhere` that did not happen: nothing was changed, and the person is still signed in.
        case notDone(String)
        /// The server could not be told and this Mac could not forget the sign-in: going on would leave a live session in
        /// the keychain that the next launch signs in with. Nothing was changed, and the person is still signed in.
        case credentialKept
    }

    private let store: any SessionStore
    private let owner: any OwnerMemory
    private let wipers: [any UserDataWiper]
    private let now: @Sendable () -> Date
    private let endSession: @Sendable (SignOutScope, StoredSession, SessionManager) async throws -> Void

    public private(set) var state: State = .signedOut(nil)
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]

    public init(
        store: any SessionStore, owner: any OwnerMemory, wipers: [any UserDataWiper] = [],
        now: @escaping @Sendable () -> Date = Date.init,
        endSession: @escaping @Sendable (SignOutScope) async throws -> Void
    ) {
        self.init(store: store, owner: owner, wipers: wipers, now: now) { scope, _, _ in
            try await endSession(scope)
        }
    }

    init(
        store: any SessionStore, owner: any OwnerMemory, wipers: [any UserDataWiper],
        now: @escaping @Sendable () -> Date,
        endSignedInSession: @escaping @Sendable (SignOutScope, StoredSession, SessionManager) async throws -> Void
    ) {
        self.store = store
        self.owner = owner
        self.wipers = wipers
        self.now = now
        self.endSession = endSignedInSession
    }

    /// The session value to send as the cookie, or none.
    public var cookie: String? {
        if case .signedIn(let session, _) = state { return session.cookie }
        return nil
    }

    /// When the session in use ends, if the server said.
    public var expiresAt: Date? {
        if case .signedIn(let session, _) = state { return session.expiresAt }
        return nil
    }

    /// Every state from now on. The current one is delivered first.
    public func states() -> AsyncStream<State> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(state)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.forget(id) }
            }
        }
    }

    private func forget(_ id: UUID) {
        continuations[id] = nil
    }

    private func move(to next: State) {
        guard next != state else { return }
        state = next
        for continuation in continuations.values { continuation.yield(next) }
    }

    // MARK: Starting

    /// At launch: the session kept for this server, if it is still within its time.
    @discardableResult
    public func restore(for server: ServerAddress) throws -> State {
        guard let session = try store.load(for: server) else {
            move(to: .signedOut(nil))
            return state
        }
        if let end = session.expiresAt, end <= now() {
            try? store.delete(for: server)
            move(to: .signedOut(.expired))
        } else {
            move(to: .signedIn(session, server: server))
        }
        return state
    }

    /// After a sign-in that kept its session.
    public func adopt(_ session: StoredSession, for server: ServerAddress) {
        move(to: .signedIn(session, server: server))
    }

    /// Once the person is known: data left from another person is not kept for this one.
    public func identify(userID: String) async {
        if let retained = owner.load(), retained != userID {
            for wiper in wipers { await wiper.wipe() }
        }
        owner.save(userID)
    }

    // MARK: Ending

    /// The server ended the session. Nothing the person made is removed: the draft and the outbox wait for the next
    /// sign-in, which is the same person's or is found out by `identify`.
    public func sessionEndedByServer() {
        guard case .signedIn(_, let server) = state else { return }
        try? store.delete(for: server)
        move(to: .signedOut(.endedByServer))
    }

    /// Retires only the credential that received the server's terminal signal. No logout is sent.
    @discardableResult
    func sessionEndedByServer(matching cookie: String, for server: ServerAddress) -> Bool {
        guard case .signedIn(let session, let current) = state, current == server, session.cookie == cookie else {
            return false
        }
        do {
            _ = try store.delete(ifMatching: session, for: server)
        } catch {
            Log.session.error("the ended session could not be removed from this device")
        }
        move(to: .signedOut(.endedByServer))
        return true
    }

    /// The session's time passed while the app ran.
    public func checkExpiry() {
        guard case .signedIn(let session, let server) = state, let end = session.expiresAt, end <= now() else { return }
        try? store.delete(for: server)
        move(to: .signedOut(.expired))
    }

    public func signOut(_ scope: SignOutScope) async -> SignOutResult {
        let starting = state
        guard case .signedIn(let session, let server) = starting else { return .done }
        var told = true
        do {
            try await endSession(scope, session, self)
        } catch {
            if scope == .everywhere {
                // The person asked for every session to end and none did: the app does not pretend it did.
                return .notDone("the server could not be reached")
            }
            told = false
        }
        let result: SignOutResult = told ? .done : .serverNotTold
        guard state == starting else { return result }
        let ended: State = .signedOut(scope == .everywhere ? .signedOutEverywhere : .signedOutByPerson)
        // The credential first: whatever fails after, it is no longer here. One that cannot be removed is harmless only
        // if the server ended it; otherwise the app stops here rather than say "signed out" over a session that lives.
        do {
            if try !store.delete(ifMatching: session, for: server), let kept = try store.load(for: server) {
                if kept != session {
                    move(to: ended)
                    return result
                }
                if !told { return .credentialKept }
            }
        } catch {
            Log.session.error("the sign-in could not be removed: \(String(describing: error), privacy: .public)")
            if !told { return .credentialKept }
        }
        for wiper in wipers {
            guard state == starting else { return result }
            await wiper.wipe()
        }
        guard state == starting else { return result }
        if let kept = try? store.load(for: server), kept != session {
            move(to: ended)
            return result
        }
        owner.save(nil)
        move(to: ended)
        return result
    }
}
