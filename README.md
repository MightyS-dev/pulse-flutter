# MightyS Pulse for Flutter

Privacy-first analytics for Flutter apps and games. No device IDs, offline queue, tiny.

MightyS Pulse lets you send named signals (events) with an optional number and a few properties, and see them in a dashboard. This package is for Flutter app and game developers who want usage numbers without advertising ids, device identifiers, cookies or fingerprinting.

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

Other calls:

```dart
Pulse.setUser('internal-account-id'); // optional
Pulse.setUser(null);                  // clears the user for later signals
await Pulse.flush();                  // waits until queued signals are delivered
```

Public calls never throw into your app and never block the main thread. Calls made before `initialize` finishes are kept (up to 100) and sent afterwards. A second `initialize` is ignored.

## What is sent and what is never sent

Sent with every signal: your signal name, optional number and properties, a UTC timestamp, the debug flag, a random session id, platform (`mobile` or `desktop`), OS name and version, app version and build, device model, locale, and the SDK name and version. The app's package or bundle id is sent only if you set `sendAppIdentity`.

Sessions use a random 128-bit id that changes after 30 minutes of inactivity.

User id: optional. If you call `setUser`, the id is hashed with SHA-256 on the device. The raw id is never stored or sent. The hash is pseudonymous and may still count as personal data. Without `setUser`, no user hash is sent.

Never sent: advertising ids, IDFV, Android ids, serial numbers, device names, host names, user names, location, contacts, cookies or signing certificate hashes.

IP address: the SDK does not read or send the device's IP address as data. As with any HTTP request, the server sees the connection address, uses it only to derive a two-letter country code and does not store it.

Do not put secrets or personal information in signal names or properties.

## Options

```dart
await Pulse.initialize('YOUR_APP_KEY', options: const PulseOptions(
  flushIntervalSeconds: 30,
  maxBatchSize: 100,
  debug: false,
  sendAppIdentity: false,
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
| `debug` | true in debug builds, false in profile and release | Marks signals as test data and prints short diagnostics. |
| `sendAppIdentity` | false | Adds the package name as `system.bundleId`. |
| `appVersion` | from the platform | Overrides the app version. |

## Delivery and offline behaviour

- The first batch after `initialize` is sent at once. Later batches follow the interval, the batch size, an explicit `flush`, or the app moving to the background.
- Signals are queued on disk and survive restarts. Network errors and server errors are retried with exponential backoff (one second up to five minutes), and a `Retry-After` header is honoured.
- Encoding, compression and file work run off the main thread.
- Delivery is at least once: after a crash a batch can be sent again. If the OS ends the app abruptly, the last signals may be lost.
- A 401 response keeps the queue and stops sending until the app restarts.
- The queue lives in the app support directory and needs a single owning process. App extensions that share it are not supported.

## Requirements

- Android and iOS
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
