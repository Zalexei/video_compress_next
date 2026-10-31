// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.video_compress_next

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build

/** Reads the container metadata without decoding any frame. */
internal object MediaInfoReader {
    fun read(context: Context, path: String): NativeMediaInfo {
        val fileSize = Sources.size(context, path)
        val retriever = MediaMetadataRetriever()
        try {
            try {
                retriever.setDataSource(context, Sources.uri(path))
            } catch (e: SecurityException) {
                throw FlutterError("file_not_found", "No permission to read $path: ${e.message}")
            } catch (e: RuntimeException) {
                throw FlutterError("unsupported", "Cannot read $path: ${e.message}")
            }
            fun string(key: Int): String? = retriever.extractMetadata(key)
            fun long(key: Int): Long? = string(key)?.toLongOrNull()

            if (string(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes") {
                throw FlutterError("unsupported", "No video track in $path")
            }
            val storedWidth = long(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH) ?: 0
            val storedHeight = long(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT) ?: 0
            val rotation = long(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) ?: 0
            if (storedWidth <= 0 || storedHeight <= 0) {
                throw FlutterError("unsupported", "Cannot read the picture size of $path")
            }
            val sideways = rotation % 180 != 0L
            val durationMs = long(MediaMetadataRetriever.METADATA_KEY_DURATION) ?: 0
            val track = videoTrack(context, path)

            return NativeMediaInfo(
                path = path,
                width = if (sideways) storedHeight else storedWidth,
                height = if (sideways) storedWidth else storedHeight,
                rotation = rotation,
                durationMs = durationMs,
                fileSize = fileSize,
                hasAudio = string(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes",
                bitrate = long(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                // The counted average first: the container's frame rate field
                // can keep the source's rate after frames were dropped.
                frameRate = frameRateFromCount(retriever, durationMs) ?: track?.frameRate,
                videoMimeType = track?.mimeType,
                title = string(MediaMetadataRetriever.METADATA_KEY_TITLE),
                author = string(MediaMetadataRetriever.METADATA_KEY_AUTHOR)
                    ?: string(MediaMetadataRetriever.METADATA_KEY_ARTIST),
            )
        } finally {
            retriever.release()
        }
    }

    private class VideoTrack(val mimeType: String?, val frameRate: Double?)

    private fun videoTrack(context: Context, path: String): VideoTrack? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(context, Sources.uri(path), null)
            (0 until extractor.trackCount)
                .map { extractor.getTrackFormat(it) }
                .firstOrNull { it.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true }
                ?.let { VideoTrack(it.getString(MediaFormat.KEY_MIME), frameRate(it)) }
        } catch (e: Exception) {
            null
        } finally {
            extractor.release()
        }
    }

    // KEY_FRAME_RATE is an Integer in some files and a Float in others.
    private fun frameRate(format: MediaFormat): Double? {
        if (!format.containsKey(MediaFormat.KEY_FRAME_RATE)) return null
        return try {
            format.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
        } catch (e: ClassCastException) {
            format.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble()
        }.takeIf { it > 0 }
    }

    private fun frameRateFromCount(retriever: MediaMetadataRetriever, durationMs: Long): Double? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || durationMs <= 0) return null
        val frames = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)
            ?.toLongOrNull() ?: return null
        return frames * 1000.0 / durationMs
    }
}
