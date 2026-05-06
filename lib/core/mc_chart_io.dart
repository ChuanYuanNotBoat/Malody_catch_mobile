import 'dart:convert';

import 'native_core.dart';

class ParsedMcChart {
  const ParsedMcChart({
    required this.metadata,
    required this.bpms,
    required this.notes,
  });

  final CoreMetadataSnapshot metadata;
  final List<CoreBpmSnapshot> bpms;
  final List<CoreNoteSnapshot> notes;
}

class McChartIo {
  static ParsedMcChart parse(String source) {
    final dynamic decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid chart json root.');
    }

    final metaMap = (decoded['meta'] is Map<String, dynamic>)
        ? decoded['meta'] as Map<String, dynamic>
        : <String, dynamic>{};
    final song = (metaMap['song'] is Map<String, dynamic>)
        ? metaMap['song'] as Map<String, dynamic>
        : <String, dynamic>{};
    final modeExt = (metaMap['mode_ext'] is Map<String, dynamic>)
        ? metaMap['mode_ext'] as Map<String, dynamic>
        : <String, dynamic>{};

    final metadata = CoreMetadataSnapshot(
      title: (song['title'] ?? metaMap['title'] ?? '').toString(),
      titleOriginal: (song['titleorg'] ?? metaMap['title_org'] ?? '')
          .toString(),
      artist: (song['artist'] ?? metaMap['artist'] ?? '').toString(),
      artistOriginal: (metaMap['artist_org'] ?? '').toString(),
      difficulty: (metaMap['version'] ?? 'Normal').toString(),
      chartAuthor: (metaMap['creator'] ?? '').toString(),
      audioFile: (metaMap['audio'] ?? '').toString(),
      backgroundFile: (metaMap['background'] ?? '').toString(),
      previewTimeMs: _asInt(metaMap['preview']),
      firstBpm: _asDouble(metaMap['bpm'], fallback: 120.0),
      offsetMs: _asInt(metaMap['offset']),
      speed: _asInt(modeExt['speed'], fallback: 100),
    );

    final bpms = <CoreBpmSnapshot>[];
    if (decoded['time'] is List) {
      final list = decoded['time'] as List<dynamic>;
      for (final entry in list) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        final beat = _parseBeat(entry['beat']);
        if (beat == null) {
          continue;
        }
        bpms.add(
          CoreBpmSnapshot(
            beat: beat,
            bpm: _asDouble(entry['bpm'], fallback: 120.0),
          ),
        );
      }
    }
    if (bpms.isEmpty) {
      bpms.add(
        CoreBpmSnapshot(
          beat: const CoreBeat(measure: 0, numerator: 0, denominator: 1),
          bpm: metadata.firstBpm <= 0 ? 120.0 : metadata.firstBpm,
        ),
      );
    }

    final notes = <CoreNoteSnapshot>[];
    if (decoded['note'] is List) {
      final list = decoded['note'] as List<dynamic>;
      for (var i = 0; i < list.length; i++) {
        final raw = list[i];
        if (raw is! Map<String, dynamic>) {
          continue;
        }
        final beat = _parseBeat(raw['beat']);
        if (beat == null) {
          continue;
        }
        final type = _asInt(raw['type']);
        final endBeat = _parseBeat(raw['endbeat']) ?? beat;
        final sound = (raw['sound'] ?? '').toString();
        final x = _asInt(raw['x'], fallback: type == 1 ? -1 : 256);
        notes.add(
          CoreNoteSnapshot(
            id: 'imported-$i',
            type: type,
            beat: beat,
            endBeat: endBeat,
            x: x,
            sound: sound,
            volume: _asInt(raw['vol'], fallback: 100),
            offsetMs: _asInt(raw['offset']),
          ),
        );
      }
    }

    return ParsedMcChart(metadata: metadata, bpms: bpms, notes: notes);
  }

  static String encode({
    required CoreMetadataSnapshot metadata,
    required List<CoreBpmSnapshot> bpms,
    required List<CoreNoteSnapshot> notes,
  }) {
    final root = <String, dynamic>{};

    root['meta'] = {
      r'$ver': 0,
      'creator': metadata.chartAuthor,
      'background': metadata.backgroundFile,
      'version': metadata.difficulty,
      'id': 0,
      'mode': 3,
      'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'song': {
        'title': metadata.title,
        'artist': metadata.artist,
        'id': 0,
        'titleorg': metadata.titleOriginal,
      },
      'mode_ext': {'speed': metadata.speed},
      if (metadata.audioFile.isNotEmpty) 'audio': metadata.audioFile,
      if (metadata.previewTimeMs != 0) 'preview': metadata.previewTimeMs,
      if (metadata.offsetMs != 0) 'offset': metadata.offsetMs,
      if (metadata.firstBpm > 0) 'bpm': metadata.firstBpm,
    };

    root['time'] = bpms
        .map(
          (bpm) => {
            'beat': [
              bpm.beat.measure,
              bpm.beat.numerator,
              bpm.beat.denominator,
            ],
            'bpm': bpm.bpm,
          },
        )
        .toList();

    root['effect'] = <dynamic>[];

    root['note'] = notes.map((note) {
      final obj = <String, dynamic>{
        'beat': [note.beat.measure, note.beat.numerator, note.beat.denominator],
      };
      if (note.type == 1) {
        obj['type'] = 1;
        obj['sound'] = note.sound;
        obj['vol'] = note.volume;
        obj['offset'] = note.offsetMs;
      } else if (note.type == 3) {
        obj['type'] = 3;
        obj['x'] = note.x;
        obj['endbeat'] = [
          note.endBeat.measure,
          note.endBeat.numerator,
          note.endBeat.denominator,
        ];
      } else {
        obj['x'] = note.x;
      }
      return obj;
    }).toList();

    root['extra'] = {
      'test': {'divide': 4, 'speed': 100, 'save': 0, 'lock': 0, 'edit_mode': 0},
    };

    return const JsonEncoder.withIndent('  ').convert(root);
  }

  static CoreBeat? _parseBeat(dynamic raw) {
    if (raw is! List || raw.length < 3) {
      return null;
    }
    return CoreBeat(
      measure: _asInt(raw[0]),
      numerator: _asInt(raw[1]),
      denominator: _asInt(raw[2], fallback: 1),
    );
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }
}
