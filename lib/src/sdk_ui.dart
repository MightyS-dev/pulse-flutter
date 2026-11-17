/// Tracks whether an App Control screen of the SDK covers the app. That screen
/// is never app usage: no debug picture is taken while it is up.
class PulseSdkUi {
  PulseSdkUi._();

  /// True while a built-in App Control screen, card or bar is on screen.
  static bool visible = false;
}
