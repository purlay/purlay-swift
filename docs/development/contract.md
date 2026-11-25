# The contract pipeline

The server repository owns the contract. This repository holds a **pin** (`Contract/contract.lock`: server
version, contract version, bundle format, manifest digest) and the generator that turns the pinned bundle into
Swift.

```sh
scripts/contract use DIR       # take a bundle from `bun run contract:bundle --out DIR` in a server checkout
scripts/contract fetch TAG     # or from a server release, after checking its digest
scripts/contract verify        # Contract/bundle is exactly what the lock names
scripts/generate               # write Sources/*/Generated
scripts/generate --check       # fail unless disk equals what would be written (CI runs this)
scripts/contract-test          # the real client against a real server of the pinned version
```

`Contract/bundle/` is fetched and git-ignored. To move to a newer server: pin its bundle, regenerate, fix what the
compiler and the tests show, and release a new version of this package.

## Releasing

Semantic versions. A change to generated code from a new contract is at least a minor; a change that breaks an app's
use of the Kit is a major. Tag `vX.Y.Z` on `main` after `scripts/verify` passes; apps move their pin deliberately.
