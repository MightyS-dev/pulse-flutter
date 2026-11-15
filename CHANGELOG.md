# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the package follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
