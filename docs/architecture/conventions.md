# Conventions

What is checked by a tool is named with the tool; the rest is the rule a reviewer holds a change to. This is a library
that two apps pin by version, so the rules about its public surface matter more here than in an app.

## Tools

| Purpose | Tool | Where |
|---|---|---|
| Format | `swift-format lint --strict` (120 columns, 4 spaces) | `.swift-format`, run by `scripts/verify test` and `generated` |
| Architecture rules | `scripts/enforcement`, each rule also run against a copy with its violation planted (`--demo`) | `scripts/verify rules` |
| Compiler | Swift 6 language mode, every warning an error (`treatAllWarnings(as: .error)`) | `Package.swift` |
| Tests | Swift Testing (`@Test`, `@Suite`) on macOS; the generator's own package; live-server tests by hand | `Tests/`, `Tools/PurlayGen`, `ContractTests/` |
| Secrets | gitleaks, pinned, over the whole history | `scripts/verify security` |
| Verification | `make verify` (pull request), `make verify-all` (release) | `Makefile`, `scripts/verify` |

## Layout and naming

- One `Package.swift`, four library products; a product is a target of the same name (`Sources/<Product>`).
- `PurlayKit` is grouped by what it does (`Auth`, `Realtime`, `Outbox`, `State`, `Markdown`, …), one folder per concern.
  `AppModel` is one type in many files: `AppModel+<Feature>.swift`.
- `Sources/*/Generated` is written by `scripts/generate` and never edited by hand (see Generated code).
- A test file is named for the behaviour it holds (`ConnectionReplayTests.swift`); a test's name states the behaviour in a sentence.
- Every test target must be named in a lane of `scripts/verify` (`-only-testing:`), or `scripts/enforcement` fails: a target no lane runs is not run.

## Layer rules (enforced by `scripts/enforcement`)

- `PurlayContract` and `PurlayTokens` depend on nothing; `PurlayKit` on `PurlayContract`; `PurlayTestSupport` on both.
- Shared code imports no UI framework (`SwiftUI`, `AppKit`, `UIKit`, `WatchKit`). What is platform-specific arrives as a protocol
  the app implements (`AttentionPresenter`, `WebAuthenticator`, `PreferenceStore`).
- No third-party package dependency in `Package.swift`.
- No `@unchecked Sendable` and no `nonisolated(unsafe)` in `Sources`.
- No `try!`, `as!`, `fatalError(`, `unsafelyUnwrapped`, force unwrap or implicitly unwrapped optional in production code
  (generated code and `PurlayTestSupport` are not looked at). A trap cannot be caught, so the rule is prevention.

## Public API and versions

- A version is a tag `vX.Y.Z` of this repository ([releasing](../development/releasing.md)); the apps pin it with `from:`.
- **Major:** anything an app must change to compile or to behave as before: a removed or renamed public symbol, a changed
  signature or protocol requirement, a changed default. **Minor:** a new pin of the server contract, a new product, new public API.
  **Patch:** a fix. When `1.0.0` is cut is an open question (Q-001 in [requirements](../product/requirements.md)).
- A new requirement on a protocol the apps implement (`AttentionPresenter`) is breaking unless it has a default in an extension,
  as `replaceReminders` has.
- Public types that cross actors are `Sendable`; the compiler checks it (Swift 6 mode), so there is no escape to review.
- The wire shape is the server's: a Swift type that decodes a server payload is generated, or it is a hand-written primitive in
  `PurlayContract/Primitives.swift` that the round-trip test covers.

## Generated code

- `Tools/PurlayGen` turns the pinned bundle (`Contract/bundle`, named by `Contract/contract.lock`) into `Sources/PurlayContract/Generated`,
  `Sources/PurlayKit/Generated` and `Sources/PurlayTokens/Generated`.
- `scripts/generate --check` fails unless the files on disk equal the generator's output; the `generated` lane runs it. A change to
  what is generated is a change to `Tools/PurlayGen` with its tests, not to the output.
- The lock is never re-pinned by accident: `scripts/prepare-contract` compares the lock before and after and fails on any difference.

## Errors

- Beyond the generated error codes, a failure is a typed value (`APIError`, `TransportError`, `HandshakeError`, `SignInError`, `ServerAddress.Problem`,
  `UploadFailure`, `SendFailure`) that a model turns into what the person is told. The person is told what happened and what to do; detail goes to `Log`
  (`Diagnostics`), never a credential.
- An empty `catch`, `_ = error` and a silent fallback are not allowed: a failure is surfaced, retried by a stated rule, or logged with its reason.

## Concurrency and state

- Models that a view reads are `@MainActor` and `@Observable`; transport, store and clock work is `Sendable` and behind a protocol.
- The clock, the network, the Keychain and the socket are the only things replaced in tests (`ScriptedTransport`, fakes in
  `PurlayTestSupport`, `eventually` in the test target for waiting on a condition).
- A test never sleeps a guessed time and then asserts: it waits for the condition (`eventually`).
- An idle signed-in app holds only its heartbeat and watchdog as timers and asks the server for nothing (`IdleBudgetTests`).

## Tests

- New behaviour comes with a test; a bug fix starts from a test that fails.
- A person's data is never visible to another: the outbox is keyed by person, a session by server, and signing out lets everything go
  (`OutboxStoreTests`, `KeychainSessionStoreTests`, `SignOutLeakTests`).

## Logging and privacy

- `Log` is the only logger; a message carries an id or a code, not a message body, address or token.
- Session material lives only in the Keychain (`KeychainSessionStore`), never in `UserDefaults` (`PreferenceStore` is for where the app was last pointed).

## Forbidden

| Forbidden | Instead | Why |
|---|---|---|
| Editing a file under `Generated/` | Change the bundle pin or `Tools/PurlayGen` | `generate --check` fails; the next regeneration discards the edit |
| Importing a UI framework in `Sources` | A protocol the app implements | Shared code draws nothing ([overview](overview.md)) |
| `@unchecked Sendable`, `nonisolated(unsafe)` | A `Mutex`, an actor, or a value type | The compiler's checking is the guarantee |
| A new package dependency | The standard library and Foundation | Every app inherits it, and there is no scanner for Swift packages ([decision 0003](../decisions/0003-verify-entry-point-and-secret-scan.md)) |
| Copying a shared file between repositories by hand | Change it at its owner, then copy | `scripts/check-shared-files` fails on any difference |
