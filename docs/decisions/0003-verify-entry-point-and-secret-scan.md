# 0003. `scripts/verify` holds the lanes, `make verify` is the entry point, and the history is scanned for secrets

Status: accepted, 2026-11-26 (a retroactive record of the lanes, which existed from the first release, and the decision to add the scan)

**Context.** The checks were one script, `scripts/verify`, in lanes that CI runs side by side
([ci.md](../development/ci.md)). There was no scan for secrets, and no single name that every Purlay repository answers to.
Swift Package Manager has no standard vulnerability scanner, and this package has no third-party dependency to scan.

**Decision.**
- The lanes stay in `scripts/verify` (`rules`, `generated`, `test`, `test-contract`, `test-kit`, `ios`, `security`). A `Makefile`
  only names them: `make verify` is what a pull request needs, `make verify-security` the scan, `make verify-all` every lane as a
  release runs them, `make setup` the pinned bundle and scanner.
- The scan is gitleaks over the whole history, installed by `scripts/install-gitleaks` from its release at a pinned version and
  checked against a digest per platform. It is its own CI job that the aggregate `verify` check requires and may not skip, and a
  release verifies with the full history, so a release does not publish past a failed scan.
- The script is owned here and copied to `purlay-macos` and `purlay-ios` like `install-xcodegen`
  (`scripts/check-shared-files` keeps the copies equal).
- Dependencies are not scanned because there is nothing to scan: `scripts/enforcement` refuses any `.package(` in `Package.swift`.
  Pinned tools (XcodeGen, gitleaks) are checked by digest instead, and Dependabot keeps the actions current.

**Alternatives.**
- *A Makefile that holds the lanes:* two places to read the same logic, and CI already calls the script by lane name.
- *`brew install gitleaks`:* an unpinned version and ten seconds of Homebrew on every run (the reason `install-xcodegen` exists).
- *GitHub's secret scanning alone:* it covers pushes to the hosted repository, not a local run or a rehearsal, and cannot be made a
  required part of the aggregate check in the same way.
- *Scanning only the pull request's commits:* a secret already in the history stays unseen.

**Consequences.** (+) One name for every repository, and a secret in any commit fails the check. (−) A false positive needs an
allowlist (`.gitleaks.toml`), which does not exist yet because none has occurred; the scan reads the full history, which grows.
