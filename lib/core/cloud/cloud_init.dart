// v27.33 — Cloud backend bootstrap (REAL project wired).
//
// Mohamed provided the project's google-services.json (copied to
// android/app/google-services.json) and the generated options live in
// lib/firebase_options.dart. This function initializes Firebase with
// those options and returns the real backend. If initialization fails
// for any reason, it falls back to [NotConfiguredBackend] so startup
// never breaks — the app stays local-only and the Profile cloud
// screens show the not-configured state.
import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';
import 'cloud_backend.dart';
import 'firebase_cloud_backend.dart';

Future<CloudBackend> initCloudBackend() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.android,
    );
    return FirebaseCloudBackend();
  } catch (_) {
    // A failed init must never break startup: local-only wins.
    return NotConfiguredBackend();
  }
}

/// True only when [initCloudBackend] returned a real backend.
bool cloudBackendIsConfigured(CloudBackend backend) =>
    backend is FirebaseCloudBackend;
