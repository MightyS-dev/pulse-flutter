import 'dart:async';
import 'dart:convert';
import 'package:mightys_pulse/src/core/control_client.dart';
import 'package:mightys_pulse/src/core/control_state.dart';
import 'package:mightys_pulse/src/core/control_version.dart';
import 'package:mightys_pulse/src/core/model.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'support.dart';

const controlKey = 'synthetic-key';
final controlUrl =
    'https://in.mightys.dev/api/v1/control/${ControlIds.forKey(controlKey)}';

/// A rules body of format 1 with every field present.
String rulesJson({
  int version = 1,
  bool off = false,
  Map<String, Object?> update = const {},
  List<Object?> blocked = const [],
  Object? maintenance,
  Object? announcement,
  Object? whatsNew,
  Map<String, Object?> custom = const {},
  List<String> disabled = const [],
}) => jsonEncode({
  'format': 1,
  'version': version,
  'off': off,
  'update': update,
  'blocked': blocked,
  'maintenance': maintenance,
  'announcement': announcement,
  'whatsNew': whatsNew,
  'texts': {'custom': custom},
  'disabledSdkVersions': disabled,
});

Map<String, Object?> requiredUpdate(
  String min, {
  String? storeVersion,
  String? storeUrl = 'https://pulse.mightys.dev/app',
}) => {
  'ios': {
    'min': min,
    'latest': min,
    'mode': 'required',
    'storeVersion': storeVersion,
    'storeUrl': storeUrl,
  },
};

/// One ControlClient on fake time, storage and transport.
class Rig {
  Rig({FakeStorage? storage, FakeTime? time, this.appVersion = '2.0.0'})
    : storage = storage ?? FakeStorage(),
      time = time ?? FakeTime() {
    client = ControlClient(
      clock: this.time,
      scheduler: this.time,
      storage: this.storage,
      transport: transport,
      localTime: (value) => value,
    );
    client.languageTags = () => const ['en'];
  }
  final FakeStorage storage;
  final FakeTime time;
  final transport = FakeTransport();
  late final ControlClient client;
  final String appVersion;

  void reply(String body, {int status = 200}) =>
      transport.controlReply = PulseResponse(status, body: body);

  void start({
    ControlMode mode = ControlMode.automatic,
    bool debug = false,
    String platform = 'ios',
    String sdk = 'pulse-flutter@0.9.7',
  }) => client.start(
    key: controlKey,
    signalsUrl: Uri.parse('https://in.mightys.dev/api/v1/signals'),
    mode: mode,
    appVersion: appVersion,
    appName: 'Garden',
    sdk: sdk,
    platform: platform,
    debug: debug,
  );

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.value();
    }
  }

  Future<void> advance(double seconds) async {
    time.advance(seconds);
    await settle();
  }

  int get requests => transport.controlRequests.length;

  /// A good cached answer saved at [savedAt] (default: now).
  void seedCache(String body, {DateTime? savedAt, String etag = '"1"'}) {
    final at = (savedAt ?? time.now).millisecondsSinceEpoch;
    final name = 'control-${hashText(controlKey).substring(0, 16)}';
    storage.files[name] = utf8.encode('$etag\n$at\n$body');
  }
}
