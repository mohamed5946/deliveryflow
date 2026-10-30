package com.valor.deliveryflow

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Captures shared-location intents on cold start AND while already
/// running (singleTop -> onNewIntent), then hands the raw payload to
/// Dart through a MethodChannel. Each payload is delivered exactly
/// once (the native side consumes it on read).
///
/// v24: beyond `geo:` VIEW intents (e.g. navigation shared from the
/// Amazon Flex driver app), this also captures https Google Maps
/// VIEW intents and ACTION_SEND share-sheet text (Google Maps links
/// shared as text). Dart decides what is usable.
class MainActivity : FlutterFragmentActivity() {
    private var pendingNavUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingNavUri = extractShareable(intent)
        preferHighestRefreshRate()
    }

    /// v27.4: ask the display for its fastest mode. Flutter renders at
    /// the display's active refresh rate, but without an app-side
    /// preference many devices keep apps at 60 Hz even on 120 Hz
    /// panels, which reads as lag when scrolling. Pick the supported
    /// mode with the highest refresh rate at (or below) the current
    /// resolution and set it as the window's preferred mode + rate.
    /// On 60 Hz-only hardware the best mode IS 60 Hz, so behavior is
    /// unchanged there. Guarded: a display quirk must never crash
    /// startup.
    private fun preferHighestRefreshRate() {
        try {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return
            val modes = display.supportedModes ?: return
            if (modes.isEmpty()) return
            val current = display.mode
            val best = modes
                .filter { it.physicalWidth <= current.physicalWidth &&
                    it.physicalHeight <= current.physicalHeight }
                .maxByOrNull { it.refreshRate }
                ?: modes.maxByOrNull { it.refreshRate }
                ?: return
            val attrs: WindowManager.LayoutParams = window.attributes
            attrs.preferredDisplayModeId = best.modeId
            attrs.preferredRefreshRate = best.refreshRate
            window.attributes = attrs
        } catch (_: Exception) {
            // Best effort only — default refresh behavior stays.
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingNavUri = extractShareable(intent)
    }

    private fun extractShareable(intent: Intent?): String? {
        if (intent == null) return null
        // Share sheet: ACTION_SEND with text (e.g. a Google Maps link
        // shared as text from Google Maps / the Flex app).
        if (intent.action == Intent.ACTION_SEND) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrBlank()) return text
        }
        // VIEW intents: geo: URIs and https map links.
        val data = intent.dataString
        if (data != null) {
            if (data.startsWith("geo:")) return data
            if (data.startsWith("https://")) {
                val lower = data.lowercase()
                if ((lower.contains("google.") && lower.contains("/maps")) ||
                    lower.contains("maps.google.") ||
                    lower.contains("goo.gl/maps") ||
                    lower.contains("maps.app.goo.gl")
                ) {
                    return data
                }
            }
        }
        return null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.valor.deliveryflow/nav_intent",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getNavUri") {
                val uri = pendingNavUri
                pendingNavUri = null
                result.success(uri)
            } else {
                result.notImplemented()
            }
        }
        // v27.37: in-app self-update (sideloaded, no Play). Dart
        // downloads + SHA-256-verifies the APK first; this channel
        // only (a) reports whether this app may install unknown
        // apps, (b) opens the per-app setting when it may not, and
        // (c) hands the VERIFIED file to Android's system install
        // prompt via FileProvider. Android itself asks the user to
        // confirm with one tap — there is no silent install, and
        // this channel never installs anything on its own.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.valor.deliveryflow/app_update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallUnknownApps" -> {
                    val allowed = if (Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(allowed)
                }
                "openUnknownAppsSettings" -> {
                    try {
                        val intent =
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        startActivity(intent)
                    } catch (_: Exception) {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (_: Exception) {
                        }
                    }
                    result.success(null)
                }
                "installApk" -> {
                    try {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("NO_PATH", "No APK path given", null)
                        } else {
                            val apkFile = java.io.File(path)
                            val uri = androidx.core.content.FileProvider
                                .getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    apkFile,
                                )
                            val intent =
                                Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(
                                        uri,
                                        "application/vnd.android.package-archive",
                                    )
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                            startActivity(intent)
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // v27: battery-optimization exemption. Aggressive OEM battery
        // managers (e.g. Infinix XOS) defer/kill scheduled reminder
        // alarms for non-exempt apps; Dart queries the state and offers
        // the system exemption dialog from notification settings.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.valor.deliveryflow/battery",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoring" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestIgnore" -> {
                    try {
                        val intent =
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        startActivity(intent)
                    } catch (e: Exception) {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (_: Exception) {
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
