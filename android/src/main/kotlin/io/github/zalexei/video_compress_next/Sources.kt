// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.video_compress_next

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.net.Uri
import java.io.File

/** Paths from Dart are plain file paths, `file://` or `content://` URIs. */
internal object Sources {
    fun uri(path: String): Uri =
        if (path.startsWith("content://") || path.startsWith("file://")) Uri.parse(path)
        else Uri.fromFile(File(path))

    fun size(context: Context, path: String): Long {
        val uri = uri(path)
        if (uri.scheme == "file") {
            val file = File(uri.path!!)
            if (!file.exists()) throw FlutterError("file_not_found", "No file at $path")
            // A file another user created (adb push, another app) can exist and still be closed to us.
            if (!file.canRead()) throw FlutterError("file_not_found", "No permission to read $path")
            return file.length()
        }
        return try {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use {
                if (it.length == AssetFileDescriptor.UNKNOWN_LENGTH) 0L else it.length
            } ?: throw FlutterError("file_not_found", "Cannot open $path")
        } catch (e: java.io.FileNotFoundException) {
            throw FlutterError("file_not_found", "Cannot open $path: ${e.message}")
        }
    }
}
