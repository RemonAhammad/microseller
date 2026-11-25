import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'package:micro_seller/core/l10n/translations_en.dart';
import 'package:micro_seller/data/services/drive_service.dart';

/// Issue #32: on Android, Sign in failed with "not configured" while Backup
/// to Drive worked, because Sign in did a full Google login, which needs the
/// web client id, and the app only ever needs Drive access.
void main() {
  const webId = '1084592092620-web.apps.googleusercontent.com';
  late _FakeGoogle google;

  void setUpPlatform(TargetPlatform platform, {String webClientId = ''}) {
    debugDefaultTargetPlatformOverride = platform;
    dotenv.loadFromString(envString: 'GOOGLE_OAUTH_WEB_CLIENT_ID=$webClientId');
    google = _FakeGoogle();
    GoogleSignInPlatform.instance = google;
    DriveService.resetForTesting();
  }

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    dotenv.clean();
  });

  group('Android without a web client id', () {
    setUp(() => setUpPlatform(TargetPlatform.android));

    test('a full login is not possible, so it is not tried', () {
      expect(DriveService.canAuthenticate, isFalse);
    });

    test('Sign in asks for Drive access only, as Backup to Drive does', () async {
      final account = await DriveService().signIn();
      expect(account, isNotNull);
      expect(account!.email, isNull);
      expect(google.authenticateCalls, 0);
      expect(google.prompts, 1);
      expect(google.initServerClientId, isNull);
    });

    test('Settings then shows it connected, without trying the login', () async {
      expect(await DriveService().getCurrentUser(), isNull);
      await DriveService().signIn();
      final current = await DriveService().getCurrentUser();
      expect(current, isNotNull);
      expect(current!.email, isNull);
      expect(google.lightweightCalls, 0);
    });

    test('Sign out drops the Drive token, so it reads as signed out', () async {
      final service = DriveService();
      await service.signIn();
      await service.signOut();
      expect(google.clearedTokens, ['drive-token']);
      expect(await service.getCurrentUser(), isNull);

      // And signing in again works.
      expect(await service.signIn(), isNotNull);
      expect(google.prompts, 2);
    });

    test('cancelling the Drive prompt is no error', () async {
      google.authorizeError =
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
      expect(await DriveService().signIn(), isNull);
    });

    test('Drive access itself refused as misconfigured is still a setup error', () async {
      google.authorizeError = const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError);
      await expectLater(
        DriveService().signIn(),
        throwsA(isA<DriveBackupException>()
            .having((e) => e.code, 'code', DriveErrorCode.developerError)),
      );
    });
  });

  group('Android with a web client id', () {
    setUp(() => setUpPlatform(TargetPlatform.android, webClientId: webId));

    test('Sign in logs in and shows the account email', () async {
      final account = await DriveService().signIn();
      expect(google.initServerClientId, webId);
      expect(google.authenticateCalls, 1);
      expect(account!.email, 'seller@example.com');
      expect((await DriveService().getCurrentUser())!.email, 'seller@example.com');
    });

    test('a web client id from another project falls back to Drive access', () async {
      google.authenticateError = const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError);
      final account = await DriveService().signIn();
      expect(account, isNotNull);
      expect(account!.email, isNull);
      expect(google.prompts, 1);
    });

    test('cancelling the login is no error and asks nothing more', () async {
      google.authenticateError =
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
      expect(await DriveService().signIn(), isNull);
      expect(google.prompts, 0);
    });
  });

  group('iOS', () {
    setUp(() => setUpPlatform(TargetPlatform.iOS));

    test('logs in as before (GIDClientID comes from Info.plist, not .env)', () async {
      expect(DriveService.canAuthenticate, isTrue);
      final account = await DriveService().signIn();
      expect(google.authenticateCalls, 1);
      expect(account!.email, 'seller@example.com');
    });
  });

  test('the not-configured message no longer blames the package name or SHA-1', () {
    final text = translationsEn['driveErrorNotConfigured']!;
    expect(text, isNot(contains('SHA-1')));
    expect(text, isNot(contains('package name')));
    expect(text, contains('Local Backup'));
  });
}

class _FakeGoogle extends GoogleSignInPlatform {
  String? initServerClientId;
  int authenticateCalls = 0;
  int lightweightCalls = 0;
  int prompts = 0;
  bool granted = false;
  final clearedTokens = <String>[];
  GoogleSignInException? authenticateError;
  GoogleSignInException? authorizeError;

  static const _user = GoogleSignInUserData(email: 'seller@example.com', id: '1');

  @override
  Future<void> init(InitParameters params) async =>
      initServerClientId = params.serverClientId;

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
      AttemptLightweightAuthenticationParameters params) async {
    lightweightCalls++;
    return null;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    authenticateCalls++;
    if (authenticateError != null) throw authenticateError!;
    return const AuthenticationResults(
      user: _user,
      authenticationTokens: AuthenticationTokenData(idToken: 'id'),
    );
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters params) async {
    if (params.request.promptIfUnauthorized && !granted) {
      prompts++;
      if (authorizeError != null) throw authorizeError!;
      granted = true;
    }
    return granted ? const ClientAuthorizationTokenData(accessToken: 'drive-token') : null;
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async {
    clearedTokens.add(params.accessToken);
    granted = false;
  }

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async => granted = false;
}
