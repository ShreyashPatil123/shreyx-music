package com.shreyx.player

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.os.PowerManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo

/**
 * MainActivity integrating AudioServiceActivity with on-device NewPipe Extractor.
 *
 * Directly ported from NØTE's NoteNativeModule.
 */
class MainActivity : AudioServiceActivity() {

    private companion object {
        val initLock = Any()
        @Volatile
        var initialized = false
    }

    private val scope = CoroutineScope(Dispatchers.Main)
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shreyx.player/native_stream")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "resolveYouTubeStream" -> {
                        val videoId = call.argument<String>("videoId") ?: ""
                        scope.launch {
                            val response = withContext(Dispatchers.IO) {
                                resolve(videoId)
                            }
                            result.success(response)
                        }
                    }
                    "minimizeApp" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    "acquireVibeWakeLock" -> {
                        try {
                            if (wakeLock == null || wakeLock?.isHeld != true) {
                                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                                wakeLock = pm.newWakeLock(
                                    PowerManager.PARTIAL_WAKE_LOCK,
                                    "ShreyXVibe::Room"
                                )
                                wakeLock?.acquire(4 * 60 * 60 * 1000L) // 4-hour max timeout
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "releaseVibeWakeLock" -> {
                        try {
                            if (wakeLock?.isHeld == true) {
                                wakeLock?.release()
                            }
                            wakeLock = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensureInitialized() {
        if (initialized) return
        synchronized(initLock) {
            if (initialized) return
            NewPipe.init(
                NoteNativeDownloader(),
                Localization("en", "US"),
                ContentCountry("US")
            )
            initialized = true
        }
    }

    private fun resolve(videoId: String): Map<String, Any?> {
        if (videoId.isBlank()) {
            return mapOf(
                "ok" to false,
                "reason" to "invalid_id",
                "message" to "No video id supplied"
            )
        }

        return try {
            ensureInitialized()
            val url = "https://www.youtube.com/watch?v=$videoId"
            val info = StreamInfo.getInfo(ServiceList.YouTube, url)

            val streams = info.audioStreams
            // Prioritize high-fidelity Opus stream (~160kbps studio master) or absolute highest bitrate audio stream
            val validStreams = streams?.filter { it.isUrl && !it.content.isNullOrBlank() } ?: emptyList()
            val best = validStreams
                .filter { (it.format?.mimeType?.contains("opus", ignoreCase = true) == true || it.format?.mimeType?.contains("webm", ignoreCase = true) == true) && it.averageBitrate >= 140000 }
                .maxByOrNull { it.averageBitrate }
                ?: validStreams.maxByOrNull { it.averageBitrate }

            if (best == null) {
                return mapOf(
                    "ok" to false,
                    "reason" to "no_audio_stream",
                    "message" to "No audio stream available"
                )
            }

            android.util.Log.i("ShrexNewPipe", "RESOLVED URL: " + best.content)
            try {
                val conn = java.net.URL(best.content).openConnection() as java.net.HttpURLConnection
                conn.setRequestProperty("User-Agent", NoteNativeDownloader.USER_AGENT)
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                val code = conn.responseCode
                android.util.Log.i("ShrexNewPipe", "TEST HTTP RESPONSE: $code, content-type: ${conn.contentType}, length: ${conn.contentLength}")
                conn.disconnect()
            } catch (e: Exception) {
                android.util.Log.e("ShrexNewPipe", "TEST HTTP ERROR: $e")
            }

            mapOf(
                "ok" to true,
                "url" to best.content,
                "mimeType" to best.format?.mimeType,
                "bitrate" to best.averageBitrate,
                "durationSeconds" to info.duration,
                "title" to info.name,
                "uploader" to info.uploaderName,
                "streamType" to info.streamType.name,
                "extractor" to "NewPipeExtractor/v0.26.5",
                "userAgent" to NoteNativeDownloader.USER_AGENT
            )
        } catch (e: Throwable) {
            mapOf(
                "ok" to false,
                "reason" to "extraction_failed",
                "message" to (e.message ?: e.javaClass.simpleName)
            )
        }
    }
}
