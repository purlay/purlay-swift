# Releasing

Versions are Semantic Versions, and a version is a git tag `vX.Y.Z` on `main`. Release tags cannot be moved or deleted (a
ruleset on `v*`): a published version is never changed, because the apps pin it and SwiftPM records its commit. A wrong release is
superseded by the next one.

1. In a pull request, move *Unreleased* in `CHANGELOG.md` to `## X.Y.Z — YYYY-MM-DD` and leave an empty *Unreleased* above it.
   Choose the number: a change an app must adapt to is a major, a new contract pin or a new product a minor, a fix a patch.
2. Merge it. `main` stays green: every pull request passes the `verify` check first (`make verify`, and the `security` job).
3. Run the Release rehearsal on `main`. Check that the successful run's commit matches the merge commit you will tag.
   Tag that commit and push the tag:

   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
   ```

4. The `Release` workflow verifies again with every lane (`scripts/verify`, including the secret scan over the full history), refuses a
   tag whose version has no entry in `CHANGELOG.md`, and publishes the GitHub release with that entry as its notes. A failed lane
   publishes nothing.
5. After the GitHub release is published, update the exact version in both `project.yml` (`exactVersion:`) and the app's
   Swift package manifests (`exact:`) in one pull request. The apps' checks fail if the declarations disagree
   (`scripts/enforcement` in each app). An exact pin prevents SwiftPM from selecting a tag whose release verification failed.

## Rehearsing

*Actions → Release → Run workflow*, on any branch, runs everything a release runs (every lane, one machine, from the week's
compilation cache) and publishes nothing, so the time a release takes and whether it would pass are known before a tag exists.
A tag cannot be taken back. The rehearsal runs on the branch you choose, so check the branch is the one you mean to release from.
