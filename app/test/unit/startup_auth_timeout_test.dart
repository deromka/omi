import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omi/startup_auth.dart';

void main() {
  group('resolveStartupAuth', () {
    test('a refresh that never returns does not block startup', () async {
      // The regression this guards. On iPhone 17 Pro / iOS 27.0 against a
      // Firebase Auth emulator on a non-loopback host, FirebaseAuth's forced
      // token refresh never returned — not an error, just silence. Because this
      // await sits before runApp(), the app showed the launch storyboard forever
      // and could not be started again until it was deleted, since the cached
      // session made every launch hang here.
      final neverCompletes = Completer<String?>();

      final result = await resolveStartupAuth(() => neverCompletes.future, timeout: const Duration(milliseconds: 50));

      expect(result, isFalse, reason: 'a stalled refresh must resolve as unauthenticated, not hang');
    });

    test('a successful refresh is authenticated', () async {
      final result = await resolveStartupAuth(() async => 'a-real-token', timeout: const Duration(seconds: 5));
      expect(result, isTrue);
    });

    test('a failed refresh is unauthenticated, exactly as before', () async {
      // getIdToken() already returns null on every failure branch and startup
      // already continued to the sign-in screen. The timeout must not change
      // that path.
      final result = await resolveStartupAuth(() async => null, timeout: const Duration(seconds: 5));
      expect(result, isFalse);
    });

    test('a slow but successful refresh still authenticates', () async {
      // The timeout must not log out a user on a merely slow network.
      final result = await resolveStartupAuth(
        () => Future<String?>.delayed(const Duration(milliseconds: 20), () => 'token'),
        timeout: const Duration(seconds: 5),
      );
      expect(result, isTrue);
    });

    test('an emulator profile does not pay the full ten seconds', () async {
      // The 10s allowance exists for a slow network. A profile pointed at the
      // auth emulator is a different case: the comment on resolveStartupAuth
      // records that a forced refresh against an emulator on a non-loopback
      // host never returns at all, so the wait is not an allowance, it is a
      // fixed toll at every launch.
      //
      // Measured on a self-hosted setup before this existed: resolve_auth took
      // 10,006 ms of a 13,127 ms startup, every time, with the launch
      // storyboard on screen throughout.
      expect(startupAuthTimeoutWithEmulator, lessThan(startupAuthTimeout));

      final stopwatch = Stopwatch()..start();
      final resolved = await resolveStartupAuth(
        () => Completer<String?>().future, // never returns, as measured
        timeout: startupAuthTimeoutWithEmulator,
      );
      stopwatch.stop();

      expect(resolved, isFalse, reason: 'a timeout means unauthenticated, not an error');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)),
          reason: 'the whole point is that the first frame is not held');
    });

    test('a quick refresh still wins under the shorter timeout', () async {
      // Short, not zero: when the emulator is reachable the refresh should
      // still be allowed to succeed.
      final resolved = await resolveStartupAuth(
        () async => 'a-real-token',
        timeout: startupAuthTimeoutWithEmulator,
      );
      expect(resolved, isTrue);
    });
  });
}
