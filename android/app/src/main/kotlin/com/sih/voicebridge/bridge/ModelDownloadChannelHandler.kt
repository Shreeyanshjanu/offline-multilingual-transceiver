package com.sih.voicebridge.bridge

import com.sih.voicebridge.download.NativeModelDownloadManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Download channel calls stay independent of voice pipeline initialization. */
internal class ModelDownloadChannelHandler(
    private val modelDownloadManager: NativeModelDownloadManager,
) {
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "startModelDownload" -> {

                val languageCode =
                    call.argument<String>("languageCode")
                        ?: throw IllegalArgumentException(
                            "languageCode is required",
                        )

                val modelUrl =
                    call.argument<String>("modelUrl")
                        ?: throw IllegalArgumentException(
                            "modelUrl is required",
                        )

                val modelFileName =
                    call.argument<String>("modelFileName")
                        ?: throw IllegalArgumentException(
                            "modelFileName is required",
                        )

                val downloadId =
                    modelDownloadManager.startDownload(
                        languageCode = languageCode,
                        modelUrl = modelUrl,
                        modelFileName = modelFileName,
                    )

                result.success(downloadId)
            }

            "getModelDownloadStatus" -> {

                val languageCode =
                    call.argument<String>("languageCode")
                        ?: throw IllegalArgumentException(
                            "languageCode is required",
                        )

                val status =
                    modelDownloadManager.getStatus(
                        languageCode,
                    )

                if (status == null) {
                    result.success(null)
                    return true
                }

                result.success(
                    mapOf(
                        "languageCode" to languageCode,
                        "downloadId" to status.downloadId,
                        "status" to status.status,
                        "bytesDownloaded" to
                            status.bytesDownloaded,
                        "totalBytes" to
                            status.totalBytes,
                        "progress" to
                            status.progress,
                        "reason" to
                            status.reason,
                        "localUri" to
                            status.localUri,
                    ),
                )
            }

            "cancelModelDownload" -> {

                val languageCode =
                    call.argument<String>("languageCode")
                        ?: throw IllegalArgumentException(
                            "languageCode is required",
                        )

                modelDownloadManager.cancelModelDownload(
                    languageCode,
                )

                result.success(null)
            }

            /*
             * ---------------------------------------------------------
             * Token downloads
             * ---------------------------------------------------------
             */

            "startTokenDownload" -> {

                val key =
                    call.argument<String>("key")
                        ?: throw IllegalArgumentException(
                            "key is required",
                        )

                val tokensUrl =
                    call.argument<String>("tokensUrl")
                        ?: throw IllegalArgumentException(
                            "tokensUrl is required",
                        )

                val tokensFileName =
                    call.argument<String>("tokensFileName")
                        ?: throw IllegalArgumentException(
                            "tokensFileName is required",
                        )

                val downloadId =
                    modelDownloadManager.startTokenDownload(
                        key = key,
                        tokensUrl = tokensUrl,
                        tokensFileName = tokensFileName,
                    )

                result.success(downloadId)
            }

            "getTokenDownloadStatus" -> {

                val key =
                    call.argument<String>("key")
                        ?: throw IllegalArgumentException(
                            "key is required",
                        )

                val status =
                    modelDownloadManager.getTokenStatus(key)

                if (status == null) {
                    result.success(null)
                    return true
                }

                result.success(
                    mapOf(
                        "key" to key,
                        "downloadId" to status.downloadId,
                        "status" to status.status,
                        "bytesDownloaded" to
                            status.bytesDownloaded,
                        "totalBytes" to
                            status.totalBytes,
                        "progress" to
                            status.progress,
                        "reason" to
                            status.reason,
                        "localUri" to
                            status.localUri,
                    ),
                )
            }

            "cancelTokenDownload" -> {
                val key = call.argument<String>("key")
                    ?: throw IllegalArgumentException("key is required")
                modelDownloadManager.cancelTokenDownload(key)
                result.success(null)
            }

            else -> return false
        }
        return true
    }
}
