// Compresses the same videos with several Flutter packages, one after the
// other, and prints one `BENCH {json}` line per run to the log.
//
//   flutter build apk --release --dart-define=INPUTS=/data/user/0/<pkg>/files/a.mp4,...
//
// Every package gets its own 720p (or "medium") preset; the output is then
// read with the same reader, so sizes and bitrates are comparable. Picture
// quality is measured afterwards on a computer (tool/ssim.py).
//
// light_compressor 2.2.0 is left out: it does not build with Flutter 3.47
// (no namespace, needs JitPack, and its Kotlin fails to compile with Kotlin 2.4).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compress_video/compress_video.dart' as cv;
import 'package:easy_video_editor/easy_video_editor.dart' as eve;
import 'package:flutter/material.dart';
import 'package:media_compress_kit/media_compress_kit.dart' as mck;
import 'package:v_video_compressor/v_video_compressor.dart' as vvc;
import 'package:video_compress/video_compress.dart' as vc;
import 'package:video_compress_next/video_compress_next.dart' as vcn;

const inputs = String.fromEnvironment('INPUTS');
const rounds = int.fromEnvironment('ROUNDS', defaultValue: 2);

typedef Compress = Future<String> Function(String input);

final Map<String, Compress> packages = {
  'video_compress_next': (input) async => (await vcn.VideoCompressor.compress(input).result).path,
  'video_compress': (input) async {
    final info = await vc.VideoCompress.compressVideo(input, quality: vc.VideoQuality.DefaultQuality);
    return info!.path!;
  },
  'compress_video': (input) async {
    final job = cv.CompressVideo().compress(
      input,
      options: const cv.CompressOptions(preset: cv.CompressPreset.p720),
    );
    return (await job.result).outputPath;
  },
  'v_video_compressor': (input) async {
    final result = await vvc.VVideoCompressor().compressVideo(
      input,
      const vvc.VVideoCompressionConfig.medium(),
    );
    return result!.compressedFilePath;
  },
  'media_compress_kit': (input) async {
    final result = await mck.MediaCompress.compressVideo(
      input,
      options: const mck.VideoOptions(quality: mck.VideoQuality.medium),
    );
    return result.path;
  },
  'easy_video_editor': (input) async {
    final path = await eve.VideoEditorBuilder(videoPath: input)
        .compress(resolution: eve.VideoResolution.p720)
        .export();
    return path!;
  },
};

void log(Map<String, Object?> line) => debugPrint('BENCH ${jsonEncode(line)}');

const chmodOnly = bool.fromEnvironment('CHMOD_ONLY');

Future<void> run() async {
  final files = inputs.split(',').where((p) => p.isNotEmpty).toList();
  if (chmodOnly) {
    // Some packages write their output readable by the app only, and copies keep that mode;
    // this opens the kept files to adb pull without compressing again.
    final dir = '${File(await vcn.VideoCompressor.cacheDirectory()).parent.path}/bench';
    final result = await Process.run('sh', ['-c', 'chmod 644 $dir/*.mp4 && ls -l $dir']);
    log({'event': 'done', 'info': '${result.stdout}${result.stderr}'});
    return;
  }
  // Kept outputs go to the app's own folder, never next to the inputs.
  final keep = Directory('${File(await vcn.VideoCompressor.cacheDirectory()).parent.path}/bench')
    ..createSync(recursive: true);
  for (final input in files) {
    final source = await vcn.VideoCompressor.getMediaInfo(input);
    log({'event': 'source', 'input': input, 'info': '$source'});
    for (var round = 0; round < rounds; round++) {
      // Alternate the order so heat from earlier runs does not always hit the same package.
      final names = round.isEven ? packages.keys.toList() : packages.keys.toList().reversed.toList();
      for (final name in names) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final watch = Stopwatch()..start();
        try {
          final output = await packages[name]!(input);
          final ms = watch.elapsedMilliseconds;
          final info = await vcn.VideoCompressor.getMediaInfo(output);
          var kept = output;
          if (round == 0) {
            kept = '${keep.path}/${input.split('/').last.split('.').first}__$name.mp4';
            await File(output).copy(kept);
          }
          if (output != input) await File(output).delete();
          log({
            'package': name,
            'input': input.split('/').last,
            'round': round,
            'ms': ms,
            'bytes': info.fileSize,
            'width': info.width,
            'height': info.height,
            'rotation': info.rotation,
            'fps': info.frameRate,
            'bitrate': info.bitrate,
            'durationMs': info.duration.inMilliseconds,
            'audio': info.hasAudio,
            'mime': info.videoMimeType,
            'kept': round == 0 ? kept : null,
          });
        } catch (e) {
          log({'package': name, 'input': input.split('/').last, 'round': round, 'error': '$e'});
        }
      }
    }
  }
  log({'event': 'done'});
}

void main() {
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Benchmark running, see logcat')))));
  unawaited(run());
}
