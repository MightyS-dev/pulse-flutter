# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the package follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.9.4 - 2026-11-16

- Signals captured in the same millisecond keep their order: timestamps are strictly increasing.
- Screen views: add `Pulse.navigatorObserver` to your navigator observers (also works with go_router) to send `pulse.screen_view` with the screen name and the previous one. Dialogs and bottom sheets are skipped. `Pulse.screen('Name')` sends one by hand.
- Switch the observer off with `PulseOptions(automaticScreenViews: false)`.
- Settings from the portal: once per launch the SDK reads which screen views, automatic signals and field groups are switched on, keeps them, and applies them from the next launch. Everything stays on when they cannot be read. Opt-out deletes them.
- New option `automaticSignals` (default true) switches off `pulse.session_started`, `pulse.new_install` and `pulse.app_updated`.
- `pulse.app_updated` is no longer lost when a launch cannot send it (automatic signals off): the stored version now changes only when the event is queued.

## 0.9.3 - 2026-11-15

- Every signal now carries the device, screen, settings, app and usage values the platform can give, with no setup: device type and brand, CPU architecture, API level, screen size and scale, orientation, colour scheme, language and region, text scale and accessibility settings, connection type, battery saver, app name, install source and debug build flag.
- Usage statistics travel with each signal: first session date, sessions so far, distinct days used, previous and average session length.
- Three automatic signals: `pulse.session_started`, `pulse.new_install` and `pulse.app_updated`. They are one per session or rarer and follow opt-out.
- The package or bundle id is now sent by default (set `sendAppIdentity: false` to leave it out).
- Adds the `connectivity_plus` and `battery_plus` plugins for connection type and battery saver.

## 0.9.2 - 2026-11-15

- Users are counted without any setup: the SDK sends a random anonymous install id (hashed) until you call `setUser`.
- The install id is created on first launch, stored only in the app's own storage, deleted with the app and replaced after opt-out.
- The first signals after start now carry the device and app details.
- The OS version is filled in on Linux and after a device info failure, so every signal carries it.

## 0.9.1 - 2026-11-15

- README: a Test mode section that explains how signals are marked as test or real.

## 0.9.0 - 2026-11-15

Initial public release.

### Added

- `Pulse.initialize`, `Pulse.track`, `Pulse.setUser`, `Pulse.flush`, `Pulse.setOptOut` and `Pulse.optOut`: named signals with an optional number and a few properties.
- Privacy by design: no advertising id, no device identifier, no cookies and no fingerprinting. Sessions use random ids that rotate after 30 minutes of inactivity.
- Optional user id, hashed with SHA-256 on the device before it leaves. The raw id is never stored or sent.
- Opt-out in one call. The choice is remembered and the queue is cleared.
- Batched delivery: the first batch after start is sent at once, later batches follow an interval (20 seconds by default) or a batch size. Request bodies are gzipped.
- Offline queue on disk that survives restarts, with retries and exponential backoff.
- Public calls never throw into the host app and never block the main thread.
- `PulseOptions` for host, flush interval, batch size, queue limits, gzip, debug output and optional app identity.
- Example app in `example/`.
