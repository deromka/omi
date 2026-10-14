import 'package:flutter/foundation.dart';

import 'package:omi/env/env.dart';

final class BackendUrlOverride {
  const BackendUrlOverride._(this.url);

  final String url;

  factory BackendUrlOverride.parse(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Enter a valid HTTP or HTTPS backend URL.');
    }
    if (uri.userInfo.isNotEmpty || uri.hasFragment || uri.hasQuery) {
      throw const FormatException('Backend URLs cannot contain credentials, queries, or fragments.');
    }
    if (uri.scheme == 'http' && !_isPrivateHost(uri.host)) {
      throw const FormatException('Public backend URLs must use HTTPS.');
    }

    final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return BackendUrlOverride._(uri.replace(path: normalizedPath).toString());
  }

  /// Whether a persisted backend URL may take effect.
  ///
  /// Upstream gates this on `!kReleaseMode`, so a release build silently
  /// discards the URL and every request goes to api.omi.me. That is the right
  /// default for an App Store build: a backend URL is a trust boundary, and
  /// nobody should be talked into pasting one by a stranger.
  ///
  /// This build is compiled by the person who runs it, for their own phone,
  /// to reach their own machine. Pass
  /// `--dart-define=OMI_ALLOW_BACKEND_OVERRIDE=true` to permit it. Without
  /// that define the upstream behaviour is unchanged, so a build made from
  /// this branch without the flag is still an ordinary Omi build.
  static const _allowInRelease =
      bool.fromEnvironment('OMI_ALLOW_BACKEND_OVERRIDE', defaultValue: false);

  /// True when a persisted override is honoured: any debug/profile build, or a
  /// release build compiled with the define above.
  static bool get overrideAllowed => _allowInRelease || !kReleaseMode;

  static bool restore(String persistedUrl, {bool? runtimeAllowed}) {
    runtimeAllowed ??= overrideAllowed;
    if (!runtimeAllowed) {
      Env.clearApiBaseUrlOverride();
      return false;
    }
    final value = persistedUrl.trim();
    if (value.isEmpty) {
      Env.clearApiBaseUrlOverride();
      return true;
    }
    try {
      Env.overrideApiBaseUrl(BackendUrlOverride.parse(value).url);
      return true;
    } on FormatException {
      Env.clearApiBaseUrlOverride();
      return false;
    }
  }

  static bool _isPrivateHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' || normalized == 'host.docker.internal' || normalized == '::1') return true;

    final octets = normalized.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((octet) => octet == null || octet < 0 || octet > 255)) return false;
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        first == 127 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 100 && second >= 64 && second <= 127);
  }
}
