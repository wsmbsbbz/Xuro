package com.xuro.tts

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.UUID

class TtsSynthesisPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private var tts: TextToSpeech? = null
    private var initializing = false
    private val pending = mutableListOf<(TextToSpeech?) -> Unit>()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "synthesizeToFile" -> synthesizeToFile(call, result)
            else -> result.notImplemented()
        }
    }

    private fun synthesizeToFile(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")?.trim().orEmpty()
        val outputPath = call.argument<String>("outputPath").orEmpty()
        val localeTag = call.argument<String>("locale") ?: "zh-CN"
        val speechRate = (call.argument<Double>("speechRate") ?: 1.0).toFloat()

        if (text.isEmpty() || outputPath.isEmpty()) {
            result.error("invalid_args", "text and outputPath are required", null)
            return
        }

        ensureTts { engine ->
            if (engine == null) {
                result.error("tts_unavailable", "Android TextToSpeech is unavailable", null)
                return@ensureTts
            }

            val file = File(outputPath)
            file.parentFile?.mkdirs()
            if (file.exists()) file.delete()

            val utteranceId = UUID.randomUUID().toString()
            engine.language = Locale.forLanguageTag(localeTag)
            engine.setSpeechRate(speechRate.coerceIn(0.5f, 2.0f))
            var completed = false
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(doneUtteranceId: String?) {
                    if (doneUtteranceId == utteranceId && !completed) {
                        completed = true
                        mainHandler.post {
                            if (file.exists() && file.length() > 0L) {
                                result.success(mapOf("bytes" to file.length()))
                            } else {
                                result.error("tts_empty_file", "TTS produced an empty file", null)
                            }
                        }
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(errorUtteranceId: String?) {
                    if (errorUtteranceId == utteranceId && !completed) {
                        completed = true
                        mainHandler.post {
                            result.error("tts_error", "TTS synthesis failed", null)
                        }
                    }
                }

                override fun onError(errorUtteranceId: String?, errorCode: Int) {
                    if (errorUtteranceId == utteranceId && !completed) {
                        completed = true
                        mainHandler.post {
                            result.error("tts_error", "TTS synthesis failed: $errorCode", null)
                        }
                    }
                }
            })

            val params = Bundle()
            val code = engine.synthesizeToFile(text, params, file, utteranceId)
            if (code != TextToSpeech.SUCCESS && !completed) {
                completed = true
                result.error("tts_error", "Failed to start TTS synthesis", null)
            }
        }
    }

    private fun ensureTts(callback: (TextToSpeech?) -> Unit) {
        tts?.let {
            callback(it)
            return
        }
        pending.add(callback)
        if (initializing) return
        initializing = true
        tts = TextToSpeech(context.applicationContext) { status ->
            initializing = false
            val engine = if (status == TextToSpeech.SUCCESS) tts else null
            val callbacks = pending.toList()
            pending.clear()
            callbacks.forEach { it(engine) }
        }
    }
}
