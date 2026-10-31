import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress_next/video_compress_next.dart';

void main() => runApp(const MaterialApp(home: CompressPage()));

/// Copies a bundled sample video to a real file, since the plugin reads files.
Future<String> sampleFile(String asset) async {
  final file = File('${await VideoCompressor.cacheDirectory()}/sample_${asset.split('/').last}');
  if (!file.existsSync()) {
    final data = await rootBundle.load(asset);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }
  return file.path;
}

class CompressPage extends StatefulWidget {
  const CompressPage({super.key});

  @override
  State<CompressPage> createState() => _CompressPageState();
}

class _CompressPageState extends State<CompressPage> {
  static const _sizes = {360: '360p', 480: '480p', 720: '720p', 1080: '1080p'};

  VideoInfo? _source;
  Uint8List? _thumbnail;
  int _shortSide = 720;
  bool _audio = true;
  bool _hevc = false;
  CompressTask? _task;
  double _progress = 0;
  VideoInfo? _result;
  Duration? _took;
  String? _error;

  Future<void> _open(Future<String?> path) async {
    final p = await path;
    if (p == null) return;
    setState(() {
      _source = null;
      _thumbnail = null;
      _result = null;
      _error = null;
    });
    try {
      final info = await VideoCompressor.getMediaInfo(p);
      final thumbnail = await VideoCompressor.getThumbnail(p, maxSide: 320);
      setState(() {
        _source = info;
        _thumbnail = thumbnail;
      });
    } on VideoCompressException catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<String?> _pick() async => (await ImagePicker().pickVideo(source: ImageSource.gallery))?.path;

  Future<void> _compress() async {
    final source = _source!;
    final task = VideoCompressor.compress(
      source.path,
      options: CompressOptions(
        maxShortSide: _shortSide,
        includeAudio: _audio,
        codec: _hevc ? VideoCodec.hevc : VideoCodec.h264,
      ),
    );
    final watch = Stopwatch()..start();
    setState(() {
      _task = task;
      _progress = 0;
      _result = null;
      _error = null;
    });
    task.progress.listen((p) => setState(() => _progress = p));
    try {
      final result = await task.result;
      setState(() {
        _result = result;
        _took = watch.elapsed;
      });
    } on VideoCompressException catch (e) {
      setState(() => _error = e.error == VideoCompressError.cancelled ? 'Cancelled' : '$e');
    } finally {
      setState(() => _task = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final result = _result;
    final busy = _task != null;
    return Scaffold(
      appBar: AppBar(title: const Text('video_compress_next')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              onPressed: busy ? null : () => _open(sampleFile('assets/landscape.mp4')),
              child: const Text('Sample 1080p60'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => _open(sampleFile('assets/portrait.mp4')),
              child: const Text('Sample portrait'),
            ),
            OutlinedButton(onPressed: busy ? null : () => _open(_pick()), child: const Text('Gallery')),
          ]),
          if (source != null) ...[
            const SizedBox(height: 16),
            if (_thumbnail != null) Center(child: Image.memory(_thumbnail!, height: 160)),
            _InfoCard(title: 'Source', info: source),
            Wrap(spacing: 8, children: [
              for (final entry in _sizes.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _shortSide == entry.key,
                  onSelected: busy ? null : (_) => setState(() => _shortSide = entry.key),
                ),
            ]),
            SwitchListTile(
              title: const Text('Keep audio'),
              value: _audio,
              onChanged: busy ? null : (v) => setState(() => _audio = v),
            ),
            SwitchListTile(
              title: const Text('HEVC'),
              value: _hevc,
              onChanged: busy ? null : (v) => setState(() => _hevc = v),
            ),
            if (busy) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).round()} %'),
              TextButton(onPressed: () => _task?.cancel(), child: const Text('Cancel')),
            ] else
              FilledButton(key: const Key('compress'), onPressed: _compress, child: const Text('Compress')),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          if (result != null && source != null) ...[
            _InfoCard(title: 'Result', info: result),
            Text(
              '${(result.fileSize * 100 / source.fileSize).toStringAsFixed(0)} % of the source size, '
              'in ${(_took!.inMilliseconds / 1000).toStringAsFixed(1)} s',
              key: const Key('summary'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.info});

  final String title;
  final VideoInfo info;

  @override
  Widget build(BuildContext context) {
    final mb = (info.fileSize / 1e6).toStringAsFixed(2);
    final mbps = info.bitrate == null ? '?' : (info.bitrate! / 1e6).toStringAsFixed(1);
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text('${info.width}x${info.height}, ${info.frameRate?.toStringAsFixed(0) ?? '?'} fps, '
            '${(info.duration.inMilliseconds / 1000).toStringAsFixed(1)} s, $mb MB, $mbps Mbps, '
            '${info.videoMimeType ?? '?'}, ${info.hasAudio ? 'audio' : 'no audio'}'),
      ),
    );
  }
}
