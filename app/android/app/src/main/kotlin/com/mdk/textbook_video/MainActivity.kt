package com.mdk.textbook_video

import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.Executors

/**
 * The app is 100% Flutter/Dart. This tiny native side exists for one thing
 * only: speaking with the *device* voice and reporting the spoken-word
 * ranges, so the lesson player can highlight exactly the word being said.
 *
 * Page rendering moved to Dart in v0.24.0 (pdfx/PDFium), which means the
 * same code path renders pages on Android and Windows.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.mdk.textbook_video/engine"
    private val io = Executors.newSingleThreadExecutor()
    private var tts: TextToSpeech? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tts = TextToSpeech(this) { /* readiness is reported per checkTts call */ }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            // Real spoken-word ranges: the Flutter player reveals text and
            // moves the page highlighter from THESE offsets, so writing,
            // highlighting and voice can never drift apart.
            override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                runOnUiThread { channel?.invokeMethod("ttsRange", mapOf("start" to start, "end" to end)) }
            }
            override fun onDone(utteranceId: String?) {
                runOnUiThread { channel?.invokeMethod("ttsDone", null) }
            }
            @Deprecated("deprecated in API level 21")
            override fun onError(utteranceId: String?) {
                runOnUiThread { channel?.invokeMethod("ttsError", null) }
            }
            override fun onError(utteranceId: String?, errorCode: Int) {
                runOnUiThread { channel?.invokeMethod("ttsError", null) }
            }
        })

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkTts" -> {
                        val lang = call.argument<String>("language") ?: "en-IN"
                        val parts = lang.split("-")
                        val locale = if (parts.size > 1) Locale(parts[0], parts[1]) else Locale(parts[0])
                        val avail = try {
                            tts?.isLanguageAvailable(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
                        } catch (e: Exception) { TextToSpeech.LANG_NOT_SUPPORTED }
                        val ok = avail == TextToSpeech.LANG_AVAILABLE || avail == TextToSpeech.LANG_COUNTRY_AVAILABLE || avail == TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE
                        result.success(mapOf("available" to ok, "code" to avail))
                    }
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        val lang = call.argument<String>("language") ?: "en-IN"
                        val rate = call.argument<Double>("rate") ?: 0.9
                        val pitch = call.argument<Double>("pitch") ?: 1.0
                        val voiceName = call.argument<String>("voice") ?: ""
                        val parts = lang.split("-")
                        val locale = if (parts.size > 1) Locale(parts[0], parts[1]) else Locale(parts[0])
                        try {
                            tts?.language = locale
                            if (voiceName.isNotEmpty()) {
                                val v = tts?.voices?.firstOrNull { it.name == voiceName }
                                if (v != null) tts?.voice = v
                            }
                            tts?.setSpeechRate(rate.toFloat())
                            tts?.setPitch(pitch.toFloat())
                            val params = android.os.Bundle()
                            params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "scene")
                            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, "scene")
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("tts_failed", e.message, null)
                        }
                    }
                    "listVoices" -> {
                        val lang = call.argument<String>("language") ?: "en-IN"
                        val out = ArrayList<Map<String, Any>>()
                        try {
                            val all = tts?.voices ?: emptySet()
                            for (v in all) {
                                val loc = v.locale
                                val tag = if (loc.country.isNullOrEmpty()) loc.language else loc.language + "-" + loc.country
                                val base = lang.split("-").firstOrNull() ?: "en"
                                if (tag.equals(lang, true) || tag.equals(localizedTag(lang), true) ||
                                    loc.language.equals(base, true)) {
                                    out.add(mapOf(
                                        "name" to v.name,
                                        "locale" to tag,
                                        "quality" to v.quality,
                                        "latency" to v.latency,
                                        "network" to v.isNetworkConnectionRequired,
                                        "notInstalled" to v.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
                                    ))
                                }
                            }
                        } catch (e: Exception) { /* empty list */ }
                        out.sortByDescending { (it["quality"] as Int) }
                        result.success(out)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        try {
                            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "stopTts" -> {
                        try { tts?.stop() } catch (e: Exception) { /* ignore */ }
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        tts?.shutdown()
        super.onDestroy()
    }
}

private fun localizedTag(lang: String): String {
    if (!lang.contains("-")) return lang
    return try {
        android.icu.util.ULocale.forLanguageTag(lang).toLanguageTag()
    } catch (e: Exception) {
        lang
    }
}
