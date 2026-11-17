/// Removes personal data from error text. Applied to every message and frame
/// before it is stored or sent.
abstract final class ErrorFilter {
  static const _mark = '<filtered>';
  static const _hex = '[0-9a-fA-F]{1,4}';
  static final _email = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
  );
  static final _url = RegExp(r'([A-Za-z][A-Za-z0-9+.-]*://[^\s?#]*)[?#]\S*');
  static final _uuid = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );
  static final _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
  static final _ipv6 = RegExp(
    '(?<![\\w:])(?:(?:$_hex:){7}$_hex|(?=[0-9a-fA-F:]*[0-9a-fA-F])'
    '(?:$_hex(?::$_hex){0,6})?::(?:$_hex(?::$_hex){0,6})?)(?![\\w:])',
  );
  static final _digits = RegExp(r'0[xX][0-9a-fA-F]+|\d{6,}');

  /// The line and optional column right after a file name in a frame.
  static final _position = RegExp(r'(?<=\.[A-Za-z0-9]{1,5}:)\d+(?::\d+)?');
  static final _fileUrl = RegExp(r'file://[^\s/]*/(?:[^\s/]+/)*([^\s/]+)');
  static final _windowsPath = RegExp(
    r'(?<!\w)[A-Za-z]:\\(?:[^\s\\]+\\)*([^\s\\]+)',
  );
  static final _unixPath = RegExp(r'(?<![\w/.:<>~-])/(?:[^\s/]+/)*([^\s/]+)');

  /// [text] with emails, URL queries and fragments, UUIDs, IP addresses, runs
  /// of six or more digits and directories of absolute paths replaced or cut.
  ///
  /// With [frame], a line and column after a file name are kept; a message
  /// has no such exemption.
  static String apply(String text, {bool frame = false}) {
    var result = text.replaceAll(_email, _mark);
    result = result.replaceAllMapped(_url, (m) => '${m[1]}$_mark');
    result = result.replaceAll(_uuid, _mark);
    result = result.replaceAll(_ipv4, _mark);
    result = result.replaceAll(_ipv6, _mark);
    final kept = frame
        ? _position.allMatches(result).toList()
        : const <RegExpMatch>[];
    result = result.replaceAllMapped(
      _digits,
      (m) =>
          m[0]!.startsWith(RegExp('0[xX]')) ||
              kept.any((k) => k.start < m.end && m.start < k.end)
          ? m[0]!
          : _mark,
    );
    result = result.replaceAllMapped(_fileUrl, (m) => m[1]!);
    result = result.replaceAllMapped(_windowsPath, (m) => m[1]!);
    return result.replaceAllMapped(_unixPath, (m) => m[1]!);
  }
}
