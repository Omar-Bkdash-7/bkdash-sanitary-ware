package com.bkdash.sanitary

import android.content.ContentUris
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth (fingerprint) requires a FragmentActivity, not a plain FlutterActivity.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "bkdash/public_backup"
    private val folderName = "Bkdash_Backups"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(supported())
                    "save" -> {
                        val name = call.argument<String>("name")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (name == null || bytes == null) {
                            result.error("bad_arguments", "name and bytes are required", null)
                        } else {
                            save(name, bytes, result)
                        }
                    }
                    "list" -> list(result)
                    "delete" -> {
                        val id = call.argument<String>("id")
                        if (id == null) {
                            result.error("bad_arguments", "id is required", null)
                        } else {
                            delete(id, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** MediaStore downloads exist from Android 10 (API 29). */
    private fun supported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    private fun relativePath(): String =
        "${Environment.DIRECTORY_DOWNLOADS}/$folderName"

    private fun collection() = MediaStore.Downloads.getContentUri(
        MediaStore.VOLUME_EXTERNAL_PRIMARY
    )

    /**
     * Writes one copy into Downloads/BKDash_Backups. No storage permission is
     * needed, and the file stays after the app is uninstalled.
     */
    private fun save(name: String, bytes: ByteArray, result: MethodChannel.Result) {
        if (!supported()) {
            result.error("unsupported", "MediaStore needs Android 10 or newer", null)
            return
        }
        try {
            val pending = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/vnd.sqlite3")
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath())
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(collection(), pending)
                ?: throw IllegalStateException("MediaStore refused the file")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Cannot open the new file")
            val visible = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            contentResolver.update(uri, visible, null, null)
            result.success(ContentUris.parseId(uri).toString())
        } catch (error: Exception) {
            result.error("save_failed", error.message, null)
        }
    }

    /** The copies in the folder, newest first. */
    private fun list(result: MethodChannel.Result) {
        if (!supported()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        try {
            val projection = arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.DATE_ADDED,
            )
            val rows = mutableListOf<Map<String, Any>>()
            contentResolver.query(
                collection(),
                projection,
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                arrayOf("${relativePath()}%"),
                "${MediaStore.MediaColumns.DATE_ADDED} DESC, " +
                    "${MediaStore.MediaColumns._ID} DESC",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    rows.add(
                        mapOf(
                            "id" to cursor.getLong(0).toString(),
                            "name" to (cursor.getString(1) ?: ""),
                            "savedAt" to cursor.getLong(2) * 1000L,
                        )
                    )
                }
            }
            result.success(rows)
        } catch (error: Exception) {
            result.error("list_failed", error.message, null)
        }
    }

    private fun delete(id: String, result: MethodChannel.Result) {
        if (!supported()) {
            result.success(false)
            return
        }
        try {
            val numericId = id.toLongOrNull()
                ?: throw IllegalArgumentException("id must be a number")
            val uri = ContentUris.withAppendedId(collection(), numericId)
            result.success(contentResolver.delete(uri, null, null) > 0)
        } catch (error: Exception) {
            result.error("delete_failed", error.message, null)
        }
    }
}
