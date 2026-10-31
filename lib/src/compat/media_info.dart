// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'dart:io';

import '../video_info.dart';

/// The result type of `video_compress`, with the same fields and JSON keys.
class MediaInfo {
  /// Creates the info with the given fields.
  MediaInfo({
    required this.path,
    this.title,
    this.author,
    this.width,
    this.height,
    this.orientation,
    this.filesize,
    this.duration,
    this.isCancel,
    this.file,
  });

  /// Reads the JSON that [toJson] writes.
  MediaInfo.fromJson(Map<String, dynamic> json) {
    path = json['path'] as String?;
    title = json['title'] as String?;
    author = json['author'] as String?;
    width = (json['width'] as num?)?.toInt();
    height = (json['height'] as num?)?.toInt();
    orientation = (json['orientation'] as num?)?.toInt();
    filesize = (json['filesize'] as num?)?.toInt();
    duration = double.tryParse('${json['duration']}');
    isCancel = json['isCancel'] as bool?;
    file = File(path!);
  }

  /// Converts the info of the new API.
  factory MediaInfo.fromVideoInfo(VideoInfo info, {bool? isCancel}) =>
      MediaInfo(
        path: info.path,
        title: info.title ?? '',
        author: info.author ?? '',
        width: info.width,
        height: info.height,
        orientation: info.rotation,
        filesize: info.fileSize,
        duration: info.duration.inMilliseconds.toDouble(),
        isCancel: isCancel,
        file: File(info.path),
      );

  /// The video file.
  String? path;

  /// The title from the file's metadata, or empty.
  String? title;

  /// The author from the file's metadata, or empty.
  String? author;

  /// Displayed width, after rotation.
  int? width;

  /// Displayed height, after rotation.
  int? height;

  /// Rotation in degrees.
  int? orientation;

  /// Bytes.
  int? filesize;

  /// Milliseconds.
  double? duration;

  /// False after a successful compression, null from `getMediaInfo`.
  bool? isCancel;

  /// [path] as a [File].
  File? file;

  /// The same JSON `video_compress` produced.
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'path': path,
      'title': title,
      'author': author,
      'width': width,
      'height': height,
    };
    if (orientation != null) data['orientation'] = orientation;
    data['filesize'] = filesize;
    data['duration'] = duration;
    if (isCancel != null) data['isCancel'] = isCancel;
    data['file'] = File(path!).toString();
    return data;
  }
}
