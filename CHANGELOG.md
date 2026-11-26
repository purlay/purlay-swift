# Changelog

## Unreleased

- Native browser sign-in sends the app platform so the server can name Purlay for Mac or Purlay for iOS (D-191).

## 0.2.0 — 2026-11-26

- `AppModel.noteActivity()` and `Engine.announceActive(workspace:)`: the app tells the server over the socket that the person
  is using it (`ACTIVE`, at most once a minute per workspace, at once after a reconnect), so a person at the keyboard is not
  shown as away after five minutes (D-143, D-257). Who is here is also read whole at the start and after a reconnect.
- A workspace without chat (the server runs `MODULES=none`, or a node that does not serve channels during a rollout) opens
  without chat requests, an engine or a socket; `chatAvailable` says so, notification and integration settings are hidden,
  and a conversation link says chat is off (`DesktopSessions.LinkProblem.chatUnavailable`).

## 0.1.0 — 2026-11-25

- Extracted from `purlay-macos` (`PurlayContract`, `PurlayTokens`, `PurlayKit`, `PurlayTestSupport`, the
  `PurlayGen` generator and the contract pin). Generated output verified identical to the macOS repository's.
- Added iOS 18 as a supported platform and `ClientPlatform` (`macos` | `ios`) for `X-Purlay-Client`.
