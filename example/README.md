# Pulse example

A small app for the `mightys_pulse` package. It shows `Pulse.initialize`, `Pulse.track`, `Pulse.setUser`, `Pulse.flush` and the opt-out switch.

```sh
flutter pub get
flutter run --dart-define=PULSE_APP_KEY=YOUR_APP_KEY
```

Without a key the app starts and the controls stay disabled. The key is given at build time and is never stored in the repository. The code is in `lib/main.dart`.
