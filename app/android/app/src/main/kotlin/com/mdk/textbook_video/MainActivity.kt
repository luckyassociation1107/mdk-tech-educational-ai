package com.mdk.textbook_video

import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Bridge: Flutter UI <-> on-device Python engine (Chaquopy) <-> Android TTS.
 *
 * - Python renders the video ON THIS DEVICE (no rendering server).
 * - Android TextToSpeech is the on-device narration engine; that is where
 *   a Telugu (te-IN) voice is used when the device has one installed.
 * - The "brain" is our Playwright automation website. On a phone it is
 *   reached over HTTPS exactly like the desktop prototype; document
 *   content therefore goes to that external website — the app says so
 *   in the UI and never claims this step is local.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.mdk.textbook_video/engine"
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!Python.isStarted()) Python.start(AndroidPlatform(this))
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
                    "createSession", "generateVideo", "askChat", "sessionVideos", "chapterSeries", "completePart", "disconnect", "listSessions" -> {
                        val args = JSONObject()
                        call.arguments?.let { if (it is Map<*, *>) it.forEach { (k, v) -> args.put(k.toString(), v) } }
                        io.execute {
                            try {
                                if (call.method == "createSession") {
                                    // Android has no PyMuPDF: render page pictures with
                                    // PdfRenderer so the Python engine (pypdf for text)
                                    // can still show/highlight real pages.
                                    try {
                                        val pdfPath = call.argument<String>("pdfPath")
                                        if (pdfPath != null) {
                                            val dir = java.io.File(filesDir, "textbook_video_data/page_png/" +
                                                Integer.toHexString(pdfPath.hashCode()).replace("-", "x"))
                                            dir.mkdirs()
                                            renderPdfPages(java.io.File(pdfPath), dir)
                                            args.put("pagePngDir", dir.absolutePath)
                                        }
                                    } catch (e: Exception) {
                                        // Text-only indexing still works; the engine
                                        // reports a clear message if a page picture
                                        // is ever requested but missing.
                                    }
                                }
                                val py = Python.getInstance().getModule("android_bridge")
                                val out = py.callAttr("handle", call.method, args.toString(), filesDir.absolutePath).toString()
                                val parsed: Any = when {
                                    out.trimStart().startsWith("[") -> {
                                        val arr = JSONArray(out); (0 until arr.length()).map { arr.getJSONObject(it).toMap() }
                                    }
                                    else -> JSONObject(out).toMap()
                                }
                                main.post { result.success(parsed) }
                            } catch (e: Exception) {
                                main.post { result.error("engine_error", e.message, null) }
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

private fun renderPdfPages(pdf: java.io.File, outDir: java.io.File) {
    val pfd = android.os.ParcelFileDescriptor.open(pdf, android.os.ParcelFileDescriptor.MODE_READ_ONLY)
    val renderer = android.graphics.pdf.PdfRenderer(pfd)
    try {
        for (i in 0 until renderer.pageCount) {
            val page = renderer.openPage(i)
            try {
                val scale = 2
                val bmp = android.graphics.Bitmap.createBitmap(
                    page.width * scale, page.height * scale, android.graphics.Bitmap.Config.ARGB_8888)
                bmp.eraseColor(android.graphics.Color.WHITE)
                page.render(bmp, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                java.io.FileOutputStream(java.io.File(outDir, "page_${i + 1}.png")).use {
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

private fun JSONObject.toMap(): Map<String, Any?> {
    val m = mutableMapOf<String, Any?>()
    keys().forEach { k ->
        val v = get(k)
        m[k] = when (v) {
            is JSONObject -> v.toMap()
            is JSONArray -> (0 until v.length()).map { v.get(it) }
            JSONObject.NULL -> null
            else -> v
        }
    }
    return m
}
