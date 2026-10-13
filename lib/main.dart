import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Size of the generated backgrounds, matching the full-screen backgrounds in
/// the app where the issue was reported.
const int _imageWidth = 3840;
const int _imageHeight = 1980;
const int _imageCount = 6;

void main() {
  runApp(const ReproApp());
}

class ReproApp extends StatelessWidget {
  const ReproApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReproPage(),
    );
  }
}

/// Shows large PNG backgrounds downscaled to the screen with `Image.memory`,
/// cycling through them like an app navigating between pages.
class ReproPage extends StatefulWidget {
  const ReproPage({super.key});

  @override
  State<ReproPage> createState() => _ReproPageState();
}

class _ReproPageState extends State<ReproPage> {
  final String _webGlRenderer = _readWebGlRenderer();
  final bool _mipmapsDisabled = _readMipmapsDisabled();

  final List<Uint8List> _images = [];
  int _current = 0;
  int _layers = 1;
  FilterQuality _filterQuality = FilterQuality.medium;
  bool _cycling = true;
  Timer? _cycleTimer;

  @override
  void initState() {
    super.initState();
    _generateImages();
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _images.length == _imageCount;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            for (var layer = 0; layer < _layers; layer++)
              Image.memory(
                _images[(_current + layer) % _imageCount],
                fit: BoxFit.cover,
                filterQuality: _filterQuality,
                gaplessPlayback: true,
              )
          else
            Center(
              child: Text(
                'Generating backgrounds ${_images.length}/$_imageCount…',
                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
          Positioned(left: 16, bottom: 16, child: _buildControls()),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flutter ${FlutterVersion.version ?? 'unknown'}'),
            Text('WebGL renderer: $_webGlRenderer'),
            Text(
              _mipmapsDisabled
                  ? 'drawImageRectOptions patched: MipmapMode.None'
                  : 'drawImageRectOptions unpatched',
            ),
            const SizedBox(height: 8),
            SegmentedButton<FilterQuality>(
              segments: [
                for (final quality in FilterQuality.values)
                  ButtonSegment(value: quality, label: Text(quality.name)),
              ],
              selected: {_filterQuality},
              onSelectionChanged: (selection) =>
                  setState(() => _filterQuality = selection.single),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Stacked images: $_layers'),
                Slider(
                  value: _layers.toDouble(),
                  min: 1,
                  max: _imageCount.toDouble(),
                  divisions: _imageCount - 1,
                  onChanged: (value) => setState(() => _layers = value.round()),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Cycle every second'),
                Switch(value: _cycling, onChanged: _setCycling),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateImages() async {
    for (var index = 0; index < _imageCount; index++) {
      final bytes = await _generatePng(index);
      if (!mounted) {
        return;
      }
      setState(() => _images.add(bytes));
    }
    _setCycling(_cycling);
  }

  void _setCycling(bool cycling) {
    _cycleTimer?.cancel();
    _cycleTimer = cycling
        ? Timer.periodic(
            const Duration(seconds: 1),
            (_) => setState(() => _current = (_current + 1) % _imageCount),
          )
        : null;
    setState(() => _cycling = cycling);
  }
}

/// Draws a background with a gradient, a fine grid and a label, and encodes it
/// as PNG, so it is decoded like an image asset.
Future<Uint8List> _generatePng(int index) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(_imageWidth * 1.0, _imageHeight * 1.0);
  final hue = 360.0 * index / _imageCount;

  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        size.bottomRight(Offset.zero),
        [
          HSVColor.fromAHSV(1, hue, 0.6, 0.9).toColor(),
          HSVColor.fromAHSV(1, (hue + 60) % 360, 0.8, 0.4).toColor(),
        ],
      ),
  );

  final gridPaint = Paint()
    ..color = Colors.white24
    ..strokeWidth = 2;
  for (var x = 0.0; x < size.width; x += 48) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
  }
  for (var y = 0.0; y < size.height; y += 48) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
  }

  final label = TextPainter(
    text: TextSpan(
      text: 'Background ${index + 1}',
      style: const TextStyle(color: Colors.white, fontSize: 320),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  label.paint(
    canvas,
    size.center(Offset.zero) - label.size.center(Offset.zero),
  );
  label.dispose();

  final picture = recorder.endRecording();
  final image = await picture.toImage(_imageWidth, _imageHeight);
  picture.dispose();
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

String _readWebGlRenderer() {
  try {
    final canvas = web.HTMLCanvasElement();
    final gl = canvas.getContext('webgl') as web.WebGLRenderingContext?;
    if (gl == null) {
      return 'WebGL unavailable';
    }
    if (gl.getExtension('WEBGL_debug_renderer_info') == null) {
      return 'unknown';
    }
    const unmaskedRendererWebgl = 0x9246;
    return gl.getParameter(unmaskedRendererWebgl).dartify()?.toString() ??
        'unknown';
  } catch (_) {
    return 'unknown';
  }
}

bool _readMipmapsDisabled() {
  return web.window
          .getProperty<JSBoolean?>('__repro_mipmaps_disabled'.toJS)
          ?.toDart ??
      false;
}
