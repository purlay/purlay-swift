# Changelog

## Unreleased

## 0.3.1 — 2026-11-27

- Dismiss Threads, Saved Messages, Open Topics, Scheduled Messages, Reminders and Pins if a server node does not serve
  their Chat read route. Keep the session, existing system alarms and later requests available.
- Restore saved markers, pins and bookmarks when a Chat node cannot serve their write route. Skip the connection notice
  and the bookmark follow-up read for that refusal.
- Expose temporary-unavailability outcomes for moving or removing saved messages and adding channel bookmarks.
- Keep confirmed Inbox receipts, pending scheduled edits and reminder alarms when a Chat node declines an action route.
  Dismiss only the thread that was acted on when its resolution or follow route is unavailable.

## 0.3.0 — 2026-11-27

- Generate route, client operation and server event owners from the pinned contract. Use the generated ownership when pausing Chat socket operations.
- Dismiss Inbox notifications or message Search when a server node does not serve its Chat route during a rollout, while
  keeping the session, core Updates and later requests available.

## 0.2.2 — 2026-11-27

- Hold waiting composer sends during sign-out. Resume them if the server refuses sign-out and discard them when the local session ends.
- Include the browser sign-in, optional chat module handling, and rolling deployment fixes from 0.2.1. That tag failed release
  verification and has no published release.

## 0.2.1 — 2026-11-27

- Native browser sign-in sends the app platform so the server can name Purlay for Mac or Purlay for iOS (D-191).
- Keep chat available when an older server omits `modules` from `/api/me`. Explicitly empty lists still open a core-only workspace.
- Treat a closed chat operation during a rolling deployment as unavailable and keep the session and pending messages.

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
