package com.sih.voicebridge.pipeline

internal class PiperSherpaTtsBackend(
    private val modelResolver: TtsModelResolver,
    private val emitEvent: (Map<String, Any?>) -> Unit,
    private val emitStatus: (String) -> Unit,
    private val emitError: (String?, String) -> Unit,
) : TtsBackend {
    override val backendName: String = "piper_sherpa"

    private var probeDone = false
    private var available = false
    private var warnedUnavailable = false

    override fun speak(request: PendingTtsRequest): Boolean {
        if (!isAvailable()) {
            if (!warnedUnavailable) {
                emitStatus("Piper/Sherpa TTS classes unavailable. Falling back to Android TTS.")
                warnedUnavailable = true
            }
            return false
        }

        val model = modelResolver.resolve(request.languageCode)
        if (model == null || model.backend.lowercase() != backendName) {
            return false
        }

        val modelFile = model.modelFile
        if (modelFile == null || !modelFile.exists()) {
            emitStatus("Piper model missing for ${request.languageCode}. Falling back to Android TTS.")
            return false
        }

        val success = synthesizeWithReflection(request, model)
        if (!success) {
            emitStatus("Piper reflective synthesis unavailable for current Sherpa API. Falling back.")
            return false
        }

        return true
    }

    override fun shutdown() {
    }

    private fun isAvailable(): Boolean {
        if (probeDone) {
            return available
        }

        probeDone = true
        available = try {
            Class.forName("com.k2fsa.sherpa.onnx.OfflineTts")
            true
        } catch (_: Throwable) {
            false
        }
        return available
    }

    private fun synthesizeWithReflection(request: PendingTtsRequest, model: ResolvedTtsModel): Boolean {
        return try {
            val offlineTtsClass = Class.forName("com.k2fsa.sherpa.onnx.OfflineTts")
            val methods = offlineTtsClass.methods + offlineTtsClass.declaredMethods

            val factoryMethod = methods.firstOrNull { method ->
                method.name.equals("create", ignoreCase = true) &&
                    method.parameterTypes.any { type -> type == String::class.java }
            }

            if (factoryMethod == null) {
                return false
            }

            val args = factoryMethod.parameterTypes.map { type ->
                when {
                    type == String::class.java -> model.modelFile?.absolutePath ?: ""
                    type == Boolean::class.javaPrimitiveType || type == Boolean::class.java -> false
                    type == Int::class.javaPrimitiveType || type == Int::class.java -> 0
                    type == Float::class.javaPrimitiveType || type == Float::class.java -> 1.0f
                    else -> null
                }
            }.toTypedArray()

            factoryMethod.isAccessible = true
            val offlineTts = factoryMethod.invoke(null, *args) ?: return false

            val synthesizeMethod = (offlineTts.javaClass.methods + offlineTts.javaClass.declaredMethods)
                .firstOrNull { method ->
                    method.name.contains("synth", ignoreCase = true) && method.parameterTypes.isNotEmpty()
                } ?: return false

            val synthArgs = synthesizeMethod.parameterTypes.mapIndexed { index, type ->
                when {
                    index == 0 && type == String::class.java -> request.text
                    type == Int::class.javaPrimitiveType || type == Int::class.java -> 0
                    type == Float::class.javaPrimitiveType || type == Float::class.java -> 1.0f
                    type == Boolean::class.javaPrimitiveType || type == Boolean::class.java -> false
                    else -> null
                }
            }.toTypedArray()

            synthesizeMethod.isAccessible = true
            synthesizeMethod.invoke(offlineTts, *synthArgs)

            emitEvent(
                mapOf(
                    "type" to "tts_started",
                    "text" to request.text,
                    "languageCode" to request.languageCode,
                    "messageId" to request.messageId,
                    "emergency" to request.emergency,
                    "backend" to backendName,
                ),
            )

            emitEvent(
                mapOf(
                    "type" to "audio_started",
                    "text" to request.text,
                    "messageId" to request.messageId,
                    "emergency" to request.emergency,
                    "backend" to backendName,
                ),
            )

            invokeOptional(offlineTts, "close")
            invokeOptional(offlineTts, "release")

            request.onPlaybackFinished?.invoke()
            true
        } catch (error: Throwable) {
            emitError(request.messageId, "Piper reflective synthesis failed: ${error.message}")
            false
        }
    }

    private fun invokeOptional(target: Any, methodName: String) {
        val method = (target.javaClass.methods + target.javaClass.declaredMethods).firstOrNull {
            it.name.equals(methodName, ignoreCase = true) && it.parameterTypes.isEmpty()
        } ?: return

        try {
            method.isAccessible = true
            method.invoke(target)
        } catch (_: Throwable) {
        }
    }
}
