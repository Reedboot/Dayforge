package com.dayforge.dayforge

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportContents: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dayforge/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDataDirectory" -> result.success(filesDir.absolutePath)
                    "exportBackup" -> {
                        val contents = call.arguments as? String
                        if (contents == null) {
                            result.error("invalid_backup", "Backup contents are missing.", null)
                        } else if (pendingExportResult != null) {
                            result.error(
                                "export_in_progress",
                                "A backup export is already in progress.",
                                null
                            )
                        } else {
                            pendingExportResult = result
                            pendingExportContents = contents
                            try {
                                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/json"
                                    putExtra(Intent.EXTRA_TITLE, "dayforge.json")
                                }
                                startActivityForResult(intent, BACKUP_EXPORT_REQUEST_CODE)
                            } catch (error: Exception) {
                                pendingExportResult = null
                                pendingExportContents = null
                                result.error("backup_export_failed", error.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != BACKUP_EXPORT_REQUEST_CODE) return

        val result = pendingExportResult ?: return
        val contents = pendingExportContents
        pendingExportResult = null
        pendingExportContents = null
        if (resultCode != RESULT_OK || data?.data == null) {
            result.success(false)
            return
        }
        if (contents == null) {
            result.error("invalid_backup", "Backup contents are missing.", null)
            return
        }

        try {
            val output = contentResolver.openOutputStream(data.data!!)
                ?: throw IllegalStateException("Could not open the selected backup destination.")
            output.use { it.write(contents.toByteArray(Charsets.UTF_8)) }
            result.success(true)
        } catch (error: Exception) {
            result.error("backup_export_failed", error.message, null)
        }
    }

    companion object {
        private const val BACKUP_EXPORT_REQUEST_CODE = 1001
    }
}
