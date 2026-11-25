# Contributing to purlay-swift

The rules every Purlay repository shares (branches, commits, pull requests, the agreement) are in the organisation's
[CONTRIBUTING.md](https://github.com/purlay/.github/blob/main/CONTRIBUTING.md). This file is what is specific to this one.

## What this repository is

The Swift that `purlay-macos` and `purlay-ios` share, and nothing that draws: the wire contract, the design tokens and the client
engine. See [`docs/architecture/overview.md`](docs/architecture/overview.md) for what belongs here and what does not.

## Before you push

```sh
scripts/verify
```

It checks, in order: the branch name; that shared files are their owners' copies; the architecture rules (each also run
against a copy with the violation planted); that the contract bundle is the one `Contract/contract.lock` pins and that
`Sources/*/Generated` is exactly what it generates; the generator's tests; format; the tests; and a build for iOS 18 and later.

## Generated code

`Sources/*/Generated` is never edited by hand. A change to the contract is a new pin and a regeneration
([`docs/development/contract.md`](docs/development/contract.md)); a change to what is generated is a change to `Tools/PurlayGen`,
with its tests.

## Changing what the apps rely on

Both apps pin a released version. A change that an app would have to adapt to is a major version; a new pin of the contract is
at least a minor. Say which in the pull request, and add the line to `CHANGELOG.md` under *Unreleased*. How a release is cut:
[`docs/development/releasing.md`](docs/development/releasing.md).

## Shared files

`LICENSE`, `CLA.md`, `SECURITY.md` and `.editorconfig` belong to `purlay/purlay`; `.swift-format`, `NOTICE` and the shared scripts
belong to this repository. Change them at their owner and copy; `scripts/check-shared-files` fails on any difference.
