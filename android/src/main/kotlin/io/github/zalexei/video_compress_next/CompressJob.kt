// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.video_compress_next

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File

/**
 * One compression with Media3 Transformer. Lives on the main thread: Transformer
 * must be used from the thread it was built on.
 */
@OptIn(UnstableApi::class)
internal class CompressJob(
    private val context: Context,
    private val request: NativeCompressRequest,
    private val onProgress: (Double) -> Unit,
    private val onDone: (Result<Unit>) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val output = File(request.outputPath)
    private var transformer: Transformer? = null
    private var finished = false

    fun start() {
        try {
            Sources.size(context, request.inputPath) // Fails early with file_not_found.
            output.parentFile?.mkdirs()
            output.delete()
            val transformer = buildTransformer()
            this.transformer = transformer
            transformer.start(composition(), output.absolutePath)
        } catch (e: FlutterError) {
            finish(Result.failure(e))
            return
        } catch (e: Exception) {
            finish(Result.failure(FlutterError("failed", e.toString())))
            return
        }
        pollProgress()
    }

    fun cancel() {
        if (finished) return
        transformer?.cancel()
        output.delete()
        finish(Result.failure(FlutterError("cancelled", "The compression was cancelled.")))
    }

    private fun buildTransformer(): Transformer {
        val videoSettings = VideoEncoderSettings.Builder()
        request.videoBitrate?.let { videoSettings.setBitrate(it.toInt()) }
        val encoders = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(videoSettings.build())
            // Lets the encoder lower the size or bitrate it cannot do, instead of failing.
            .setEnableFallback(true)
            .build()
        return Transformer.Builder(context)
            .setVideoMimeType(
                if (request.codec == NativeVideoCodec.HEVC) MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264,
            )
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoders)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    onProgress(1.0)
                    finish(Result.success(Unit))
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    output.delete()
                    finish(Result.failure(error(exportException)))
                }
            })
            .build()
    }

    private fun composition(): Composition {
        val item = MediaItem.Builder().setUri(Sources.uri(request.inputPath))
        if (request.startMs != null || request.endMs != null) {
            val clipping = MediaItem.ClippingConfiguration.Builder()
            request.startMs?.let { clipping.setStartPositionMs(it) }
            request.endMs?.let { clipping.setEndPositionMs(it) }
            item.setClippingConfiguration(clipping.build())
        }

        val videoEffects = mutableListOf<Effect>()
        // Frame dropping goes first, so later effects process fewer frames.
        request.maxFrameRate?.let {
            videoEffects.add(FrameDropEffect.createDefaultFrameDropEffect(it.toFloat()))
        }
        val width = request.width?.toInt()
        val height = request.height?.toInt()
        if (width != null && height != null) {
            // Effects see the frame as displayed, after rotation, so a portrait
            // video keeps its portrait size.
            videoEffects.add(
                Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT),
            )
        }

        val edited = EditedMediaItem.Builder(item.build())
            .setRemoveAudio(!request.includeAudio)
            .setEffects(Effects(listOf(), videoEffects))
            .build()
        return Composition.Builder(EditedMediaItemSequence.Builder(edited).build())
            // H.264 has no HDR that plays everywhere; SDR looks right on any screen.
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            .build()
    }

    private fun pollProgress() {
        val holder = ProgressHolder()
        handler.post(object : Runnable {
            override fun run() {
                val transformer = transformer ?: return
                if (finished) return
                if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    onProgress(holder.progress / 100.0)
                }
                handler.postDelayed(this, PROGRESS_INTERVAL_MS)
            }
        })
    }

    private fun finish(result: Result<Unit>) {
        if (finished) return
        finished = true
        handler.removeCallbacksAndMessages(null)
        onDone(result)
    }

    private fun error(e: ExportException): FlutterError {
        val code = when (e.errorCode) {
            ExportException.ERROR_CODE_IO_FILE_NOT_FOUND,
            ExportException.ERROR_CODE_IO_NO_PERMISSION -> "file_not_found"
            ExportException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            ExportException.ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED,
            ExportException.ERROR_CODE_DECODER_INIT_FAILED,
            ExportException.ERROR_CODE_ENCODER_INIT_FAILED -> "unsupported"
            else -> "failed"
        }
        return FlutterError(code, "${e.errorCodeName}: ${e.message}")
    }

    private companion object {
        const val PROGRESS_INTERVAL_MS = 200L
    }
}
