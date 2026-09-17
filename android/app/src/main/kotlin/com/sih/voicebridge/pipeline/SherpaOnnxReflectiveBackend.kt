package com.sih.voicebridge.pipeline

import android.content.Context
import java.lang.reflect.Constructor
import android.util.Log

private const val TAG = "SIH_STT"

class SherpaOnnxReflectiveBackend(
    private val context: Context,
    private val model: ResolvedSttModel,
    private val onStatus: (String) -> Unit,
) : StreamingSttBackend, ModelSizedSttBackend {
    override val backendName: String = "sherpa_reflective_${model.languageCode}"

    private val recognizerDelegate = lazy {
        val recognizerConfig = buildRecognizerConfig(model)
            ?: throw IllegalStateException("Unable to build Sherpa recognizer config")
        createRecognizer(recognizerConfig)
    }
    private val recognizer: Any get() = recognizerDelegate.value
    private val apiDelegate = lazy { OfflineRecognizerApi(recognizer) }
    private var released = false

    override fun prepare() {
        check(!released) { "Sherpa backend has been released" }
        apiDelegate.value
    }

    override fun createSession(languageCode: String): StreamingSttSession {
        if (languageCode.lowercase() != model.languageCode.lowercase()) {
            throw IllegalStateException(
                "Sherpa backend prepared for ${model.languageCode}, requested $languageCode",
            )
        }

        onStatus("Sherpa STT session started (${model.languageCode})")
        return SherpaOnnxReflectiveSession(apiDelegate.value)
    }

    override fun close() {
        if (!released && recognizerDelegate.isInitialized()) {
            released = true
            recognizer.javaClass.getMethod("release").invoke(recognizer)
        }
    }

    override fun modelSizeBytes(): Long? {
        val files = listOf(
            model.modelFile,
            model.tokensFile,
            model.encoderFile,
            model.decoderFile,
            model.joinerFile,
        )

        var bytes = 0L
        for (file in files) {
            if (file != null && file.exists()) {
                bytes += file.length()
            }
        }

        return if (bytes > 0L) bytes else null
    }

    private fun createRecognizer(recognizerConfig: Any): Any {
        Log.e(
            TAG,
            "Recognizer model is being loaded from filesystem"
        )

        Log.e(
            TAG,
            "Model: ${model.modelFile.absolutePath}"
        )

        Log.e(
            TAG,
            "Tokens: ${model.tokensFile?.absolutePath}"
        )
        val recognizerClass = Class.forName("com.k2fsa.sherpa.onnx.OfflineRecognizer")

        val constructors = recognizerClass.constructors.sortedBy { it.parameterCount }
        for (constructor in constructors) {
            val instance = tryConstructRecognizer(constructor, recognizerConfig)
            if (instance != null) {
                return instance
            }
        }

        val factoryCreated = invokeBestMatch(
            target = recognizerClass,
            methodNames = listOf("create", "fromConfig"),
            args = listOf(recognizerConfig),
            staticOnly = true,
        )
        if (factoryCreated != null) {
            return factoryCreated
        }

        throw IllegalStateException("No compatible OfflineRecognizer constructor found")
    }

    private fun tryConstructRecognizer(
        constructor: Constructor<*>,
        recognizerConfig: Any,
    ): Any? {

        val params = constructor.parameterTypes

        Log.e(
            "SIH_STT",
            "Trying constructor: $constructor"
        )

        Log.e(
            "SIH_STT",
            "Parameter count: ${params.size}"
        )

        val args = mutableListOf<Any?>()

        for (param in params) {

            Log.e(
                "SIH_STT",
                "Parameter type: ${param.name}"
            )

            when {

                // OfflineRecognizerConfig
                param.isAssignableFrom(
                    recognizerConfig.javaClass
                ) -> {

                    Log.e(
                        "SIH_STT",
                        " -> Using OfflineRecognizerConfig"
                    )

                    args.add(recognizerConfig)
                }

                // IMPORTANT:
                // Our models are loaded from absolute filesystem paths.
                // Therefore AssetManager MUST be null.
                param.name ==
                    "android.content.res.AssetManager" -> {

                    Log.e(
                        "SIH_STT",
                        " -> Using NULL AssetManager because model paths are absolute"
                    )

                    args.add(null)
                }

                // Android Context, if required by this constructor.
                param.isAssignableFrom(
                    Context::class.java
                ) -> {

                    Log.e(
                        "SIH_STT",
                        " -> Using Android Context"
                    )

                    args.add(context)
                }

                else -> {

                    Log.e(
                        "SIH_STT",
                        " -> ❌ Unsupported constructor parameter: ${param.name}"
                    )

                    return null
                }
            }
        }

        return try {

            constructor.isAccessible = true

            Log.e(
                "SIH_STT",
                "Invoking constructor..."
            )

            val instance =
                constructor.newInstance(
                    *args.toTypedArray()
                )

            Log.e(
                "SIH_STT",
                "✅ Constructor invocation succeeded"
            )

            instance

        } catch (error: Throwable) {

            Log.e(
                "SIH_STT",
                "❌ Constructor invocation FAILED",
                error
            )

            null
        }
    }

    private fun buildRecognizerConfig(model: ResolvedSttModel): Any? {
        val recognizerConfigClass = classOrNull("com.k2fsa.sherpa.onnx.OfflineRecognizerConfig")
            ?: return null
        val modelConfigClass = classOrNull("com.k2fsa.sherpa.onnx.OfflineModelConfig")
            ?: return null

        val recognizerConfig = instantiate(recognizerConfigClass) ?: return null
        val modelConfig = instantiate(modelConfigClass) ?: return null

        configureModelConfig(modelConfig, model)
        requireProperty(recognizerConfig, listOf("modelConfig", "offlineModelConfig"), modelConfig)
        requireProperty(recognizerConfig, listOf("decodingMethod"), "greedy_search")
        requireProperty(recognizerConfig, listOf("maxActivePaths"), 4)

        val featureConfig = classOrNull("com.k2fsa.sherpa.onnx.FeatureConfig")?.let { instantiate(it) }
            ?: error("Sherpa FeatureConfig is unavailable")
        requireProperty(featureConfig, listOf("sampleRate"), 16000f)
        requireProperty(featureConfig, listOf("featureDim", "numBins"), 80)
        requireProperty(recognizerConfig, listOf("featConfig", "featureConfig"), featureConfig)

        return recognizerConfig
    }

    private fun configureModelConfig(modelConfig: Any, model: ResolvedSttModel) {
        requireProperty(modelConfig, listOf("numThreads"), 2)
        requireProperty(modelConfig, listOf("provider"), "cpu")
        requireProperty(modelConfig, listOf("debug"), false)

        when (model.type.lowercase()) {
            "transducer" -> configureTransducerModel(modelConfig, model)
            else -> configureNemoCtcModel(modelConfig, model)
        }
    }

    private fun configureNemoCtcModel(
        modelConfig: Any,
        model: ResolvedSttModel
    ) {
        val nemoClass =
            classOrNull("com.k2fsa.sherpa.onnx.OfflineNemoEncDecCtcModelConfig")
                ?: error("Sherpa NeMo CTC configuration is unavailable")

        val nemoConfig = instantiate(nemoClass) ?: error("Cannot create Sherpa NeMo CTC configuration")

        // NeMo CTC model path
        requireProperty(
            nemoConfig,
            listOf("model"),
            model.modelFile.absolutePath
        )

        // IMPORTANT:
        // OfflineModelConfig uses "nemo", not "nemoCtc"
        requireProperty(
            modelConfig,
            listOf("nemo", "nemoCtc"),
            nemoConfig
        )

        // tokens.txt belongs directly to OfflineModelConfig
        val tokensFile = model.tokensFile ?: error("NeMo CTC tokens are missing")
        requireProperty(modelConfig, listOf("tokens", "tokensPath"), tokensFile.absolutePath)

        // Tell Sherpa explicitly that this is a NeMo CTC model.
        requireProperty(
            modelConfig,
            listOf("modelType"),
            "nemo_ctc"
        )
    }

    private fun configureTransducerModel(modelConfig: Any, model: ResolvedSttModel) {
        val transducerClass = classOrNull("com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig")
            ?: return

        val transducer = instantiate(transducerClass) ?: return
        setProperty(transducer, listOf("encoder", "encoderPath"), model.encoderFile?.absolutePath)
        setProperty(transducer, listOf("decoder", "decoderPath"), model.decoderFile?.absolutePath)
        setProperty(transducer, listOf("joiner", "joinerPath"), model.joinerFile?.absolutePath)

        if (model.tokensFile != null) {
            setProperty(transducer, listOf("tokens", "tokensPath"), model.tokensFile.absolutePath)
            setProperty(modelConfig, listOf("tokens", "tokensPath"), model.tokensFile.absolutePath)
        }

        setProperty(modelConfig, listOf("transducer"), transducer)
    }
}
