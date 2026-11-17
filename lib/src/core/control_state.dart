/// How the SDK treats App Control.
enum ControlMode {
  /// Checks the rules and shows the built-in screens. This is the default.
  /// Add `builder: Pulse.control.builder` to your app so the screens can show.
  automatic,

  /// Checks the rules and keeps the state up to date, but shows nothing: draw
  /// your own screens from `Pulse.control.state`.
  manual,

  /// No network request is made for App Control and the state is always
  /// [ControlKind.normal].
  off,
}

/// The eight things App Control can ask for.
enum ControlKind {
  /// Nothing to show.
  normal,

  /// A newer version is available: a dialog with "Update" and "Not now".
  updateSuggested,

  /// The version is too old: a full screen the user cannot close.
  updateRequired,

  /// This version is blocked: a full screen, with Continue when
  /// [ControlState.allowContinue] is true.
  versionBlocked,

  /// Down for maintenance: a full screen with "Try again".
  maintenance,

  /// A maintenance window starts soon: a bar.
  maintenanceUpcoming,

  /// An announcement card.
  announcement,

  /// A what's new card after an update.
  whatsNew,
}

/// What the app should show right now. Read it from `Pulse.control.state` or
/// listen to `Pulse.control.stream`.
class ControlState {
  const ControlState(
    this.kind, {
    this.title,
    this.body,
    this.buttonText,
    this.secondaryButtonText,
    this.url,
    this.startsAt,
    this.endsAt,
    this.version,
    this.allowContinue = true,
    this.isTestBuild = false,
    this.testBuildText,
  });

  /// The state when there is nothing to show.
  static const normal = ControlState(ControlKind.normal);

  /// What to show.
  final ControlKind kind;

  /// Screen title, or null.
  final String? title;

  /// Screen text, or the banner text for [ControlKind.maintenanceUpcoming].
  final String? body;

  /// Text of the main button (update, try again, OK), or null when the screen
  /// has none.
  final String? buttonText;

  /// Text of the second button ("Not now" or "Continue"), or null when the user
  /// cannot leave the screen.
  final String? secondaryButtonText;

  /// Where the main button goes: the store page or the link of an
  /// announcement, or null.
  final String? url;

  /// Start of the maintenance window (UTC), or null.
  final DateTime? startsAt;

  /// End of the maintenance window (UTC), or null.
  final DateTime? endsAt;

  /// The version a card is about (what's new), the announcement id, or null.
  final String? version;

  /// True when the user may leave the screen (`Pulse.control.dismiss` works).
  final bool allowContinue;

  /// True in a debug build: a locking screen then also shows a test banner and
  /// a Continue button.
  final bool isTestBuild;

  /// Text of the test banner when [isTestBuild] is true.
  final String? testBuildText;

  /// True for every kind except [ControlKind.normal].
  bool get isActive => kind != ControlKind.normal;

  ControlState copyWith({
    bool? allowContinue,
    bool? isTestBuild,
    String? testBuildText,
  }) => ControlState(
    kind,
    title: title,
    body: body,
    buttonText: buttonText,
    secondaryButtonText: secondaryButtonText,
    url: url,
    startsAt: startsAt,
    endsAt: endsAt,
    version: version,
    allowContinue: allowContinue ?? this.allowContinue,
    isTestBuild: isTestBuild ?? this.isTestBuild,
    testBuildText: testBuildText ?? this.testBuildText,
  );

  @override
  bool operator ==(Object other) =>
      other is ControlState &&
      other.kind == kind &&
      other.title == title &&
      other.body == body &&
      other.buttonText == buttonText &&
      other.secondaryButtonText == secondaryButtonText &&
      other.url == url &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt &&
      other.version == version &&
      other.allowContinue == allowContinue &&
      other.isTestBuild == isTestBuild &&
      other.testBuildText == testBuildText;

  @override
  int get hashCode => Object.hash(
    kind,
    title,
    body,
    buttonText,
    secondaryButtonText,
    url,
    startsAt,
    endsAt,
    version,
    allowContinue,
    isTestBuild,
    testBuildText,
  );

  @override
  String toString() => 'ControlState(${kind.name})';
}
