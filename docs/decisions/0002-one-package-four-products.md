# 0002. One package, four products

Status: accepted, 2026-11-25

`purlay-macos` held four separate local packages. Here they are one `Package.swift` with four library products:
a consumer adds one URL and one version, and the products always agree on a contract. Rejected: four repositories
or four tagged packages (version skew between Kit and Contract is a bug nobody wants to diagnose).
