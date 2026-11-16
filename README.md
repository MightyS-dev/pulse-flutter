# MightyS Pulse for Flutter

Privacy-first analytics for Flutter apps and games. No device IDs, offline queue.

Docs: https://pulse.mightys.dev/docs/flutter/

Send named signals (events) with an optional number and a few properties, and see them in the MightyS Pulse dashboard. This package is for Flutter app and game developers who want usage numbers without advertising ids, device identifiers, cookies or fingerprinting.

## Install

```sh
flutter pub add mightys_pulse
```

Android release builds need network access, otherwise nothing is sent. Add `<uses-permission android:name="android.permission.INTERNET" />` to `android/app/src/main/AndroidManifest.xml`, outside `<application>`. Flutter's template declares it only for debug and profile builds.

## Quick start

```dart
import 'package:flutter/widgets.dart';
import 'package:mightys_pulse/mightys_pulse.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Pulse.initialize('YOUR_APP_KEY'); // your app key from the Pulse dashboard
  Pulse.track('level.complete');
  Pulse.track('purchase', value: 4.99, props: {'sku': 'gems_100'});
  runApp(const MyApp());
}
```

Users are counted without any setup. Other calls:

```dart
Pulse.setUser('internal-account-id'); // optional: use your own user id instead of the anonymous install id
Pulse.setUser(null);                  // back to the anonymous install id for later signals
await Pulse.flush();                  // waits until queued signals are delivered
```

Public calls never throw into your app and never block the main thread. Calls made before `initialize` finishes are kept (up to 100) and sent afterwards. A second `initialize` is ignored.

## What is sent and what is never sent

Sent with every signal: your signal name, optional number and properties, a UTC timestamp, the debug flag, a random session id, and the device, app and settings values below. A value the platform cannot give is left out, never guessed. Nothing needs to be set up for any of it.

| Group | Values |
| --- | --- |
| Device | platform (`mobile` or `desktop`), device type (phone, tablet, desktop, tv, watch, car), manufacturer (Android) or Apple, device model, simulator or emulator flag, CPU architecture, OS name and version, Android API level, target environment (Apple: native, simulator, ios-on-mac) |
| Screen | logical width and height, pixel scale, width and height in pixels, density (Android), number of displays, orientation (phones and tablets) |
| Settings and accessibility | colour scheme (light or dark), layout direction, time zone id (macOS and Linux), UTC offset, language, preferred language, region, text scale, content size category (iOS), reduce motion, bold text, invert colours, increase contrast |
| Connection and power | connection type (wifi, cellular, ethernet, none, other), battery saver on or off |
| App and install | app name, version and build number, package or bundle id, install source (appstore, testflight, playstore, galaxystore, amazon, sideload, debug, other), debug build flag, Dart version (for example `Dart 3.10.4`), SDK name and version |
| Usage statistics | date of the first session, sessions so far, distinct days used (all time and last 30 days), previous session length, average session length, seconds since the session started, and `isNewInstall` during the first session |

Values that change while the app runs (orientation, colour scheme, text scale, accessibility settings, connection type, battery saver, UTC offset, screen size, session seconds) are read when each signal is captured, from cached state, without blocking. The rest is read once at start. The package or bundle id is sent unless you set `sendAppIdentity: false`.

Usage statistics are kept in one small file named `usage` next to the install id in the app's own storage and are deleted together with it on opt-out.

Automatic signals: the SDK sends `pulse.session_started` when a new session begins (app start, or the first signal after 30 minutes of inactivity), `pulse.new_install` once on the first launch after install, and `pulse.app_updated` (with `previousVersion` and `previousBuild`) once when the app version or build number changes. They are one per session or rarer, follow opt-out and carry the same debug flag as your own signals.

Sessions use a random 128-bit id that changes after 30 minutes of inactivity.

Anonymous install id: random, created by the SDK on first launch (16 random bytes from the platform's secure random generator) and stored only in the app's own storage, next to the offline queue. It is deleted with the app and replaced after opt-out. It is sent only as a SHA-256 hash, is not derived from any device identifier and is not shared between apps. Nothing needs to be set up for it.

User id: optional. If you call `setUser`, the hash of your id is sent instead of the install id hash. The id is hashed with SHA-256 on the device and the raw id is never stored or sent. The hash is pseudonymous and may still count as personal data. `setUser(null)` returns to the install id hash.

If the install id cannot be read or written, the SDK uses a random id kept in memory for that run.

Never sent: advertising ids, IDFV, Android ids, serial numbers, the device name set by the user, host names, user names, location, contacts, installed apps, network carrier, cookies or signing certificate hashes.

Web: the package does nothing on Flutter web. It stores no install id, sets no cookies and sends no signals there.

IP address: the SDK does not read or send the device's IP address as data. As with any HTTP request, the server sees the connection address, uses it only to derive a two-letter country code and does not store it.

Do not put secrets or personal information in signal names or properties.

## Options

```dart
await Pulse.initialize('YOUR_APP_KEY', options: const PulseOptions(
  flushIntervalSeconds: 30,
  maxBatchSize: 100,
  debug: false,
  sendAppIdentity: true,
));
```

| Option | Default | Behaviour |
| --- | --- | --- |
| `host` | `https://in.mightys.dev` | Base URL (HTTP or HTTPS, no credentials, query or fragment). An invalid host or an empty key leaves the SDK inactive. |
| `flushIntervalSeconds` | 20 | Seconds between batches after the first. Clamped to 0.05 through 3600. |
| `maxBatchSize` | 100 | Signals per request. Clamped to 1 through 1000. |
| `maxQueueSize` | 1000 | Signals kept offline. Clamped to 1 through 10000. The oldest are dropped first. |
| `maxQueueAgeDays` | 7 | Days a queued signal is kept. Clamped to at most 29. |
| `gzip` | true | Compresses batches larger than 1024 bytes. |
| `debug` | true in debug builds, false in profile and release | Marks signals as test data and prints short diagnostics. See [Test mode](#test-mode). |
| `sendAppIdentity` | true | Sends the package name as `system.bundleId`. Set false to leave it out. |
| `appVersion` | from the platform | Overrides the app version. |
| `automaticScreenViews` | true | Lets `Pulse.navigatorObserver` send screen views. Set false to switch them off. |
| `automaticSignals` | true | Sends `pulse.session_started`, `pulse.new_install` and `pulse.app_updated`. Set false to switch them off. |

## Screen views

Add one line to send a `pulse.screen_view` signal each time a screen appears:

```dart
MaterialApp(navigatorObservers: [Pulse.navigatorObserver], /* ... */);
// go_router: GoRouter(observers: [Pulse.navigatorObserver], /* ... */)
```

- Props: `screen` (at most 128 characters) and `previousScreen` when known. Never a URL, query, title or anything the user typed.
- Name: the route name, or the route class name when it has none. Query and fragment are removed, and numeric and uuid-like path segments become `:id`.
- Dialogs, bottom sheets and menus are not screens and are skipped. The same screen appearing again with no other screen in between is sent once.
- Other screens: call `Pulse.screen('Name')`. It works with or without the observer and follows opt-out.
- Switch off: `PulseOptions(automaticScreenViews: false)` makes the observer do nothing.

## Settings from the portal

The portal can switch these off for your app without a package update:

- screen views, and all automatic signals (`pulse.session_started`, `pulse.new_install`, `pulse.app_updated`, `pulse.screen_view`), or any one of those types
- the field groups device, screen, settings, network, app and usage (the basic platform, version, locale, SDK and bundle id fields are always sent)

Once per launch the SDK reads the settings in the background (it never delays `initialize`, `track` or `flush`) and keeps them in its own storage. A change applies from the next launch and stays the same for the whole run. Everything is on when the settings cannot be read: no network, an error, an unreadable answer, or none stored yet. Opt-out deletes the stored settings.

The options `automaticScreenViews` and `automaticSignals` can only switch things off as well. Setting them to true never turns on what the portal switched off, and `Pulse.screen` also sends nothing when the portal switched screen views off.

## Test mode

Every signal carries a `debug` flag. `debug: true` means test data, and the dashboard's test mode switch chooses whether you see test signals or real ones. You need only one app key per app: the same key serves both.

Unless you set it, `PulseOptions.debug` is `true` in a debug build (what `flutter run` starts) and `false` in profile and release builds. The default follows Flutter's build mode, is fixed for a given build and never changes while the app runs. An explicit value always wins, in both directions:

```dart
await Pulse.initialize('YOUR_APP_KEY', options: const PulseOptions(debug: true)); // force test data
```

## Delivery and offline behaviour

- The first batch after `initialize` is sent at once. Later batches follow the interval, the batch size, an explicit `flush`, or the app moving to the background.
- Signals are queued on disk and survive restarts. Network errors and server errors are retried with exponential backoff (one second up to five minutes), and a `Retry-After` header is honoured.
- Encoding, compression and file work run off the main thread.
- Each batch carries an id, so a batch sent again after a lost answer is stored only once.
- Delivery is at least once: after a crash a batch can be sent again. If the OS ends the app abruptly, the last signals may be lost.
- A 401 response keeps the queue and stops sending until the app restarts.
- The queue lives in the app support directory and needs a single owning process. App extensions that share it are not supported.

## Requirements

- Android and iOS (the connection type and battery saver values come from the `connectivity_plus` and `battery_plus` plugins; the Android merge adds the normal `ACCESS_NETWORK_STATE` permission)
- Dart 3.10 or newer, Flutter 3.38.1 or newer

## Opt-out

`await Pulse.setOptOut(true)` stops collection, clears the queue and cancels active requests; bytes already sent cannot be recalled. The choice is remembered across launches. `Pulse.setOptOut(false)` turns collection back on. `Pulse.optOut` reads the current state and is true until the stored choice has been read.

## Licence

MIT. See the LICENSE file.

## Reference

Signal names must be non-blank and at most 200 UTF-16 units, and values must be finite numbers. Properties may be `String`, `bool` (sent as `"true"` or `"false"`), `int` or finite `double`. Nested maps, lists, null and non-finite numbers are dropped. At most 32 properties are kept, in insertion order, with keys up to 128 and string values up to 1024 UTF-16 units, within 8192 UTF-8 bytes in total.

A runnable sample app is in the [`example`](example) folder:

```sh
cd example
flutter run --dart-define=PULSE_APP_KEY=YOUR_APP_KEY
```
