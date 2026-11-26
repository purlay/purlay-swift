# purlay-swift

<p>
  <a href="https://github.com/purlay/purlay-swift/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/purlay/purlay-swift/ci.yml?branch=main&style=flat-square&label=CI" alt="CI status"></a>
  <img src="https://img.shields.io/badge/Swift-6-f05138?style=flat-square" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-24292f?style=flat-square" alt="AGPL-3.0 license"></a>
</p>

The Swift code every Apple client of [Purlay](https://github.com/purlay/purlay) shares: the wire contract, the
design tokens, and the client engine (sign-in, transport, realtime, outbox). No UI, no platform-specific
framework: the apps draw their own interface.

| Product | What it is |
|---|---|
| `PurlayContract` | Codable wire types, routes, frames and error codes, **generated** from the server's contract bundle |
| `PurlayTokens` | Colour, spacing and type values, generated from the server's `tokens.json` |
| `PurlayKit` | Session store (Keychain), handshake, API client, realtime connection with replay, optimistic outbox, the app model |
| `PurlayTestSupport` | Fakes and builders for testing code that uses the Kit |

Part of [Purlay](https://github.com/purlay/purlay), whose README maps the repositories. Consumers:
[`purlay-macos`](https://github.com/purlay/purlay-macos), [`purlay-ios`](https://github.com/purlay/purlay-ios).
Platforms: macOS 26 and later (built for 27), iOS 18 and later (built for 27).

## Using it

```swift
.package(url: "https://github.com/purlay/purlay-swift", from: "0.2.0")
```

An app pins one version, and that version pins one server contract (`Contract/contract.lock`). The server's
`GET /api/client` handshake refuses a client its contract no longer serves, so upgrade the pin together with the
server's minimum.

## Developing

```sh
make setup              # the pinned contract bundle and the secret scanner (network)
make verify             # rules, contract pin, generated code, format, tests, iOS build
make verify-security    # no secret in the history
swift test              # the package's tests
```

Generated code (`Sources/*/Generated`) is never edited by hand: `scripts/contract` pins a bundle from the server,
`scripts/generate` regenerates, and `scripts/generate --check` fails on any difference. See
[`docs/development/contract.md`](docs/development/contract.md).

## Documentation

| Folder | Holds |
|---|---|
| [`docs/README.md`](docs/README.md) | The map: current status, constraints, how to verify |
| [`docs/product/`](docs/product) | Vision and requirements, each tied to a test |
| [`docs/architecture/`](docs/architecture) | What lives here, what must not, conventions, technical debt |
| [`docs/development/`](docs/development) | The contract pipeline, CI, releasing |
| [`docs/decisions/`](docs/decisions) | Decision records |

## License

Contributing: [`CONTRIBUTING.md`](CONTRIBUTING.md). [AGPL-3.0](LICENSE); contributions are under the
[contributor licence agreement](CLA.md).
