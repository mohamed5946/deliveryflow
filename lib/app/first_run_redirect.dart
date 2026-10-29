// v27.33 — First-run redirect rules, extracted pure for testing.
//
// This is EXACTLY the redirect logic the GoRouter uses (see
// router.dart, which delegates here). Order matters and is tested:
//   1. A geo: URI never becomes a route → /splash.
//   2. The registration (invite-code) gate comes before EVERYTHING:
//      fresh installs (registered == false) are sent to /register
//      no matter which route they asked for — including the account
//      screen. The existing gate implementation and its value are
//      reused unchanged; nothing here invents a new code.
//   3. A registered user asking for /register goes to /splash.
//   4. Splash / register pass through (splash navigates itself).
//   5. Onboarding rules: unfinished onboarding → /onboarding;
//      finished onboarding asking for /onboarding → /home.
// Upgraders (registered == true, gate already passed) skip step 2
// entirely and reach the account-choice screen directly.

/// Returns the redirect target, or null to stay on [matchedLocation].
String? resolveFirstRunRedirect({
  required bool registered,
  required bool onboardingDone,
  required String uriString,
  required String matchedLocation,
}) {
  if (uriString.startsWith('geo:')) return '/splash';
  final loc = matchedLocation;
  if (!registered && loc != '/register') return '/register';
  if (registered && loc == '/register') return '/splash';
  if (loc == '/splash' || loc == '/register') return null;
  if (!onboardingDone && loc != '/onboarding') return '/onboarding';
  if (onboardingDone && loc == '/onboarding') return '/home';
  return null;
}
