# Requirements: purlay-swift

> Last updated: 2026-11-26 · Vision: [vision.md](vision.md)

These describe what the four products do today, read from the code and its tests. Status is *Done* when the test named in the
last column exists and passes in `scripts/verify`. Tests are Swift Testing suites under `Tests/` unless a path says otherwise.

## Functional requirements

| ID | Requirement | Acceptance (Given / When / Then) | Priority | Status | Test |
|---|---|---|---|---|---|
| FR-001 | Every wire type reads what the server sends and writes it back unchanged | Given the pinned bundle's examples, when each schema decodes its examples and encodes them again, then the result equals the input | MVP | Done | `PurlayContractTests` › Round trip |
| FR-002 | Generated code is exactly what the generator writes from the pinned bundle | Given `Contract/bundle` is the one `contract.lock` names, when `scripts/generate --check` runs, then it fails on any difference between disk and output | MVP | Done | `scripts/verify generated`; `Tools/PurlayGen` tests (`GeneratorTests`, `NamingTests`, `TokensTests`, `CommandTests`) |
| FR-003 | Tokens are the file's values and readable | Given `tokens.json`, when the colour pairs are checked, then each pair is readable in light and in dark, and each value equals the file's | MVP | Done | `PurlayTokensTests` |
| FR-004 | The app refuses a server it cannot serve, and says why | Given a server whose minimum contract is newer, or whose version is older than the oldest read, when the handshake runs, then the result is "too new" or refused; given no minimum or an unreadable one, then it does not refuse on it | MVP | Done | `HandshakeTests` |
| FR-005 | A typed server address becomes one origin, safely | Given text typed by a person, when it is read, then it becomes an `https` origin (equal spellings are equal); `http` is accepted only for this machine in a development build; credentials, paths, other schemes and bad ports are refused with the reason | MVP | Done | `ServerAddressTests` |
| FR-006 | Sign-in goes through the system browser and keeps no password | Given a sign-in, when it runs, then the browser gets new values each time, a callback that is not the server's or whose code is not a code is dropped, and closing the page ends it with nothing sent or kept | MVP | Done | `PurlayTestSupportTests` › `NativeSignInTests` |
| FR-007 | The session is read from the server's header and kept per server in the Keychain | Given a `Set-Cookie` header (several cookies, with or without `Max-Age`), when read, then the session and its end are found; given two servers, then each has its own session and removing one leaves the other | MVP | Done | `SessionCookieTests`, `KeychainSessionStoreTests` |
| FR-008 | The realtime connection replays from its cursor without losing or skipping | Given a replay that has more to come, when a live frame beyond the page arrives, then it is delivered but the cursor does not move until the replay finishes; a new connection starts from its own replay | MVP | Done | `ConnectionReplayTests`, `ConnectionTests` |
| FR-009 | A message is on screen at once, and a failed send is never dropped | Given an open socket, when a message is sent, then it shows as sending before anything leaves; no ACK in three seconds marks it failed and Retry sends the same id again; only a failed message can be retried or discarded | MVP | Done | `SendCoordinatorTests` |
| FR-010 | Unsent messages survive and stay one person's | Given the outbox, when it keeps messages, then they come back as they went, within the web's bounds (newest fifty), and what one person kept is never found or sent as another's | MVP | Done | `OutboxStoreTests` |
| FR-011 | Signing out lets everything go | Given a session of use, when the person signs out, then nothing of theirs is held, and a second person on the same device sees none of the first's | MVP | Done | `SignOutLeakTests` |
| FR-012 | An idle app costs nothing | Given a signed-in app waiting for nothing, when ten minutes pass, then it holds only the heartbeat and its watchdog as timers and asks the server for nothing over HTTP | MVP | Done | `IdleBudgetTests` |
| FR-013 | Each request names its platform | Given a platform, when a request is built, then `X-Purlay-Client` names that platform, and macOS when none is given | MVP | Done | `ClientHeaderTests` |
| FR-014 | An upload is checked before it is sent, and its failure says what it means | Given a file, when it is empty or past the limit, then it is refused before sending (the limit itself goes); each server answer is said as what it means; Retry is offered only when trying again can differ | MVP | Done | `UploadRulesTests` |
| FR-015 | The real client works against a real server of the pinned version | Given a server of the version in `contract.lock`, when the live tests run, then sign-in, reads, engine, features and socket pass | Next | Partly: by hand, not in CI (TD-001) | `ContractTests/` via `scripts/contract-test` |
| FR-016 | Consumers can test their code without a server | Given `PurlayTestSupport`, when an app test scripts a transport or fakes a store, then the Kit behaves as against a server | MVP | Done | `PurlayTestSupportTests` |

## Non-functional requirements

| ID | Area | Applies? | Target | Verification |
|---|---|---|---|---|
| NFR-PERF | Performance budget | Yes | An idle app: no HTTP and only two timers (FR-012). A pull request's check: about two minutes | `IdleBudgetTests`; [ci.md](../development/ci.md) |
| NFR-SEC | Security | Yes | No secret in the history; session material only in the Keychain; no third-party code; no trap on handled input | `scripts/verify security`; `scripts/enforcement` |
| NFR-PRIV | Privacy | Yes | Nothing of a person survives sign-out; the outbox and sessions are keyed by person and server; logs carry ids and codes, not content | `SignOutLeakTests`, `OutboxStoreTests`, `KeychainSessionStoreTests` |
| NFR-A11Y | Accessibility | No: the library draws nothing | The apps own it | n/a |
| NFR-I18N | i18n | No: strings belong to the apps. The Kit returns typed problems, not sentences | n/a | n/a |
| NFR-OBS | Observability | Yes | `Log` and `Diagnostics` for what an app can show a person who reports a problem | `DiagnosticsTests`, `DiagnosticsModelTests` |
| NFR-OFF | Offline / sync | Yes | After a reconnect the client replays from its cursor; an unsent message waits in the outbox | FR-008, FR-010 |
| NFR-REC | Failure and recovery | Yes | A failed send is shown and retryable; a server it cannot serve is refused with the reason | FR-004, FR-009 |
| NFR-VER | Versioning | Yes | Semantic versions; one pin of the server contract per version; release tags are immutable | [conventions.md](../architecture/conventions.md), [releasing.md](../development/releasing.md) |
| NFR-COST | Cost | Yes | CI inside the free plan's runners: 5 concurrent macOS jobs shared by the organisation | [ci.md](../development/ci.md) |
| NFR-SCALE | Scale | No: a client library | n/a | n/a |

## Assumptions

| ID | Assumption | Reason | Impact | Status |
|---|---|---|---|---|
| A-001 | The only consumers are `purlay-macos` and `purlay-ios` | Both pin it, and no other repository of the organisation does (checked 2026-11-26) | Medium | Confirmed |
| A-002 | The platform floors follow the apps: macOS 26, iOS 18 | `Package.swift`; the iOS decision records the floor | Medium | Confirmed |
| A-003 | The Kit stays free of third-party dependencies | `scripts/enforcement` enforces it | High | Confirmed |
| A-004 | The server's contract version moves rarely enough for a release per pin | The lock names one server release | Low | Proposed |

## Open questions

| ID | Question | Owner | Target date | Answer / decision |
|---|---|---|---|---|
| Q-001 | When is `1.0.0` cut, and from then on is every public change judged against the last release by a tool (TD-002)? Proposed: after the iPhone app's first release | maintainer | before that release | open |
| Q-002 | Will the Kit ever be offered to third parties as an SDK? It changes the API stability promise and the licence notice. Proposed: no | maintainer | open | open |
| Q-003 | Should the live contract tests run in CI (TD-001), and who pays the macOS minutes? Proposed: yes, in the release lane only | maintainer | before the next contract pin | open |

## Out of scope

- Views, platform frameworks, feature code for one module on one platform.
- Android and web clients (they generate from the bundle).
- A public SDK or a stable API for third parties (Q-002).
