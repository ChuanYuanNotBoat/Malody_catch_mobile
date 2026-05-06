import 'dart:math';

import 'native_core.dart';

class BeatTimeMapper {
  BeatTimeMapper({required List<CoreBpmSnapshot> bpms, required this.offsetMs})
    : _segments = _buildSegments(bpms);

  final int offsetMs;
  final List<_BeatSegment> _segments;

  static BeatTimeMapper fromChart({
    required List<CoreBpmSnapshot> bpms,
    required int offsetMs,
  }) {
    return BeatTimeMapper(bpms: bpms, offsetMs: offsetMs);
  }

  int beatToMs(double beat) {
    final segment = _segmentForBeat(beat);
    final ms =
        segment.startMs +
        (beat - segment.startBeat) * _msPerBeat(segment.bpm) +
        offsetMs;
    return ms.round();
  }

  double msToBeat(int ms) {
    final localMs = ms - offsetMs;
    final segment = _segmentForMs(localMs.toDouble());
    return segment.startBeat +
        (localMs - segment.startMs) / _msPerBeat(segment.bpm);
  }

  _BeatSegment _segmentForBeat(double beat) {
    for (var i = _segments.length - 1; i >= 0; i--) {
      final segment = _segments[i];
      if (beat >= segment.startBeat) {
        return segment;
      }
    }
    return _segments.first;
  }

  _BeatSegment _segmentForMs(double ms) {
    for (var i = _segments.length - 1; i >= 0; i--) {
      final segment = _segments[i];
      if (ms >= segment.startMs) {
        return segment;
      }
    }
    return _segments.first;
  }

  static List<_BeatSegment> _buildSegments(List<CoreBpmSnapshot> bpms) {
    final normalized = <_BeatPoint>[];
    for (final bpm in bpms) {
      normalized.add(
        _BeatPoint(
          beat: _beatToDouble(bpm.beat),
          bpm: bpm.bpm <= 0 ? 120.0 : bpm.bpm,
        ),
      );
    }
    if (normalized.isEmpty) {
      normalized.add(const _BeatPoint(beat: 0, bpm: 120.0));
    }

    normalized.sort((a, b) => a.beat.compareTo(b.beat));

    final deduped = <_BeatPoint>[];
    for (final point in normalized) {
      if (deduped.isNotEmpty &&
          (point.beat - deduped.last.beat).abs() < 0.0000001) {
        deduped[deduped.length - 1] = point;
      } else {
        deduped.add(point);
      }
    }

    final segments = <_BeatSegment>[];
    var runningMs = deduped.first.beat * _msPerBeat(deduped.first.bpm);
    segments.add(
      _BeatSegment(
        startBeat: deduped.first.beat,
        bpm: deduped.first.bpm,
        startMs: runningMs,
      ),
    );

    for (var i = 1; i < deduped.length; i++) {
      final prev = deduped[i - 1];
      final next = deduped[i];
      runningMs += max(0, next.beat - prev.beat) * _msPerBeat(prev.bpm);
      segments.add(
        _BeatSegment(startBeat: next.beat, bpm: next.bpm, startMs: runningMs),
      );
    }
    return segments;
  }

  static double _beatToDouble(CoreBeat beat) {
    return beat.measure + beat.numerator / max(1, beat.denominator);
  }

  static double _msPerBeat(double bpm) => 60000.0 / (bpm <= 0 ? 120.0 : bpm);
}

class _BeatPoint {
  const _BeatPoint({required this.beat, required this.bpm});

  final double beat;
  final double bpm;
}

class _BeatSegment {
  const _BeatSegment({
    required this.startBeat,
    required this.bpm,
    required this.startMs,
  });

  final double startBeat;
  final double bpm;
  final double startMs;
}
