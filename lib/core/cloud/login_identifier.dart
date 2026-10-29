// v27.33 — Login identifier handling (username OR phone OR email).
//
// The login screen has ONE identifier field + password. Resolution:
//   * contains '@'            → email, used directly;
//   * looks like a phone      → normalized, hashed, looked up in the
//                                phones collection → account email;
//   * anything else           → lowercased username, looked up in
//                                the usernames collection → email.
// The resolved email is then used with Firebase Auth's
// signInWithEmailAndPassword. Firebase Auth itself is email-based;
// the lookup collections exist only to bridge identifier → email.
//
// PHONE PRIVACY: the raw phone number is NEVER a Firestore doc id.
// The phones collection is keyed by SHA-256 of the normalized phone,
// so a doc id reveals nothing without knowing the phone number.
// Normalization (Egypt): strip spaces/dashes/parentheses and any
// leading '+', '0020', '20', or '0' country/trunk prefix, leaving
// the 10-digit national number (e.g. 10/11/12/15 + 8 digits).
// The same normalization runs at sign-up and at login, so every
// written form of one number resolves to the same key.
//
// USERNAME UNIQUENESS is case-insensitive: mapping keys are the
// lowercased username, and sign-up rejects a taken username in any
// case. Firestore rules additionally forbid creating over an
// existing mapping doc (create-only, no overwrite).
import 'package:crypto/crypto.dart';

/// Canonical 10-digit Egyptian national number, or '' if the input
/// cannot be normalized (too short, non-digit content).
String normalizeEgyptPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0020')) digits = digits.substring(4);
  if (digits.startsWith('20') && digits.length == 12) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('0') && digits.length == 11) {
    digits = digits.substring(1);
  }
  return digits;
}

/// True for a plausible Egyptian mobile: 10 digits starting with '1'
/// (010/011/012/015 after normalization).
bool isValidEgyptPhone(String input) {
  final digits = normalizeEgyptPhone(input);
  return digits.length == 10 && digits.startsWith('1');
}

/// Looks like a phone number (digits, '+', spaces, dashes) rather
/// than a username or email. Used only to pick the lookup path.
bool looksLikePhone(String input) {
  final trimmed = input.trim();
  if (trimmed.contains('@')) return false;
  if (trimmed.isEmpty) return false;
  return RegExp(r'^[+0-9][0-9 ()\-]*$').hasMatch(trimmed);
}

/// Lookup key for the phones collection: SHA-256 hex of the
/// normalized phone. Never the raw phone number.
String phoneLookupKey(String input) {
  final digits = normalizeEgyptPhone(input);
  return sha256.convert(digits.codeUnits).toString();
}

/// Lookup key for the email-username reminder collection: SHA-256
/// hex of the lowercased, trimmed email.
String emailLookupKey(String email) {
  return sha256.convert(email.trim().toLowerCase().codeUnits).toString();
}

/// Lookup key for the usernames collection: lowercased username.
String usernameLookupKey(String username) => username.trim().toLowerCase();
