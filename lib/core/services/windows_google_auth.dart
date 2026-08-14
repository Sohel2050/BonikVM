// Windows Google Sign-In.
//
// `google_sign_in` has no Windows platform implementation (Android/iOS/web
// only), so on Windows we do the OAuth flow ourselves per RFC 8252 ("OAuth
// for Native Apps"): open the system browser to Google's consent screen
// with a local loopback redirect URI, catch the redirect with a temporary
// HTTP server, then exchange the authorization code for tokens using PKCE
// (no client secret needed for a public/native client).
//
// The resulting id_token is fed into the SAME
// GoogleAuthProvider.credential(...) + FirebaseAuth.signInWithCredential
// path already used on mobile (see auth_service.dart) — Firebase Auth's
// Windows backend is REST-based and handles that call the same way
// regardless of platform.
//
// Requires a Google OAuth "Desktop app" client ID, which does not exist in
// this Firebase project yet (only Android/iOS client IDs were configured).
// Create one at https://console.cloud.google.com/apis/credentials
// (Create Credentials → OAuth client ID → Application type: Desktop app)
// and put it in .env as GOOGLE_DESKTOP_CLIENT_ID — this is a one-time,
// ~2 minute setup step that can't be done from inside this codebase since
// it requires access to the Google Cloud project.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';

class WindowsGoogleAuthResult {
  final String idToken;
  final String? accessToken;
  WindowsGoogleAuthResult({required this.idToken, this.accessToken});
}

class WindowsGoogleAuthException implements Exception {
  final String message;
  WindowsGoogleAuthException(this.message);
  @override
  String toString() => message;
}

class WindowsGoogleAuth {
  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  /// Runs the full loopback OAuth flow and returns Google ID/access tokens
  /// ready to hand to Firebase, or throws [WindowsGoogleAuthException].
  static Future<WindowsGoogleAuthResult> signIn() async {
    final clientId = AppConfig.googleDesktopClientId;
    if (clientId.isEmpty) {
      throw WindowsGoogleAuthException(
        'Google Sign-In isn\'t configured for Windows yet. '
        'Add GOOGLE_DESKTOP_CLIENT_ID to .env — see windows_google_auth.dart '
        'for setup instructions.',
      );
    }

    final verifier = _randomUrlSafeString(64);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomUrlSafeString(16);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/callback';

    try {
      final authUri = Uri.parse(_authEndpoint).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'openid email profile',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
          'prompt': 'select_account',
        },
      );

      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw WindowsGoogleAuthException('Could not open the browser.');
      }

      final code = await _waitForCode(server, expectedState: state).timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw WindowsGoogleAuthException(
          'Sign-in timed out. Please try again.',
        ),
      );

      // Google requires client_secret in this request even for Desktop app
      // clients using PKCE — confirmed via "invalid_request: client_secret
      // is missing" when omitted. It's admin-managed (see AppConfig), not
      // hardcoded.
      final clientSecret = AppConfig.googleDesktopClientSecret;
      final tokenResponse = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
          'code': code,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
        },
      );

      if (tokenResponse.statusCode != 200) {
        throw WindowsGoogleAuthException(
          'Google rejected the sign-in request: ${tokenResponse.body}',
        );
      }

      final tokenData =
          jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final idToken = tokenData['id_token'] as String?;
      if (idToken == null) {
        throw WindowsGoogleAuthException(
          'Google did not return an ID token.',
        );
      }

      return WindowsGoogleAuthResult(
        idToken: idToken,
        accessToken: tokenData['access_token'] as String?,
      );
    } finally {
      await server.close(force: true);
    }
  }

  static Future<String> _waitForCode(
    HttpServer server, {
    required String expectedState,
  }) async {
    await for (final request in server) {
      final params = request.uri.queryParameters;
      final error = params['error'];
      final code = params['code'];
      final returnedState = params['state'];

      request.response.headers.contentType = ContentType.html;
      if (error != null) {
        request.response.write(_resultPage(
          success: false,
          message: 'Sign-in was cancelled or denied.',
        ));
        await request.response.close();
        throw WindowsGoogleAuthException('Sign-in was cancelled.');
      }

      if (code == null || returnedState != expectedState) {
        request.response.write(_resultPage(
          success: false,
          message: 'Invalid sign-in response.',
        ));
        await request.response.close();
        continue;
      }

      request.response.write(_resultPage(
        success: true,
        message: 'Signed in! You can close this window and return to VPN MASTER.',
      ));
      await request.response.close();
      return code;
    }
    throw WindowsGoogleAuthException('Sign-in server closed unexpectedly.');
  }

  static String _resultPage({required bool success, required String message}) {
    final color = success ? '#16A34A' : '#DC2626';
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>VPN MASTER</title></head>
<body style="font-family:sans-serif;text-align:center;padding:60px;">
<h2 style="color:$color;">${success ? '&#10003;' : '&#10007;'} $message</h2>
</body></html>
''';
  }

  static String _randomUrlSafeString(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
