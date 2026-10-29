// v27.33 — Cloud account screen.
//
// FIRST-RUN / ACCOUNT CHOICE (Mohamed's flow): a signed-out user
// NEVER lands straight on a login form. This screen FIRST offers
// two choices — "إنشاء حساب" (Create account) or "لدي حساب بالفعل"
// (Already have an account). The invite-code gate runs BEFORE this
// screen for fresh installs (router forces /register while
// settings.registered is false); upgraders (gate already passed)
// reach this choice directly, with a first-login migration offer
// for their local data after they sign in.
//
// LOGIN: ONE identifier field + password. The identifier may be a
// username, a phone number, or an email — the backend resolves it
// to the Firebase email account (see login_identifier.dart).
// Sign-up collects username + phone + email + password; username
// and phone are each unique (live availability check while typing
// + mapping-doc check at sign-up + create-only rules server-side).
// A taken username shows EXACTLY: "الـ username ده اتاخد قبل كده،
// اختار username تاني" (and the equivalent phone message).
//
// FORCED PASSWORD CHANGE: when the signed-in account's user doc has
// mustChangePassword=true (set ONLY by the project owner in the
// Firebase console for the admin account — there is NO default or
// initial password anywhere in code), this screen shows ONLY the
// password-change form: no dashboard access, no data, no skip.
// After a successful change the flag clears and normal access
// resumes. The old password stops working immediately (Firebase).
//
// SESSION: closing, backgrounding, or rebooting NEVER logs out —
// Firebase Auth persistence restores the session at startup (see
// main()). The ONLY logout path is the explicit Sign out button
// below, with a confirmation dialog; it clears the per-account
// cloud cache and returns here, to the account-choice screen.
//
// Passwords are never stored anywhere by this app — they go only
// to Firebase Auth. A phone number alone NEVER authorizes a
// password change: in-app change requires the current password,
// and the forgot flow is email-reset-link only (v1).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cloud/cloud_providers.dart';
import '../../core/cloud/login_identifier.dart';
import '../../core/providers.dart';
import '../../theme/design_system.dart';
import 'local_migration.dart';

enum _AccountView { choice, signIn, signUp }

class CloudAccountScreen extends ConsumerStatefulWidget {
  const CloudAccountScreen({super.key});

  @override
  ConsumerState<CloudAccountScreen> createState() =>
      _CloudAccountScreenState();
}

class _CloudAccountScreenState extends ConsumerState<CloudAccountScreen> {
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  _AccountView _view = _AccountView.choice;
  bool? _usernameAvailable;
  Timer? _usernameTimer;
  bool _migrationOffered = false;
  String? _formError;

  @override
  void dispose() {
    for (final c in [
      _identifierCtrl,
      _passwordCtrl,
      _usernameCtrl,
      _phoneCtrl,
      _emailCtrl,
    ]) {
      c.dispose();
    }
    _usernameTimer?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _usernameTimer?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _usernameAvailable = null);
      return;
    }
    _usernameTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final available = await ref
            .read(cloudAccountProvider.notifier)
            .isUsernameAvailable(value);
        if (mounted) setState(() => _usernameAvailable = available);
      } catch (_) {
        // Unconfigured backend: hide the availability note.
        if (mounted) setState(() => _usernameAvailable = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(cloudConfiguredProvider);
    final state = ref.watch(cloudAccountProvider);
    final account = state.account;
    // Display errors without the "Exception: " prefix so mapped
    // messages (e.g. the taken-username message) show EXACTLY.
    final errorText = (state.error ?? _formError)
        ?.replaceFirst('Exception: ', '');
    return GlassScaffold(
      appBar: AppBar(title: const Text('Cloud account')),
      body: SingleChildScrollView(
        padding: GlassTokens.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!configured)
              const GlassCard(
                child: Text(
                  'Cloud not configured yet: connect a Firebase '
                  'project (google-services.json, Auth enabled, '
                  'Firestore created, rules pasted) to enable '
                  'sign-in and sync. Until then the app keeps '
                  'working local-only.',
                ),
              ),
            if (account != null) ...[
              if (account.mustChangePassword) ...[
                // FORCED CHANGE: nothing else is reachable from here
                // — no Management button, no data, no skip. Sign-out
                // is still allowed (it ends the session; signing
                // back in forces the change again until completed).
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'يجب تغيير كلمة المرور قبل استخدام التطبيق',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'This account requires a password change '
                        'before any access. Enter the current '
                        'password and a new one.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _ChangePasswordForm(
                  key: const ValueKey('forcedChangePasswordForm'),
                  onDone: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password changed'),
                      ),
                    );
                  },
                ),
              ] else ...[
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.username.isEmpty
                            ? account.email
                            : account.username,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(account.email),
                      if (account.phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(account.phone),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Role: ${account.role.name}'
                        '${account.isManager ? ' — you can open Management' : ''}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (account.isManager)
                  GlassButton(
                    label: 'Open Management',
                    icon: Icons.supervisor_account_rounded,
                    onPressed: () => context.push('/management'),
                  ),
                const SizedBox(height: 12),
                GlassButton(
                  label: 'Change username',
                  icon: Icons.person_rounded,
                  primary: false,
                  onPressed: () => _changeUsernameDialog(context),
                ),
                const SizedBox(height: 12),
                GlassButton(
                  label: 'Change password',
                  icon: Icons.lock_rounded,
                  primary: false,
                  onPressed: () => _changePasswordDialog(context),
                ),
              ],
              const SizedBox(height: 12),
              GlassButton(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                primary: false,
                onPressed: () => _confirmSignOut(context),
              ),
            ] else if (_view == _AccountView.choice) ...[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Sign in to sync your data across devices, or '
                      'create a cloud account. You can keep using '
                      'the app local-only without an account.',
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      key: const ValueKey('cloudChoiceCreate'),
                      label: 'إنشاء حساب',
                      icon: Icons.person_add_rounded,
                      onPressed: () =>
                          setState(() => _view = _AccountView.signUp),
                    ),
                    const SizedBox(height: 12),
                    GlassButton(
                      key: const ValueKey('cloudChoiceExisting'),
                      label: 'لدي حساب بالفعل',
                      icon: Icons.login_rounded,
                      primary: false,
                      onPressed: () =>
                          setState(() => _view = _AccountView.signIn),
                    ),
                  ],
                ),
              ),
            ] else if (_view == _AccountView.signIn) ...[
              GlassCard(
                child: Column(
                  children: [
                    TextField(
                      key: const ValueKey('cloudIdentifierField'),
                      controller: _identifierCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username, phone, or email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('cloudPasswordField'),
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (state.busy)
                      const CircularProgressIndicator()
                    else ...[
                      GlassButton(
                        key: const ValueKey('cloudSignInButton'),
                        label: 'Sign in',
                        icon: Icons.login_rounded,
                        onPressed: _submitSignIn,
                      ),
                      const SizedBox(height: 12),
                      GlassButton(
                        key: const ValueKey('cloudGoogleSignInButton'),
                        label: 'Sign in with Google',
                        icon: Icons.account_circle_rounded,
                        primary: false,
                        onPressed: _submitGoogle,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use one sign-in method per account: a Google '
                        'login is a separate account from an Email / '
                        'Password login with the same email.',
                      ),
                      TextButton(
                        key: const ValueKey('cloudForgotLink'),
                        onPressed: () => _forgotDialog(context),
                        child: const Text('Forget password or username'),
                      ),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText,
                        key: const ValueKey('cloudErrorText'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _view = _AccountView.choice),
                child: const Text('Back to account choices'),
              ),
            ] else ...[
              GlassCard(
                child: Column(
                  children: [
                    TextField(
                      key: const ValueKey('cloudUsernameField'),
                      controller: _usernameCtrl,
                      onChanged: _onUsernameChanged,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_usernameAvailable != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _usernameAvailable!
                            ? 'الـ username ده متاح'
                            : 'الـ username ده اتاخد قبل كده، اختار username تاني',
                        key: const ValueKey('cloudUsernameAvailability'),
                        style: TextStyle(
                          color: _usernameAvailable!
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('cloudPhoneField'),
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (Egypt, e.g. 01xxxxxxxxx)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('cloudSignupEmailField'),
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('cloudPasswordField'),
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password (6+ characters)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (state.busy)
                      const CircularProgressIndicator()
                    else
                      GlassButton(
                        key: const ValueKey('cloudSignUpButton'),
                        label: 'Create account',
                        icon: Icons.person_add_rounded,
                        onPressed: _submitSignUp,
                      ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText,
                        key: const ValueKey('cloudErrorText'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _view = _AccountView.choice),
                child: const Text('Back to account choices'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submitSignIn() async {
    final notifier = ref.read(cloudAccountProvider.notifier);
    final ok = await notifier.signInWithIdentifier(
      identifier: _identifierCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed in')),
      );
      await _maybeOfferMigration();
    }
  }

  Future<void> _submitGoogle() async {
    final notifier = ref.read(cloudAccountProvider.notifier);
    final ok = await notifier.signInWithGoogle();
    if (ok &&
        mounted &&
        ref.read(cloudAccountProvider).account != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed in')),
      );
      await _maybeOfferMigration();
    }
  }

  Future<void> _submitSignUp() async {
    final username = _usernameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty) {
      setState(() => _formError = 'Enter a username.');
      return;
    }
    if (!isValidEgyptPhone(phone)) {
      setState(
        () => _formError = 'Enter a valid Egyptian mobile number.',
      );
      return;
    }
    if (!email.contains('@')) {
      setState(() => _formError = 'Enter a valid email.');
      return;
    }
    if (password.length < 6) {
      setState(() => _formError = 'Password must be 6+ characters.');
      return;
    }
    setState(() => _formError = null);
    final notifier = ref.read(cloudAccountProvider.notifier);
    final ok = await notifier.signUp(
      email: email,
      password: password,
      username: username,
      phone: phone,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created')),
      );
      await _maybeOfferMigration();
    }
  }

  /// First-login migration offer for upgraders: local Hive data
  /// exists and this account has never migrated it. Shown ONCE per
  /// sign-in (and never again once the marker is set).
  Future<void> _maybeOfferMigration() async {
    if (_migrationOffered || !mounted) return;
    _migrationOffered = true;
    final account = ref.read(cloudAccountProvider).account;
    if (account == null) return;
    final db = ref.read(databaseServiceProvider);
    if (db.settings.cloudMigratedUid == account.uid) return;
    final settings = ref.read(settingsProvider);
    final data = buildLocalMigrationData(db, settings, account.uid);
    if (data.summaries.isEmpty && data.orders.isEmpty) return;
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload your local data?'),
        content: Text(
          'Found ${data.summaries.length} days of local data on this '
          'device. Upload it to your cloud account so it syncs and '
          'the manager can see it? This happens only once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            key: const ValueKey('cloudMigrationAccept'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final sync = ref.read(cloudSyncServiceProvider);
    final done = await sync.migrateLocalDataOnce(
      uid: account.uid,
      alreadyMigratedUid: db.settings.cloudMigratedUid,
      localSummaries: data.summaries,
      localOrders: data.orders,
      markMigrated: (uid) async {
        final s = db.settings;
        s.cloudMigratedUid = uid;
        await db.saveSettings(s);
      },
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            done ? 'Local data uploaded' : 'Upload skipped',
          ),
        ),
      );
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will return to the account-choice screen. Your '
          'cloud session ends and the next account cannot see '
          'your downloaded data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('cloudSignOutConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(cloudAccountProvider.notifier).signOut();
    }
  }

  Future<void> _changeUsernameDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change username'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('cloudChangeUsernameField'),
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'New username',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!.replaceFirst('Exception: ', ''),
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('cloudChangeUsernameSave'),
              onPressed: () async {
                final ok = await ref
                    .read(cloudAccountProvider.notifier)
                    .changeUsername(ctrl.text.trim());
                if (!ctx.mounted) return;
                if (ok) {
                  Navigator.pop(ctx, true);
                } else {
                  setDialogState(() {
                    error = ref.read(cloudAccountProvider).error;
                  });
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username changed')),
      );
    }
  }

  Future<void> _changePasswordDialog(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ChangePasswordDialog(),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed')),
      );
    }
  }

  Future<void> _forgotDialog(BuildContext context) async {
    final emailCtrl = TextEditingController();
    String? result;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Forget password or username'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('cloudForgotEmailField'),
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Account email',
                  border: OutlineInputBorder(),
                ),
              ),
              if (result != null) ...[
                const SizedBox(height: 8),
                Text(
                  result!,
                  key: const ValueKey('cloudForgotResult'),
                ),
              ],
              const SizedBox(height: 4),
              const Text(
                'Phone-OTP reset is not available: resetting a '
                'password from a phone number alone is not secure '
                'without a backend service. Use the email link, or '
                'change your password while signed in.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            TextButton(
              key: const ValueKey('cloudForgotUsernameButton'),
              onPressed: () async {
                final name = await ref
                    .read(cloudAccountProvider.notifier)
                    .lookupUsernameByEmail(emailCtrl.text.trim());
                if (ctx.mounted) {
                  setDialogState(() {
                    result = name == null
                        ? 'No account found for this email.'
                        : 'Your username is: $name';
                  });
                }
              },
              child: const Text('Show my username'),
            ),
            TextButton(
              key: const ValueKey('cloudForgotResetButton'),
              onPressed: () async {
                final ok = await ref
                    .read(cloudAccountProvider.notifier)
                    .sendPasswordReset(emailCtrl.text.trim());
                if (ctx.mounted) {
                  setDialogState(() {
                    result = ok
                        ? 'Reset link sent to ${emailCtrl.text.trim()}'
                        : 'Could not send reset link.';
                  });
                }
              },
              child: const Text('Send reset link'),
            ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }
}

/// Shared current + new password form, used by the forced-change
/// gate and by the signed-in change-password dialog.
class _ChangePasswordForm extends ConsumerStatefulWidget {
  const _ChangePasswordForm({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<_ChangePasswordForm> createState() =>
      _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<_ChangePasswordForm> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          TextField(
            key: const ValueKey('cloudChangeCurrentPasswordField'),
            controller: _currentCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Current password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('cloudChangeNewPasswordField'),
            controller: _newCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password (6+ characters)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_busy)
            const CircularProgressIndicator()
          else
            GlassButton(
              key: const ValueKey('cloudChangePasswordSave'),
              label: 'Change password',
              icon: Icons.lock_rounded,
              onPressed: () async {
                if (_newCtrl.text.length < 6) {
                  setState(
                    () => _error = 'New password must be 6+ characters.',
                  );
                  return;
                }
                setState(() {
                  _error = null;
                  _busy = true;
                });
                final ok = await ref
                    .read(cloudAccountProvider.notifier)
                    .changePassword(
                      currentPassword: _currentCtrl.text,
                      newPassword: _newCtrl.text,
                    );
                if (!mounted) return;
                setState(() => _busy = false);
                if (ok) {
                  widget.onDone();
                } else {
                  setState(() {
                    _error = ref
                        .read(cloudAccountProvider)
                        .error
                        ?.replaceFirst('Exception: ', '');
                  });
                }
              },
            ),
        ],
      ),
    );
  }
}

class _ChangePasswordDialog extends StatelessWidget {
  const _ChangePasswordDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: _ChangePasswordForm(
        onDone: () => Navigator.pop(context, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
