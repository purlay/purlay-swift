# Vision: purlay-swift

> Last updated: 2026-11-26 · Owner: maintainer

## Problem

Purlay has two Apple clients, a Mac app and an iPhone app, and a third (Android) planned. Without shared code each would
re-implement sign-in, the handshake, the realtime connection with replay, and the optimistic outbox, and the clients would
drift from the server and from each other.

## Users

- **Primary:** the developers of `purlay-macos` and `purlay-ios`: they add one URL and one version and get the contract, the
  tokens and the engine.
- **Secondary:** a future watchOS or visionOS client of the same product.

## Job to be done

When an Apple client of Purlay needs to talk to the server, its developer wants the contract types, the design values and the
engine to arrive generated and tested against the server's own release, so that the app is only an interface.

## Value

- One implementation of the hard parts (session, replay, outbox), tested once, with 940 tests (2026-11-26).
- The contract is generated from the server's bundle, never typed twice: drift is a failed check, not a production bug.
- The Kit draws nothing, so each app keeps a native interface.

## Platforms

macOS 26 and later, iOS 18 and later (built with the OS 27 SDK), Swift 6 language mode.

## Success metrics

| Metric | Target | How measured | Date |
|---|---|---|---|
| Apps on the latest release | Both apps pin the latest tag within one pull request of a release | the apps' `from:` against the latest tag | each release |
| Hand-written copies of wire types in the apps | 0 | `grep` for `Codable` wire types outside this package | each release |
| A pull request's check | about 2 minutes | [ci.md](../development/ci.md) | quarterly |

## First slice

Already built (0.1.0, extracted from the Mac app): the four products, the generator, the pin. Requirements:
[requirements.md](requirements.md).

## Non-goals

- Any view or platform framework (SwiftUI, AppKit, UIKit): the apps draw.
- Feature code for one server module on one platform (that is `purlay-ios`'s `Feature*` packages).
- Serving Android or the web: they generate from the same bundle and do not use this code.
- A public SDK for third parties (see Q-002).

## Constraints

Licence AGPL-3.0 with the contributor agreement. No third-party dependency. The server owns the contract; the pin moves
deliberately ([contract pipeline](../development/contract.md)).
