# purlay-swift

The Swift code that every Apple client of [Purlay](https://github.com/purlay/purlay) shares: the wire contract, the design tokens
and the client engine (handshake, sign-in, transport, realtime with replay, optimistic outbox). One package, four products
(`PurlayContract`, `PurlayTokens`, `PurlayKit`, `PurlayTestSupport`), no UI. `purlay-macos` and `purlay-ios` pin a release of it.

## Current status

- **Stage:** released library, version 0.2.0 (2026-11-26); both apps consume it.
- **Working:** the four products; the generator and the contract pin (server 0.8.0, contract 1); the architecture rules; the CI lanes
  and the secret scan; release rehearsal and publication.
- **Measured baseline (2026-11-26, a developer machine):** `scripts/verify` all lanes green in 20 s warm; 940 tests pass
  (Kit 847, TestSupport 70, Contract 19, Tokens 4); about 12.9k hand-written and 24.9k generated lines under `Sources`.
- **Partly done:** the live-server contract tests run by hand, not in CI ([TD-001](architecture/tech-debt.md)).
- **Known issues:** none open besides the debts in [tech-debt.md](architecture/tech-debt.md).

## Current constraints

- The contract is defined once, in the server repository; here it is pinned and generated, never edited — [decision 0001](decisions/0001-contract-single-source.md)
- One package with four products, so a consumer adds one URL and one version — [decision 0002](decisions/0002-one-package-four-products.md)
- Shared code imports no UI framework, has no third-party dependency, no unchecked concurrency escape and no trap on handled input — [conventions](architecture/conventions.md)
- `scripts/verify` holds the lanes and `make verify` is the entry point; the whole history is scanned for secrets — [decision 0003](decisions/0003-verify-entry-point-and-secret-scan.md)
- A file shared between the Swift repositories is changed at its owner and copied (`scripts/check-shared-files`)
- Release tags are immutable: a wrong release is superseded, never moved — [releasing](development/releasing.md)

## Next steps

1. Run the live contract tests in the release lane ([TD-001](architecture/tech-debt.md), Q-003): FR-015.
2. Check public API changes against the last release by a tool before `1.0.0` ([TD-002](architecture/tech-debt.md), Q-001).
3. Move to the server's next contract release when it ships ([contract pipeline](development/contract.md)).

## Quick start

**Requirements:** Xcode 27 or later (Swift 6.2), `gh` and network for the first `make setup`.

```sh
make setup              # the pinned contract bundle and the secret scanner
make verify             # rules, generated code, format, tests on macOS, build for iOS
swift test              # only the package's tests
```

`Contract/bundle` is fetched and git-ignored. Locally, `scripts/check-shared-files` reads GitHub's API, which limits anonymous requests
(60 an hour): set `GITHUB_TOKEN="$(gh auth token)"` (CI passes its own token).

## Verification

```sh
make verify
```

A change is not finished until this is green. Also `make verify-security` (the history holds no secret, required in CI) and
`make verify-all` (every lane, as a release runs them). `scripts/verify <lane>` runs one lane.

## Project structure

```
Sources/PurlayContract, PurlayTokens, PurlayKit, PurlayTestSupport   # the four products; Generated/ folders are written by the generator
Tests/                  # Swift Testing, one target per product
Tools/PurlayGen/        # the generator, a package of its own with its tests
ContractTests/          # the real client against a real server (by hand)
Contract/               # contract.lock, the pin; bundle/ is fetched
scripts/                # verify and its lanes, the contract pipeline, installers, shared files
```

## Docs map

| Document | Read it when |
|---|---|
| [product/vision.md](product/vision.md) | You ask why this package exists and what it must not become |
| [product/requirements.md](product/requirements.md) | You change behaviour: each requirement names its test |
| [architecture/overview.md](architecture/overview.md) | You add a product, a folder, or move a boundary |
| [architecture/conventions.md](architecture/conventions.md) | Before every code change |
| [architecture/tech-debt.md](architecture/tech-debt.md) | You pick the next piece of work, or take a shortcut |
| [decisions/](decisions/) | You ask "why is it like this?", before an architectural change |
| [development/contract.md](development/contract.md) | You move the server contract pin or touch the generator |
| [development/ci.md](development/ci.md) | You change a lane or a workflow |
| [development/releasing.md](development/releasing.md) | You cut or rehearse a release |

## Recent decisions

- [0003 — `scripts/verify` holds the lanes, `make verify` is the entry point, the history is scanned for secrets](decisions/0003-verify-entry-point-and-secret-scan.md)
- [0002 — One package, four products](decisions/0002-one-package-four-products.md)
- [0001 — The contract stays in the server repository](decisions/0001-contract-single-source.md)

## Working rule

In every change: read the relevant document, implement, update the documents in the same change, record a decision if one was
made, run `make verify`.
