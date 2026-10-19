package com.mdk.textbook_video

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.Executors

/**
 * The app is 100% Flutter/Dart. This tiny native side only does the two
 * things Dart cannot do itself:
 *  - render textbook pages to PNGs (android.graphics.pdf.PdfRenderer)
 *  - check whether a device TTS voice exists for a language (flutter_tts
 *    then speaks with that same Android voice).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.mdk.textbook_video/engine"
    private val io = Executors.newSingleThreadExecutor()
    private var tts: TextToSpeech? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tts = TextToSpeech(this) { /* readiness is reported per checkTts call */ }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
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
                    "renderPages" -> {
                        val pdfPath = call.argument<String>("pdfPath")
                        if (pdfPath == null) {
                            result.error("no_pdf", "pdfPath missing", null)
                        } else {
                            io.execute {
                                try {
                                    val dir = File(filesDir, "classroom_pages/" +
                                        Integer.toHexString(pdfPath.hashCode()).replace("-", "x"))
                                    dir.mkdirs()
                                    renderPdfPages(File(pdfPath), dir)
                                    runOnUiThread { result.success(dir.absolutePath) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("render_failed", e.message, null) }
                                }
                            }
                        }
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

private fun renderPdfPages(pdf: File, outDir: File) {
    val pfd = android.os.ParcelFileDescriptor.open(pdf, android.os.ParcelFileDescriptor.MODE_READ_ONLY)
    val renderer = android.graphics.pdf.PdfRenderer(pfd)
    try {
        for (i in 0 until renderer.pageCount) {
            val out = File(outDir, "page_${i + 1}.png")
            if (out.exists() && out.length() > 0) continue
            val page = renderer.openPage(i)
            try {
                val scale = 2
                val bmp = android.graphics.Bitmap.createBitmap(
                    page.width * scale, page.height * scale, android.graphics.Bitmap.Config.ARGB_8888)
                bmp.eraseColor(android.graphics.Color.WHITE)
                page.render(bmp, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                FileOutputStream(out).use {
                    bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, it)
                }
                bmp.recycle()
            } finally {
                page.close()
            }
        }
    } finally {
        renderer.close()
        pfd.close()
    }
}
