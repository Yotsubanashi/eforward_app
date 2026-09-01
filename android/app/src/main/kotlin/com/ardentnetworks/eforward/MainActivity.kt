package com.ardentnetworks.eforward

import android.content.pm.PackageManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    // Mirrors the iOS privacy cover (see ios/Runner/AppDelegate.swift). On
    // Android the reliable way to keep session content out of the recents/app-
    // switcher preview is FLAG_SECURE — the system renders a blank thumbnail
    // instead of a snapshot, so there is no content to leak on reopen. Flutter
    // tells us when the flag is warranted (active session + unlock enabled)
    // through the shared "eforward/privacy" channel.
    private val privacyChannelName = "eforward/privacy"

    // Lets Dart detect a leftover install under the app's previous
    // applicationId (com.example.eforward_app, renamed to
    // com.ardentnetworks.eforward). A package rename can never upgrade in place,
    // so the old app lingers as a second icon until the user removes it.
    private val legacyChannelName = "eforward/legacy"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            legacyChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPackageInstalled" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        result.success(isPackageInstalled(pkg))
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            privacyChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val secure = call.arguments as? Boolean ?: false
                    // Window flags must be touched on the UI thread.
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                }
                // No-op on Android: FLAG_SECURE is a window flag, not a view
                // overlay, so there is nothing to take down on resume. Answered
                // (rather than "not implemented") so the shared Dart call is clean.
                "hideCover" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }

    private fun isPackageInstalled(pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }
}
