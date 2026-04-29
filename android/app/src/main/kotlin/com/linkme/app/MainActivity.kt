package com.linkme.app

import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "link_me/device_info")
            .setMethodCallHandler { call, result ->
                if (call.method == "getDeviceName") {
                    result.success(resolveDeviceName())
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "link_me/file_system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "Missing file path", null)
                        } else {
                            MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                            result.success(null)
                        }
                    }
                    "openDirectory" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            result.success(openDirectory(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun resolveDeviceName(): String {
        val globalName = try {
            Settings.Global.getString(contentResolver, "device_name")
        } catch (_: Throwable) {
            null
        }
        if (!globalName.isNullOrBlank()) return globalName

        val secureBluetoothName = try {
            Settings.Secure.getString(contentResolver, "bluetooth_name")
        } catch (_: Throwable) {
            null
        }
        if (!secureBluetoothName.isNullOrBlank()) return secureBluetoothName

        val manufacturer = Build.MANUFACTURER.orEmpty().trim()
        val model = Build.MODEL.orEmpty().trim()
        if (model.isNotEmpty() && manufacturer.isNotEmpty() && !model.lowercase().contains(manufacturer.lowercase())) {
            return "$manufacturer $model"
        }
        return model.ifEmpty { "Android Phone" }
    }

    private fun openDirectory(path: String): Boolean {
        return try {
            val uri = Uri.parse(path)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "resource/folder")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.parse("content://com.android.externalstorage.documents/root/primary"), "resource/folder")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                true
            } catch (_: Throwable) {
                false
            }
        }
    }
}
