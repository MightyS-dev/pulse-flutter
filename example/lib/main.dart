import 'package:flutter/material.dart';
import 'package:mightys_pulse/mightys_pulse.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pass your app key at build time: flutter run --dart-define=PULSE_APP_KEY=YOUR_APP_KEY
  const key = String.fromEnvironment('PULSE_APP_KEY');
  await Pulse.initialize(key);
  runApp(const ExampleApp(configured: key != ''));
}

/// The Pulse calls this example uses, so a test can replace them.
class PulseActions {
  const PulseActions({
    this.track = Pulse.track,
    this.setUser = Pulse.setUser,
    this.flush = Pulse.flush,
    this.setOptOut = Pulse.setOptOut,
    this.getOptOut = _optOut,
  });
  final void Function(String type, {num? value, Map<String, Object?>? props})
  track;
  final void Function(String?) setUser;
  final Future<void> Function() flush;
  final Future<void> Function(bool) setOptOut;
  final bool Function() getOptOut;
}

bool _optOut() => Pulse.optOut;

class ExampleApp extends StatelessWidget {
  const ExampleApp({
    super.key,
    this.actions = const PulseActions(),
    this.configured = true,
  });
  final PulseActions actions;
  final bool configured;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pulse example',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
    ),
    // One line shows the App Control screens (update required, maintenance ...).
    builder: Pulse.control.builder,
    navigatorObservers: [Pulse.navigatorObserver],
    home: ExampleScreen(actions: actions, configured: configured),
  );
}

class ExampleScreen extends StatefulWidget {
  const ExampleScreen({
    super.key,
    required this.actions,
    required this.configured,
  });
  final PulseActions actions;
  final bool configured;

  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  late bool _optedOut = widget.actions.getOptOut();
  bool _userSet = false;
  late String _status = widget.configured
      ? 'Ready.'
      : 'Run with --dart-define=PULSE_APP_KEY=YOUR_APP_KEY to send signals.';

  void _track() {
    // A named signal with an optional number and a few properties.
    widget.actions.track(
      'button.tap',
      value: 1,
      props: {'screen': 'home', 'count': 2},
    );
    setState(
      () => _status = 'Signal queued. Delivery happens in the background.',
    );
  }

  void _toggleUser() {
    // The id is hashed on the device; the raw id is never stored or sent.
    widget.actions.setUser(_userSet ? null : 'demo-user-1');
    setState(() {
      _userSet = !_userSet;
      _status = _userSet ? 'User set for future signals.' : 'User cleared.';
    });
  }

  Future<void> _flush() async {
    setState(() => _status = 'Flushing...');
    await widget.actions.flush();
    if (!mounted) return;
    setState(() => _status = 'Flush finished.');
  }

  Future<void> _setOptOut(bool value) async {
    await widget.actions.setOptOut(value);
    if (!mounted) return;
    setState(() {
      _optedOut = widget.actions.getOptOut();
      _status = _optedOut
          ? 'Collection off. The queue is cleared.'
          : 'Collection on.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.configured && !_optedOut;
    return Scaffold(
      appBar: AppBar(title: const Text('Pulse example')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                FilledButton(
                  onPressed: canSend ? _track : null,
                  child: const Text('Track signal'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: canSend ? _toggleUser : null,
                  child: Text(_userSet ? 'Clear user' : 'Set user'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: widget.configured ? _flush : null,
                  child: const Text('Flush'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Opt out'),
                  value: _optedOut,
                  onChanged: widget.configured ? _setOptOut : null,
                ),
                Text(_status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
