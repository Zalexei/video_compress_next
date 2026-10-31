// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.video_compress_next

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

internal object Thumbnails {
    fun jpeg(context: Context, request: NativeThumbnailRequest): ByteArray {
        Sources.size(context, request.path) // Fails early with file_not_found.
        val retriever = MediaMetadataRetriever()
        val frame = try {
            retriever.setDataSource(context, Sources.uri(request.path))
            val timeUs: Long
            val option: Int
            if (request.positionMs < 0) {
                timeUs = -1L
                option = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            } else {
                // The frame at the position, not the key frame before it,
                // which can be seconds away in screen or messenger videos.
                timeUs = request.positionMs * 1000
                option = MediaMetadataRetriever.OPTION_CLOSEST
            }
            val maxSide = request.maxSide?.toInt()?.takeIf { it < longestSide(retriever) }
            if (maxSide != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(timeUs, option, maxSide, maxSide)
            } else {
                retriever.getFrameAtTime(timeUs, option)?.let { scaleDown(it, maxSide) }
            }
        } catch (e: SecurityException) {
            throw FlutterError("file_not_found", "No permission to read ${request.path}: ${e.message}")
        } catch (e: RuntimeException) {
            throw FlutterError("unsupported", "Cannot read a frame of ${request.path}: ${e.message}")
        } finally {
            retriever.release()
        } ?: throw FlutterError("unsupported", "No frame at ${request.positionMs} ms in ${request.path}")

        val stream = ByteArrayOutputStream()
        frame.compress(Bitmap.CompressFormat.JPEG, request.quality.toInt().coerceIn(1, 100), stream)
        frame.recycle()
        return stream.toByteArray()
    }

    /** The longer side of the stored frame; scaling "down" to more would enlarge it. */
    private fun longestSide(retriever: MediaMetadataRetriever): Int {
        fun int(key: Int) = retriever.extractMetadata(key)?.toIntOrNull() ?: 0
        return max(
            int(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH),
            int(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT),
        ).takeIf { it > 0 } ?: Int.MAX_VALUE
    }

    private fun scaleDown(bitmap: Bitmap, maxSide: Int?): Bitmap {
        val longest = max(bitmap.width, bitmap.height)
        if (maxSide == null || longest <= maxSide) return bitmap
        val scale = maxSide.toFloat() / longest
        val scaled = Bitmap.createScaledBitmap(
            bitmap, (bitmap.width * scale).roundToInt(), (bitmap.height * scale).roundToInt(), true,
        )
        bitmap.recycle()
        return scaled
    }
}
