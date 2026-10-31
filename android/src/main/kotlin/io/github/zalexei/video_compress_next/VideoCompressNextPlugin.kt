// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.video_compress_next

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class VideoCompressNextPlugin : FlutterPlugin, VideoCompressHostApi {
    private var context: Context? = null
    private var flutterApi: VideoCompressFlutterApi? = null
    private val jobs = mutableMapOf<String, CompressJob>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var background: ExecutorService

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        flutterApi = VideoCompressFlutterApi(binding.binaryMessenger)
        // Two threads: a grid of thumbnails would otherwise start one decoder per call.
        background = Executors.newFixedThreadPool(2)
        VideoCompressHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        VideoCompressHostApi.setUp(binding.binaryMessenger, null)
        jobs.values.toList().forEach { it.cancel() }
        jobs.clear()
        background.shutdown()
        flutterApi = null
        context = null
    }

    override fun getMediaInfo(path: String, callback: (Result<NativeMediaInfo>) -> Unit) {
        val context = requireContext()
        runInBackground(callback) { MediaInfoReader.read(context, path) }
    }

    override fun compress(request: NativeCompressRequest, callback: (Result<Unit>) -> Unit) {
        val context = requireContext()
        if (jobs.containsKey(request.taskId)) {
            callback(Result.failure(FlutterError("failed", "Task ${request.taskId} is already running")))
            return
        }
        val job = CompressJob(
            context,
            request,
            onProgress = { flutterApi?.onProgress(request.taskId, it) {} },
            onDone = { result ->
                jobs.remove(request.taskId)
                callback(result)
            },
        )
        jobs[request.taskId] = job
        job.start()
    }

    override fun cancel(taskId: String) {
        jobs[taskId]?.cancel()
    }

    override fun getThumbnail(request: NativeThumbnailRequest, callback: (Result<ByteArray>) -> Unit) {
        val context = requireContext()
        runInBackground(callback) { Thumbnails.jpeg(context, request) }
    }

    override fun cacheDirectory(): String {
        val context = requireContext()
        val dir = context.getExternalFilesDir(CACHE_FOLDER) ?: File(context.filesDir, CACHE_FOLDER)
        dir.mkdirs()
        return dir.absolutePath
    }

    private fun requireContext(): Context =
        context ?: throw FlutterError("failed", "The plugin is not attached to an engine")

    // Replies go back on the main thread, where the engine expects them.
    private fun <T> runInBackground(callback: (Result<T>) -> Unit, work: () -> T) {
        background.execute {
            val result = try {
                Result.success(work())
            } catch (e: FlutterError) {
                Result.failure(e)
            } catch (e: Throwable) {
                // Throwable, not Exception: an OutOfMemoryError on a 4K frame
                // would otherwise end the app and leave the Dart call waiting.
                Result.failure(FlutterError("failed", e.toString()))
            }
            mainHandler.post { callback(result) }
        }
    }

    private companion object {
        const val CACHE_FOLDER = "video_compress_next"
    }
}
