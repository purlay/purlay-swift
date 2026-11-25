# Releasing

Versions are Semantic Versions, and a version is a git tag `vX.Y.Z` on `main`. Release tags cannot be moved or deleted (a
ruleset on `v*`): a published version is never changed, because the apps pin it and SwiftPM records its commit. A wrong release is
superseded by the next one.

1. In a pull request, move *Unreleased* in `CHANGELOG.md` to `## X.Y.Z — YYYY-MM-DD` and leave an empty *Unreleased* above it.
   Choose the number: a change an app must adapt to is a major, a new contract pin or a new product a minor, a fix a patch.
2. Merge it. `main` stays green: every pull request passes `scripts/verify` first.
3. Tag the merge commit and push the tag:

   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
   ```

4. The `Release` workflow verifies again, refuses a tag whose version has no entry in `CHANGELOG.md`, and publishes the GitHub
   release with that entry as its notes.
5. In each app, raise `from:` in `project.yml` and in the package manifests in one pull request. The apps' checks fail if the
   two disagree.
