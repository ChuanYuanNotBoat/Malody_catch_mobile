import 'dart:math';

import 'package:flutter/material.dart';

import '../core/native_core.dart';

class SimpleDensityBar extends StatelessWidget {
  const SimpleDensityBar({
    super.key,
    required this.notes,
    required this.playheadBeat,
    required this.onSeekBeat,
  });

  final List<CoreNoteSnapshot> notes;
  final double playheadBeat;
  final ValueChanged<double> onSeekBeat;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          _seek(details.localPosition.dy, context.size?.height ?? 1),
      onVerticalDragUpdate: (details) =>
          _seek(details.localPosition.dy, context.size?.height ?? 1),
      child: CustomPaint(
        painter: _DensityPainter(notes: notes, playheadBeat: playheadBeat),
        child: const SizedBox(width: 56),
      ),
    );
  }

  void _seek(double y, double height) {
    if (height <= 1) {
      return;
    }
    final maxBeat = _maxBeat(notes);
    final ratio = (1.0 - (y / height)).clamp(0.0, 1.0);
    onSeekBeat(ratio * maxBeat);
  }

  static double _maxBeat(List<CoreNoteSnapshot> notes) {
    var maxBeat = 16.0;
    for (final note in notes) {
      final beat =
          note.beat.measure +
          note.beat.numerator / max(1, note.beat.denominator);
      final endBeat =
          note.endBeat.measure +
          note.endBeat.numerator / max(1, note.endBeat.denominator);
      maxBeat = max(maxBeat, max(beat, endBeat) + 4);
    }
    return maxBeat;
  }
}

class _DensityPainter extends CustomPainter {
  _DensityPainter({required this.notes, required this.playheadBeat});

  final List<CoreNoteSnapshot> notes;
  final double playheadBeat;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF0E1219);
    canvas.drawRect(Offset.zero & size, bg);

    const bins = 72;
    final bucket = List<int>.filled(bins, 0);
    final maxBeat = SimpleDensityBar._maxBeat(notes);
    for (final note in notes) {
      final beat =
          note.beat.measure +
          note.beat.numerator / max(1, note.beat.denominator);
      final idx = ((beat / maxBeat) * (bins - 1)).round().clamp(0, bins - 1);
      bucket[idx] += 1;
    }

    final peak = max(1, bucket.reduce(max));
    final paint = Paint()..color = const Color(0xFFDEE6F2);
    for (var i = 0; i < bins; i++) {
      final y0 = size.height - (i + 1) / bins * size.height;
      final y1 = size.height - i / bins * size.height;
      final h = max(1.0, y1 - y0 - 1.0);
      final w = bucket[i] / peak * (size.width - 8);
      if (w <= 0) {
        continue;
      }
      canvas.drawRect(Rect.fromLTWH(size.width - 4 - w, y0, w, h), paint);
    }

    final lineY =
        size.height - (playheadBeat / maxBeat).clamp(0.0, 1.0) * size.height;
    final line = Paint()
      ..color = const Color(0xFFFF7A59)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, lineY), Offset(size.width, lineY), line);
  }

  @override
  bool shouldRepaint(covariant _DensityPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.playheadBeat != playheadBeat;
  }
}
