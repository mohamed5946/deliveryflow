package com.valor.deliveryflow

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
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
class MainActivity : FlutterActivity() {
    private var pendingNavUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingNavUri = extractShareable(intent)
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
