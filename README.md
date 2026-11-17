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
| Usage statistics | date of the first session, sessions so far, distinct days used (all time and last 30 days), previous session length, average session length, seconds since the session started, foregrounds today, length of the previous foreground period, the launch time of a cold start, and `isNewInstall` during the first session |

Values that change while the app runs (orientation, colour scheme, text scale, accessibility settings, connection type, battery saver, UTC offset, screen size, session seconds) are read when each signal is captured, from cached state, without blocking. The rest is read once at start. The package or bundle id is sent unless you set `sendAppIdentity: false`.

Usage statistics (including the foreground counters and the count of automatic signals sent today) are kept in one small file named `usage` next to the install id in the app's own storage and are deleted together with it on opt-out.

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
| `automaticSignals` | true | Sends `pulse.session_started`, `pulse.new_install`, `pulse.app_updated`, `pulse.deep_link` and, when the portal switches them on, `pulse.app_opened` and `pulse.app_backgrounded`. Set false to switch them off. |
| `captureErrors` | true | Sends unhandled errors as `pulse.error`. Set false to install no error handler at all. |
| `errorDetail` | `ErrorDetail.full` | `ErrorDetail.typeOnly` sends only the error type: no message and no frames. |
| `control` | `ControlMode.automatic` | App Control: `automatic` checks and shows the built-in screens, `manual` checks and only keeps `Pulse.control.state` up to date, `off` makes no request. See [App Control](#app-control). |
| `captureHeatmaps` | true | Follows the portal for tap heatmaps (off there until you switch it on). Set false to never capture taps. It can only switch capture off. See [Heatmaps](#heatmaps). |

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

## Automatic signals

Types the SDK can send by itself: `pulse.session_started`, `pulse.new_install`, `pulse.app_updated`, `pulse.screen_view`, `pulse.deep_link`, `pulse.app_opened`, `pulse.app_backgrounded` and `pulse.heatmap`. Switch them off in code with `PulseOptions(automaticSignals: false)` (all of them except screen views), `automaticScreenViews: false` (the observer), `captureErrors: false` (error capture) and `captureHeatmaps: false` (tap heatmaps, see [Heatmaps](#heatmaps)); `Pulse.setOptOut(true)` stops everything. The portal can switch or pause each type, and `pulse.app_opened` and `pulse.app_backgrounded` are sent only when the portal turns them on (they are off by default). Defaults and how many signals each type uses: https://pulse.mightys.dev/docs/automatic-signals/

What the new ones carry:

- `pulse.app_opened`: prop `coldStart` (`"true"` for the first foreground of the process, else `"false"`). It is sent on a real change to the foreground (`AppLifecycleState.resumed`), once, and never for `inactive`.
- `pulse.app_backgrounded`: prop `foregroundSeconds`. Sent when the app goes to `paused` or `hidden`. It never starts a session: when the last signal was 30 minutes or more ago it is dropped (the foreground counters below still update).
- `pulse.deep_link`: props `scheme`, `host`, `path` (numeric and uuid-like segments become `:id`, at most 128 characters) and `utmSource`, `utmMedium`, `utmCampaign` when the link has those tags (filtered, at most 64 characters each). Never the rest of the query, the fragment, credentials or a port. Flutter has no single place that sees every link, so you report them: `Pulse.deepLink(uri)` from your router, `onGenerateInitialRoutes` or an `app_links` stream. It follows opt-out and the switches above.
- `pulse.screen_view` gains `previousScreenSeconds` (whole seconds the previous screen was visible, time in the background excluded) on every view that has a `previousScreen`.

Extra system fields (in the `usage` group, switchable from the portal): `launchMs`, `foregroundsToday` and `previousForegroundSeconds`.

- `launchMs` is on the `pulse.session_started` of the first session of a process only. Flutter code cannot read the time the process started, so it measures from the `Pulse.initialize` call to the first rasterized frame (`WidgetsBinding.waitUntilFirstFrameRasterized`); when no frame was drawn yet by the time of the first signal, it runs to that signal. It does not include native engine start-up or the time before `initialize`, so call `initialize` early in `main`. Values over one hour are left out.
- `foregroundsToday` counts foregrounds on the device's local day (the cold start counts). `previousForegroundSeconds` is the length of the last finished foreground period, kept across launches.

Not available in this package, so not sent: `notificationPermission`, `trackingPermission` and with them `pulse.permission_changed`. None of the plugins this package uses can read those statuses, and the SDK never asks for a permission or adds a permission plugin. The portal switch for the `permissions` group exists for parity with the other SDKs and has no effect here.

Guards: per session at most 20 of each of `pulse.app_opened` and `pulse.app_backgrounded`, 10 `pulse.deep_link` and 100 `pulse.screen_view`, and at most 300 automatic signals per install and local day. Dropped ones are counted and the count is sent once as the system field `droppedAutomatic` on the next signal. Your own signals and `pulse.error` are never limited by this.

## Heatmaps

Heatmaps show where people tap on each screen. They are off until you switch them on for the app in the portal, and the option `captureHeatmaps: false` keeps them off in code whatever the portal says. They need screen views (use `Pulse.navigatorObserver` or `Pulse.screen`), because every tap is filed under the current screen name, and a tap with no known screen is not captured. Automatic signals must stay on as well.

What is collected: the screen name, where the tap landed (the share of the screen width and the distance from the top in logical pixels), the width class (phone below 600, tablet below 1024, else desktop), the orientation, and the kind: `tap`, or `rage` for the third and later tap within one second and 30 logical pixels. Taps are sent in batches as `pulse.heatmap` signals (at most 200 points each, at most 1000 per session) when the screen changes, the app goes to the background or `flush` runs.

What is never collected: no text, no widget names or ids, no recordings, no screenshots in release builds. A tap is never captured while the on-screen keyboard is visible, on a text field (including password fields), while a text field has the focus, or inside a `PulseHeatmapIgnore`. A drag, a second finger and a secondary mouse button are not taps.

The SDK only watches pointer events through one global pointer route. It never consumes or delays an event and it adds no widget to your tree.

Keep an area out of the heatmap:

```dart
PulseHeatmapIgnore(child: AccountCard())
```

It has no visual effect and does not change hit testing for your widgets.

Screenshots: so the portal can draw the taps over a picture of the screen, a debug build (`kDebugMode`, so `flutter run` and debug installs, never profile or release) uploads one PNG per screen, width class, orientation and app version, about one second after the screen appears and never while the keyboard is visible. The picture is taken from the root layer of the render tree and has its longest side scaled to at most 2048 pixels. It is sent at most 20 times per hour and a marker in the app's own storage stops a repeat. If it fails, nothing happens. Release builds never send pictures.

The heatmap switch follows the newest settings the SDK reads from the portal during the run: switching heatmaps off stops capture at once and drops the taps not sent yet.

## Errors and crashes

By default the SDK sends unhandled errors as `pulse.error` signals, so you can see what broke and where:

- What is captured: errors that reach `FlutterError.onError` and `PlatformDispatcher.instance.onError` (kind `error`). The handlers that were installed before are kept and called with the same arguments, and the result of the previous `PlatformDispatcher` handler is returned unchanged. Without one, the SDK returns false, so Flutter still logs the error as usual. Nothing is swallowed and the handlers never throw.
- What is sent: the error type, a filtered message (at most 500 characters) and up to 30 frames, top first, each as `Function file.dart:42` (file name only, no directory). The whole error object is at most 16 KB.
- The filter: emails, URLs (query and fragment), UUIDs, IP addresses, runs of 6 or more digits and directories of absolute paths are replaced or cut in the message and in every frame.
- Type only: `PulseOptions(errorDetail: ErrorDetail.typeOnly)` sends just the type.
- Handled errors: send an error you caught yourself with `Pulse.trackError(error, stack, {'screen': 'cart'})` (kind `handled`; the current stack is used when you give none). It works even when `captureErrors` is false.
- Limits: at most 10 errors per error type and session are sent, so a loop cannot flood your quota. Opt-out stops capture.
- Switch off: `PulseOptions(captureErrors: false)` installs no handler.
- Symbolication: in a build made with `--split-debug-info` the frames are raw addresses (`#00 abs ...`). They are sent as they are and marked as not symbolicated, so they are not readable in the dashboard yet.

```dart
try {
  await checkout();
} catch (error, stack) {
  Pulse.trackError(error, stack, {'step': 'payment'});
}
```

## App Control

Require an update, suggest one or put the app into maintenance from the Pulse portal, without releasing a new build. Add one line to your app:

```dart
MaterialApp(
  builder: Pulse.control.builder, // shows the App Control screens above your app
  home: const Home(),
)
```

It fits `CupertinoApp` and `WidgetsApp` too (`builder` has the signature of `TransitionBuilder`). The screens are: a full screen for a required update, a blocked version and maintenance; a dialog for a suggested update; a card for an announcement or what's new; and a bar for a maintenance window that starts soon. They follow your theme (light and dark), the text size of the device and the language of your app (12 languages built in), use Material on Android and a Cupertino look on iOS, and read out properly with a screen reader. Colors, shape and text styles can be changed:

```dart
Pulse.control.theme = const PulseControlTheme(accentColor: Color(0xFF0B6E4F));
```

This package has no native code and opens no links itself, so tell it how to open the store page. With `url_launcher` in your app:

```dart
Pulse.control.onOpenStore = (url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
```

Without `onOpenStore` the built-in screens show no Update button, and a required update is shown as a suggestion that can be dismissed: there is always a way out.

Draw your own screens instead with `PulseOptions(control: ControlMode.manual)`:

```dart
Pulse.control.stream.listen((state) {
  if (state.kind == ControlKind.updateRequired) {
    // state.title, state.body, state.buttonText, state.url ...
  }
});
// Pulse.control.state, Pulse.control.checkNow(), Pulse.control.openStore(), Pulse.control.dismiss()
```

`PulseOptions(control: ControlMode.off)` makes no request at all and the state is always `ControlKind.normal`.

For App Store review: the rules never apply to a version newer than the one in the store, so a build in review is not blocked by a minimum you set for the released version. In a debug build every locking screen shows a "Test build" bar and a Continue button.

How it fails safely:

- `Pulse.initialize` never waits for App Control and your first frame never waits for it either.
- The rules are read in the background once after start and again when the app returns to the foreground, at most once a minute, with 3 seconds to connect and 5 seconds in all. There is no retry loop.
- Any failure (no network, an error answer, an answer that is not valid, larger than 64 KiB or of another format) keeps the last known state from the cache, or normal. Never a lock from the unknown.
- A locking rule from a cache older than 30 days is ignored, and a cached maintenance never lasts past its end or 72 hours after its start.
- If the store version is not newer than the installed one, or the user pressed Update three times and came back on the same version, a required update becomes a suggestion.
- The app is never closed by App Control, and there is no Exit button.
- The request carries no key and no identity (not even the app key) and App Control keeps working when analytics is opted out.

## Settings from the portal

The portal can switch these off for your app without a package update:

- screen views, and all automatic signals (`pulse.session_started`, `pulse.new_install`, `pulse.app_updated`, `pulse.screen_view`, `pulse.deep_link`), or any one of those types; pause a type (the server does this near the plan limit); switch on `pulse.app_opened` and `pulse.app_backgrounded`
- heatmaps (`pulse.heatmap`, off by default), and the type itself
- the field groups device, screen, settings, network, app, usage and permissions (the basic platform, version, locale, SDK and bundle id fields are always sent)

Once per launch the SDK reads the settings in the background (it never delays `initialize`, `track` or `flush`) and keeps them in its own storage. A change applies from the next launch and stays the same for the whole run, except the heatmap switch, which follows the newest settings at once. Everything is on when the settings cannot be read: no network, an error, an unreadable answer, or none stored yet. Opt-out deletes the stored settings.

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

Supported plugin versions. The SDK works with any version in these ranges, so your app can keep the older plugin majors it already uses:

| Plugin | Supported versions |
|---|---|
| `device_info_plus` | 11.0.0 up to (not including) 14.0.0 |
| `package_info_plus` | 8.0.2 up to (not including) 11.0.0 |
| `connectivity_plus` | 5.0.0 up to (not including) 8.0.0 |
| `battery_plus` | 5.0.1 up to (not including) 8.0.0 |
| `path_provider` | 2.1.5 or newer 2.x |
| `crypto` | 3.0.6 or newer 3.x |

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
