import 'dart:math';

import 'package:flutter/material.dart';

import '../core/chart_document_controller.dart';
import '../core/native_core.dart';

class SimpleChartCanvas extends StatefulWidget {
  const SimpleChartCanvas({
    super.key,
    required this.notes,
    required this.selectedIds,
    required this.mode,
    required this.viewBeat,
    required this.onViewBeatChanged,
    required this.onHitNote,
    required this.onPlaceNormal,
    required this.onPlaceRain,
    required this.onMoveSelected,
  });

  final List<CoreNoteSnapshot> notes;
  final Set<String> selectedIds;
  final EditorMode mode;
  final double viewBeat;
  final ValueChanged<double> onViewBeatChanged;
  final ValueChanged<String> onHitNote;
  final void Function(double beat, int x) onPlaceNormal;
  final void Function(double beat, int x) onPlaceRain;
  final void Function(double beat, int x) onMoveSelected;

  @override
  State<SimpleChartCanvas> createState() => _SimpleChartCanvasState();
}

class _SimpleChartCanvasState extends State<SimpleChartCanvas> {
  static const double _visibleBeats = 16.0;
  String? _draggingNoteId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => _handleTap(details.localPosition),
      onPanStart: (details) => _handlePanStart(details.localPosition),
      onPanUpdate: (details) =>
          _handlePanUpdate(details.localPosition, details.delta),
      onPanEnd: (_) => _draggingNoteId = null,
      child: CustomPaint(
        painter: _CanvasPainter(
          notes: widget.notes,
          selectedIds: widget.selectedIds,
          viewBeat: widget.viewBeat,
          visibleBeats: _visibleBeats,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _handleTap(Offset position) {
    final hit = _hitTest(position);
    if (hit != null) {
      widget.onHitNote(hit.id);
      return;
    }

    final beat = _positionToBeat(position.dy, context.size?.height ?? 1);
    final x = _positionToLaneX(position.dx, context.size?.width ?? 1);
    if (widget.mode == EditorMode.placeRain) {
      widget.onPlaceRain(beat, x);
    } else if (widget.mode == EditorMode.placeNormal) {
      widget.onPlaceNormal(beat, x);
    }
  }

  void _handlePanStart(Offset position) {
    final hit = _hitTest(position);
    if (hit != null && widget.selectedIds.contains(hit.id)) {
      _draggingNoteId = hit.id;
    } else {
      _draggingNoteId = null;
    }
  }

  void _handlePanUpdate(Offset position, Offset delta) {
    if (_draggingNoteId != null) {
      final beat = _positionToBeat(position.dy, context.size?.height ?? 1);
      final x = _positionToLaneX(position.dx, context.size?.width ?? 1);
      widget.onMoveSelected(beat, x);
      return;
    }

    final next = max(0.0, widget.viewBeat + delta.dy * 0.03);
    widget.onViewBeatChanged(next);
  }

  CoreNoteSnapshot? _hitTest(Offset position) {
    final size = context.size;
    if (size == null) {
      return null;
    }

    CoreNoteSnapshot? best;
    var bestDist = double.infinity;
    for (final note in widget.notes) {
      final beat =
          note.beat.measure +
          note.beat.numerator / max(1, note.beat.denominator);
      final y = _beatToY(beat, size.height);
      final x = (note.x.clamp(0, 512) / 512.0) * size.width;
      final dist = (position - Offset(x, y)).distance;
      if (dist < 24 && dist < bestDist) {
        best = note;
        bestDist = dist;
      }
    }
    return best;
  }

  double _beatToY(double beat, double height) {
    final ratio = ((beat - widget.viewBeat) / _visibleBeats).clamp(0.0, 1.0);
    return height - ratio * height;
  }

  double _positionToBeat(double y, double height) {
    if (height <= 1) {
      return widget.viewBeat;
    }
    final ratio = (1.0 - (y / height)).clamp(0.0, 1.0);
    return widget.viewBeat + ratio * _visibleBeats;
  }

  int _positionToLaneX(double x, double width) {
    if (width <= 1) {
      return 256;
    }
    return (x / width * 512).round().clamp(0, 512);
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.notes,
    required this.selectedIds,
    required this.viewBeat,
    required this.visibleBeats,
  });

  final List<CoreNoteSnapshot> notes;
  final Set<String> selectedIds;
  final double viewBeat;
  final double visibleBeats;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF151A23);
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()
      ..color = const Color(0xFF2A3444)
      ..strokeWidth = 1;
    for (var i = 0; i <= 8; i++) {
      final y = size.height * i / 8;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 0; i <= 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    for (final note in notes) {
      final beat =
          note.beat.measure +
          note.beat.numerator / max(1, note.beat.denominator);
      final ratio = ((beat - viewBeat) / visibleBeats).clamp(0.0, 1.0);
      final y = size.height - ratio * size.height;
      final x = (note.x.clamp(0, 512) / 512.0) * size.width;
      final selected = selectedIds.contains(note.id);

      final color = switch (note.type) {
        3 => const Color(0xFF4FC3F7),
        1 => const Color(0xFFFFD54F),
        _ => const Color(0xFF81C784),
      };

      if (note.type == 3) {
        final endBeat =
            note.endBeat.measure +
            note.endBeat.numerator / max(1, note.endBeat.denominator);
        final endRatio = ((endBeat - viewBeat) / visibleBeats).clamp(0.0, 1.0);
        final endY = size.height - endRatio * size.height;
        final rect = Rect.fromLTRB(x - 8, min(y, endY), x + 8, max(y, endY));
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = color.withValues(alpha: 0.8),
        );
      }

      canvas.drawCircle(
        Offset(x, y),
        selected ? 11 : 8,
        Paint()..color = color,
      );
      if (selected) {
        canvas.drawCircle(
          Offset(x, y),
          13,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.selectedIds != selectedIds ||
        oldDelegate.viewBeat != viewBeat;
  }
}
