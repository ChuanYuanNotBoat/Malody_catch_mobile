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
    required this.timeDivision,
    required this.viewBeat,
    required this.visibleBeats,
    required this.playheadBeat,
    required this.onViewBeatChanged,
    required this.onVisibleBeatsChanged,
    required this.onHitNote,
    required this.onPlaceNormal,
    required this.onPlaceRain,
    required this.onMoveSelected,
    required this.onMoveSelectedDelta,
    required this.onSelectRegion,
    this.onClearSelection,
    this.onLongPressContext,
  });

  final List<CoreNoteSnapshot> notes;
  final Set<String> selectedIds;
  final EditorMode mode;
  final int timeDivision;
  final double viewBeat;
  final double visibleBeats;
  final double playheadBeat;
  final ValueChanged<double> onViewBeatChanged;
  final ValueChanged<double> onVisibleBeatsChanged;
  final ValueChanged<String> onHitNote;
  final void Function(double beat, int x) onPlaceNormal;
  final void Function(double beat, int x) onPlaceRain;
  final void Function(double beat, int x) onMoveSelected;
  final void Function(double beatDelta, int xDelta) onMoveSelectedDelta;
  final void Function({
    required double startBeat,
    required double endBeat,
    required int startX,
    required int endX,
  })
  onSelectRegion;
  final VoidCallback? onClearSelection;
  final void Function(double beat, int x, Offset globalPosition)?
  onLongPressContext;

  @override
  State<SimpleChartCanvas> createState() => _SimpleChartCanvasState();
}

class _SimpleChartCanvasState extends State<SimpleChartCanvas> {
  static const double _minVisibleBeats = 4.0;
  static const double _maxVisibleBeats = 64.0;
  String? _draggingNoteId;
  double _scaleStartVisibleBeats = 16.0;
  bool _selectingRect = false;
  Offset? _selectStart;
  Offset? _selectEnd;
  double _dragLastBeat = 0;
  int _dragLastX = 256;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => _handleTap(details.localPosition),
      onLongPressStart: (details) =>
          _handleLongPress(details.localPosition, details.globalPosition),
      onScaleStart: (details) => _handleScaleStart(details.localFocalPoint),
      onScaleUpdate: (details) =>
          _handleScaleUpdate(details.localFocalPoint, details),
      onScaleEnd: (_) => _handleScaleEnd(),
      child: CustomPaint(
        painter: _CanvasPainter(
          notes: widget.notes,
          selectedIds: widget.selectedIds,
          timeDivision: widget.timeDivision,
          viewBeat: widget.viewBeat,
          playheadBeat: widget.playheadBeat,
          visibleBeats: widget.visibleBeats,
          selectStart: _selectStart,
          selectEnd: _selectEnd,
          selectingRect: _selectingRect,
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
    } else if (widget.mode == EditorMode.select) {
      widget.onClearSelection?.call();
    }
  }

  void _handleLongPress(Offset position, Offset globalPosition) {
    final beat = _positionToBeat(position.dy, context.size?.height ?? 1);
    final x = _positionToLaneX(position.dx, context.size?.width ?? 1);
    widget.onLongPressContext?.call(beat, x, globalPosition);
  }

  void _handleScaleStart(Offset position) {
    _scaleStartVisibleBeats = widget.visibleBeats;
    _selectingRect = false;
    _selectStart = null;
    _selectEnd = null;
    final hit = _hitTest(position);
    if (hit != null && widget.selectedIds.contains(hit.id)) {
      _draggingNoteId = hit.id;
      _dragLastBeat = _positionToBeat(position.dy, context.size?.height ?? 1);
      _dragLastX = _positionToLaneX(position.dx, context.size?.width ?? 1);
    } else {
      _draggingNoteId = null;
      if (widget.mode == EditorMode.select && hit == null) {
        _selectingRect = true;
        _selectStart = position;
        _selectEnd = position;
      }
    }
  }

  void _handleScaleUpdate(Offset position, ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      final nextVisible = (_scaleStartVisibleBeats / details.scale).clamp(
        _minVisibleBeats,
        _maxVisibleBeats,
      );
      widget.onVisibleBeatsChanged(nextVisible.toDouble());
      final nextView = max(
        0.0,
        widget.viewBeat + details.focalPointDelta.dy * 0.03,
      );
      widget.onViewBeatChanged(nextView);
      return;
    }

    if (_selectingRect) {
      setState(() {
        _selectEnd = position;
      });
      return;
    }

    if (_draggingNoteId != null) {
      final beat = _positionToBeat(position.dy, context.size?.height ?? 1);
      final x = _positionToLaneX(position.dx, context.size?.width ?? 1);
      if (widget.selectedIds.length == 1) {
        widget.onMoveSelected(beat, x);
      } else {
        final beatDelta = beat - _dragLastBeat;
        final xDelta = x - _dragLastX;
        if (beatDelta.abs() > 0.0001 || xDelta != 0) {
          widget.onMoveSelectedDelta(beatDelta, xDelta);
          _dragLastBeat = beat;
          _dragLastX = x;
        }
      }
      return;
    }

    final next = max(0.0, widget.viewBeat + details.focalPointDelta.dy * 0.03);
    widget.onViewBeatChanged(next);
  }

  void _handleScaleEnd() {
    if (_selectingRect && _selectStart != null && _selectEnd != null) {
      final start = _selectStart!;
      final end = _selectEnd!;
      final startBeat = _positionToBeat(start.dy, context.size?.height ?? 1);
      final endBeat = _positionToBeat(end.dy, context.size?.height ?? 1);
      final startX = _positionToLaneX(start.dx, context.size?.width ?? 1);
      final endX = _positionToLaneX(end.dx, context.size?.width ?? 1);
      widget.onSelectRegion(
        startBeat: startBeat,
        endBeat: endBeat,
        startX: startX,
        endX: endX,
      );
    }
    setState(() {
      _draggingNoteId = null;
      _selectingRect = false;
      _selectStart = null;
      _selectEnd = null;
    });
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
    final ratio = ((beat - widget.viewBeat) / widget.visibleBeats).clamp(
      0.0,
      1.0,
    );
    return height - ratio * height;
  }

  double _positionToBeat(double y, double height) {
    if (height <= 1) {
      return widget.viewBeat;
    }
    final ratio = (1.0 - (y / height)).clamp(0.0, 1.0);
    return widget.viewBeat + ratio * widget.visibleBeats;
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
    required this.timeDivision,
    required this.viewBeat,
    required this.playheadBeat,
    required this.visibleBeats,
    required this.selectStart,
    required this.selectEnd,
    required this.selectingRect,
  });

  final List<CoreNoteSnapshot> notes;
  final Set<String> selectedIds;
  final int timeDivision;
  final double viewBeat;
  final double playheadBeat;
  final double visibleBeats;
  final Offset? selectStart;
  final Offset? selectEnd;
  final bool selectingRect;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF151A23);
    canvas.drawRect(Offset.zero & size, bg);

    final normalizedDivision = timeDivision.clamp(1, 96);
    final horizontalDivisions = max(
      8,
      (visibleBeats * normalizedDivision).round().clamp(8, 256),
    );
    for (var i = 0; i <= horizontalDivisions; i++) {
      final y = size.height * i / horizontalDivisions;
      final isMajor = i % normalizedDivision == 0;
      final grid = Paint()
        ..color = isMajor ? const Color(0xFF3A475B) : const Color(0xFF2A3444)
        ..strokeWidth = isMajor ? 1.2 : 1;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final referenceY = size.height * 0.8;
    final referencePaint = Paint()
      ..color = const Color(0xFF5B6D86)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, referenceY),
      Offset(size.width, referenceY),
      referencePaint,
    );

    final laneGrid = Paint()
      ..color = const Color(0xFF2A3444)
      ..strokeWidth = 1;
    for (var i = 0; i <= 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), laneGrid);
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

    final playheadRatio = ((playheadBeat - viewBeat) / visibleBeats).clamp(
      0.0,
      1.0,
    );
    final playheadY = size.height - playheadRatio * size.height;
    final playheadLine = Paint()
      ..color = const Color(0xFFFF7A59)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(0, playheadY),
      Offset(size.width, playheadY),
      playheadLine,
    );

    if (selectingRect && selectStart != null && selectEnd != null) {
      final rect = Rect.fromPoints(selectStart!, selectEnd!);
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0x334FC3F7),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xFF4FC3F7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.selectedIds != selectedIds ||
        oldDelegate.timeDivision != timeDivision ||
        oldDelegate.viewBeat != viewBeat ||
        oldDelegate.visibleBeats != visibleBeats ||
        oldDelegate.playheadBeat != playheadBeat ||
        oldDelegate.selectStart != selectStart ||
        oldDelegate.selectEnd != selectEnd ||
        oldDelegate.selectingRect != selectingRect;
  }
}
