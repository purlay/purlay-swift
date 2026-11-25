# Architecture

## What belongs here

Code that two or more Apple apps need and that draws nothing: the contract, the tokens, and the engine that
talks to the server. The rule is enforced (`scripts/enforcement`): shared code imports no UI framework, has no
third-party dependency, uses no unchecked concurrency escape and cannot trap on a value it was handed.

```
PurlayContract   (generated, no dependencies)
PurlayTokens     (generated, no dependencies)
PurlayKit        -> PurlayContract
PurlayTestSupport -> PurlayKit, PurlayContract
```

## What does not

- Views, view models that import SwiftUI, anything platform-specific (Dock badge, login item, APNs registration):
  those live in the apps and reach the Kit through its protocols (`AttentionPresenter`, `WebAuthenticator`, …).
- Feature code for one server module on one platform: that is `purlay-ios`'s `Feature*` packages.

## Platform neutrality

The Kit is a client for one server on several operating systems, so the platform is a value, not a build
assumption: `ClientPlatform` names the client in `X-Purlay-Client`, and every platform-specific act arrives as an
injected dependency in `AppEnvironment`.

## Other clients

Android does not consume this repository. It generates its own types from the same contract bundle
([decision 0001](../decisions/0001-contract-single-source.md)).
