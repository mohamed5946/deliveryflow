package com.valor.deliveryflow

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Captures geo: VIEW intents (e.g. navigation shared from the Amazon
/// Flex driver app) on cold start AND while already running
/// (singleTop -> onNewIntent), then hands the raw URI string to Dart
/// through a MethodChannel. Each URI is delivered exactly once.
class MainActivity : FlutterActivity() {
    private var pendingNavUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingNavUri = intent?.dataString?.takeIf { it.startsWith("geo:") }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingNavUri = intent.dataString?.takeIf { it.startsWith("geo:") }
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
    }
}
