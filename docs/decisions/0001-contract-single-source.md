# 0001. The contract stays in the server repository

Status: accepted, 2026-11-25

The contract is defined once, in `purlay` (`packages/types`), and published as a versioned bundle. This repository
pins one bundle and generates Swift from it; Android will generate Kotlin from the same bundle. No separate
"contract" repository: a route and its type must change in one commit, and the bundle already is the published form.
