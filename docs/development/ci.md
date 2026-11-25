# Continuous integration

The three Swift repositories (`purlay-swift`, `purlay-macos`, `purlay-ios`) run their checks the same way. This is the one place
that says how and why; each repository's `CONTRIBUTING.md` says only what is specific to it.

## What it has to be

- A pull request's check: **about two minutes**.
- A release's check (every lane, on one machine): **five to ten minutes**.
- `main` stays green, and nobody waits on a check to find out what a local run would have told them.

## How

**One script, in lanes.** `scripts/verify` takes a lane; CI runs the lanes as separate jobs side by side, and a person runs them all
(`scripts/verify`). The jobs' names are lanes, not steps: `rules`, `generated`, `test` (or `test-contract` and `test-kit`), `build`,
`packages`, `app`, `ios`, `simulator`, as each repository has them. One job, `verify`, depends on all of them and is the single check a pull request needs
(the branch protection asks for it by name).

**Cheap work on a cheap runner.** `rules` (branch name, shared files, architecture rules and their demonstration) needs no Swift and
runs on Linux, where a job starts in seconds. Everything that compiles runs on the Xcode 27 runner.

**A compilation cache that survives a fresh checkout.** A hosted runner is clean every time, and compiling `PurlayContract` and
`PurlayKit` from nothing took minutes, several times per run. Xcode's compilation cache is content-addressed
(`COMPILATION_CACHE_ENABLE_CACHING=YES`, `COMPILATION_CACHE_CAS_PATH`): a build in a new checkout reuses what any earlier build with
the same inputs compiled, with no regard to file timestamps (which is what makes caching DerivedData unreliable). Measured on a
developer machine, building the iOS app took 22 s cold and 5.5 s with a warm cache and a fresh DerivedData. The cache is kept in
`PURLAY_CACHE_DIR` (by default `~/Library/Caches/dev.purlay/compilation-cache`, so a person's second run is fast too).

- **`main` and a weekly schedule save it; pull requests only restore it.** A pull request never writes the cache, so a branch cannot
  leave something behind for another. One key per lane per day, reset each week (`cas-<lane>-<week>-<day>`, restored by the week's
  prefix) so it cannot grow without end. The Monday run warms the week.
- **The contract bundle is cached by the lock's digest** and, on a miss, downloaded from the server's release asset
  (`scripts/prepare-contract`) and compared with `Contract/contract.lock`; it is never re-pinned by accident.

**No simulator in a pull request's check.** Preparing a simulator on a hosted runner took about three and a half minutes of an
eleven-minute job (`Testing started` came 483 s after the build), whatever was tested; no check that starts one can take two minutes.
A pull request runs the app's logic on macOS and builds the app for iOS. `purlay-ios` runs its `simulator` lane for a pull request that
changes the app itself, and always on `main`, on the schedule and for a release.

**A pull request that changes only documents compiles nothing.** Every macOS job pays a fixed cost before it does any work (below), so a
`changes` job reads the pull request's files and, when every one is a document (`docs/`, `*.md`, `LICENSE`, `NOTICE`, `.editorconfig`,
`CODEOWNERS`), the compiling lanes are skipped. `verify` accepts a skipped lane only when that job said so; an empty file list, any
other event (`main`, the schedule) and any file that is not a document run every lane, so `main` always saves the caches.

**Tools are installed from their releases, pinned and checked.** `brew install xcodegen` took 9 to 17 s of every job that needed it (it updates
Homebrew and pours a bottle). `scripts/install-xcodegen`, owned here and copied to the apps, downloads the pinned release, checks its digest, and
puts it on the `PATH` of the steps that follow: 1 s in the apps' runs (measured). It installs nothing when the pinned version is already there, and a digest that is not
the pinned one fails and leaves nothing behind. To move to a newer version change the version and the digest the release page shows.

**Releases are rehearsed.** Release tags are immutable, so the release workflow can be run by hand from a branch
(*Actions → Release → Run workflow*): it runs every lane on the release's machine and publishes nothing. The first rehearsal of
`purlay-swift` found a flaky test that a normal pull request had not.

## What it costs, measured

Hosted runner (Apple M1, virtual, 3 cores, 7 GB), 2026-11-25. Before: one job ran `scripts/verify` start to finish. "Cold" is a first
run with no cache; "warm" restores the compilation cache saved by `main`. Times are the jobs' own, run side by side, when no other
repository was holding the runners.

| | Before | After, cold | After, warm |
|---|---|---|---|
| `purlay-swift` pull request | 393 s | `test` 188 s, `ios` 124 s, `generated` 104 s | **106–126 s**: `test-contract` 94–110 s, `test-kit` 77–90 s, `generated` 68–80 s, `ios` 42–51 s, `rules` 5–6 s |
| `purlay-swift` release rehearsal | | | 263 s |
| `purlay-macos` pull request | 337 s | `test` 97 s, `app` 160 s | **100–156 s**: `test` 78–123 s, `app` 96–109 s, `rules` 5–10 s |
| `purlay-ios` pull request | 535 s (646 s for the first simulator version) | `packages` 106 s, `build` 148 s | **89–97 s**: `packages` 41–77 s, `build` 41–60 s, `rules` 5–12 s |
| a pull request that changes only documents | the same as any other | | the `rules` and `changes` jobs only, about 10 s (this pull request is the first) |

The jobs of a run start together, so a pull request takes as long as its slowest job, plus the time it waits for a runner.

### Where the time goes, and what does not help

Measured on the runner with the iOS app's build lane, the same cache each time:

| | Time |
|---|---|
| the first `xcodebuild` of a job (CI's case) | 66 s |
| the same, with DerivedData removed | 22 s |
| an incremental build | 13 s |
| the build with the cache off | 80 s |

- **The compilation cache works**: with it warm, the 34 Swift compile tasks take 0.9 s in total. What is left is not compiling.
- **The first `xcodebuild` of every job costs about 45 s more than the next one**, with a lot of system time (disk, service start-up), whatever the cache holds. So a lean macOS lane has a floor of roughly 80–90 s: about 20 s of job set-up and the cache restore, plus that first build.
- **Reading Xcode and the SDKs in the background while the job set itself up did not help** (the read took 22 s and the build lane gained 5 s; the job got slower overall), so the start-up cost is not the toolchain being read from disk for the first time. It is not worth the complexity.
- **Runs vary**: the same lane took 77 s in one run and 141 s in another on the same runner type, because the machines are shared.

So two minutes is reachable for a pull request only if every macOS lane is lean, and is not a promise: `purlay-ios` and `purlay-swift` meet it in the measured runs, `purlay-macos` is at two to two and a half and varies with the runner. Its `app` lane is mostly the Debug build (about 85 s, of which the first-build floor is the larger part) and its `test` lane the package's tests and snapshots (about 100 s). The levers left are splitting the longest lane (done for `purlay-swift`'s `test`: Contract and Tokens, Kit and TestSupport, side by side), running fewer macOS jobs; format sits in the lane with the most slack (`generated` in `purlay-swift`, `packages` in `purlay-ios`).

**Waiting for a runner is not in those numbers.** The organisation is on GitHub's free plan: 20 concurrent jobs, 5 of them macOS, shared by
every repository (the server's own check uses many). With several pull requests open the Swift jobs queue for minutes. That is the plan's
limit, not the workflows'; it is why a pull request should not be opened on top of another, and why a lane that needs macOS is split
only when it saves more than the extra job costs.

## When you change it

- A change that makes a pull request's check slower needs a reason in its description; measure it on the runner, not on your machine
  (the runner is six to nine times slower).
- A new lane is a job that `verify` depends on, or it is not checked.
- Pin every action to a commit SHA with its version in a comment; Dependabot keeps them current.
- A test that sleeps a guessed number of milliseconds and then asserts is a test of the scheduler; wait for the condition
  (`eventually`).
