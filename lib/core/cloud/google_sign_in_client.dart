// v27.33 — Google sign-in client abstraction.
//
// The Firebase backend talks to Google through this interface, never
// directly to the plugin, so tests inject a fake and production uses
// the real google_sign_in plugin. Only the token pair crosses this
// boundary — never a password, never a keystore secret.
//
// NO AUTO-LINKING (explicit design decision): a Google login is a
// SEPARATE Firebase Auth account from an Email/Password account,
// even when the email address matches. Firebase Auth itself refuses
// to merge them without an explicit link call, and this app does not
// perform that link silently — silently merging two accounts could
// hand one driver's data to another sign-in. Drivers must stick to
// ONE sign-in method per account. If a driver already has an
// Email/Password account and tries Google with the same email,
// Firebase returns account-exists-with-different-credential and the
// UI tells them to use their original sign-in method.
import 'package:google_sign_in/google_sign_in.dart';

/// Tokens returned by a Google sign-in attempt.
class GoogleSignInTokens {
  const GoogleSignInTokens({this.idToken, this.accessToken});

  final String? idToken;
  final String? accessToken;
}

abstract class GoogleSignInClient {
  /// Returns tokens, or null when the user cancelled the picker.
  Future<GoogleSignInTokens?> signIn();

  Future<void> signOut();
}

/// Production client backed by the google_sign_in plugin (v6 API).
class PluginGoogleSignInClient implements GoogleSignInClient {
  PluginGoogleSignInClient({GoogleSignIn? googleSignIn})
      : _google = googleSignIn ?? GoogleSignIn();

  final GoogleSignIn _google;

  @override
  Future<GoogleSignInTokens?> signIn() async {
    final account = await _google.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return GoogleSignInTokens(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );
  }

  @override
  Future<void> signOut() => _google.signOut();
}
