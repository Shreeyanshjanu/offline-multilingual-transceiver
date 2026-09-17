package com.sih.voicebridge.download

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import java.io.File

class NativeModelDownloadManager(context: Context) {
    data class DownloadStatus(
        val downloadId: Long, val status: String,
        val bytesDownloaded: Long, val totalBytes: Long,
        val progress: Double, val reason: Long?, val localUri: String?,
    )

    private val appContext = context.applicationContext
    private val downloadManager = appContext.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val preferences = appContext.getSharedPreferences("itantra_model_downloads", Context.MODE_PRIVATE)

    fun startDownload(languageCode: String, modelUrl: String, modelFileName: String): Long {
        val code = languageCode.trim().lowercase()
        require(code in setOf("en", "hi", "gu", "mr", "kn", "ml", "ta", "te", "bn", "or"))
        require(modelFileName == "stt-$code-model.int8.onnx")
        return start("model_$code", modelUrl, "stt_models/$code/$modelFileName", "Downloading $code model")
    }

    fun startTokenDownload(key: String, tokensUrl: String, tokensFileName: String): Long {
        val token = key.trim().lowercase()
        require(token == "en" || token == "indic")
        require(tokensFileName == "stt-$token-tokens.txt")
        return start("token_$token", tokensUrl, "stt_models/$tokensFileName", "Downloading language data")
    }

    private fun start(key: String, url: String, destination: String, description: String): Long {
        require(Uri.parse(url).scheme == "https") { "Model downloads require HTTPS" }
        val existingId = preferences.getLong(key, -1L)
        if (existingId != -1L) {
            val existing = query(existingId)
            if (existing?.status in setOf("pending", "running", "paused")) return existingId
            val existingUri = existing?.localUri?.let(Uri::parse)
            if (existing?.status == "successful" && existingUri?.scheme == "file") {
                val file = existingUri.path?.let(::File)
                if (file != null && file.exists() && file.length() > 0) return existingId
            }
            // Remove failed records and their partial destinations before retrying.
            cancel(key)
        }
        val directory = requireNotNull(appContext.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS))
        val file = File(directory, destination)
        if (file.exists()) check(file.delete()) { "Unable to remove stale download" }
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("iTantra speech model")
            .setDescription(description)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(appContext, Environment.DIRECTORY_DOWNLOADS, destination)
        val id = downloadManager.enqueue(request)
        if (!preferences.edit().putLong(key, id).commit()) {
            downloadManager.remove(id)
            error("Unable to save download ID")
        }
        return id
    }

    fun getStatus(languageCode: String): DownloadStatus? = savedStatus("model_${languageCode.trim().lowercase()}")
    fun getTokenStatus(key: String): DownloadStatus? = savedStatus("token_${key.trim().lowercase()}")
    fun cancelModelDownload(languageCode: String) = cancel("model_${languageCode.trim().lowercase()}")
    fun cancelTokenDownload(key: String) = cancel("token_${key.trim().lowercase()}")

    private fun savedStatus(key: String): DownloadStatus? {
        val id = preferences.getLong(key, -1L)
        return if (id == -1L) null else query(id)
    }

    private fun cancel(key: String) {
        val id = preferences.getLong(key, -1L)
        if (id != -1L) downloadManager.remove(id)
        check(preferences.edit().remove(key).commit()) { "Unable to clear download ID" }
    }

    private fun query(downloadId: Long): DownloadStatus? {
        downloadManager.query(DownloadManager.Query().setFilterById(downloadId)).use { cursor ->
            if (!cursor.moveToFirst()) return null
            val statusValue = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val reason = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            val uri = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
            val status = when (statusValue) {
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_RUNNING -> "running"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                DownloadManager.STATUS_FAILED -> "failed"
                else -> "unknown"
            }
            return DownloadStatus(downloadId, status, downloaded, total,
                if (total > 0) downloaded.toDouble() / total else 0.0, reason, uri)
        }
    }
}
