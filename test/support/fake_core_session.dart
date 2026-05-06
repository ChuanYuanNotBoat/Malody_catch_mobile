import 'package:malody_catch_mobile/core/core_session.dart';
import 'package:malody_catch_mobile/core/native_core.dart';

class FakeCoreSession implements CoreSessionPort {
  final List<CoreNoteSnapshot> _notes = <CoreNoteSnapshot>[];
  final List<CoreBpmSnapshot> _bpms = <CoreBpmSnapshot>[
    const CoreBpmSnapshot(
      beat: CoreBeat(measure: 0, numerator: 0, denominator: 1),
      bpm: 120,
    ),
  ];
  CoreMetadataSnapshot _metadata = CoreMetadataSnapshot.empty();
  bool _closed = false;
  bool _canUndo = false;
  bool _canRedo = false;
  String _lastError = '';
  int _lastErrorCode = 0;
  String _lastErrorName = 'none';
  int _revision = 0;

  @override
  bool get isClosed => _closed;

  @override
  String get lastError => _lastError;

  @override
  String get lastErrorDetails => _lastError.isEmpty
      ? 'none(0)'
      : '$_lastErrorName($_lastErrorCode): $_lastError';

  @override
  int get lastErrorCode => _lastErrorCode;

  @override
  String get lastErrorName => _lastErrorName;

  @override
  int get noteCount => _notes.length;

  @override
  int get chartRevision => _revision;

  @override
  int get bpmCount => _bpms.length;

  @override
  CoreChartSummary? chartSummary() {
    return CoreChartSummary(
      noteCount: _notes.length,
      bpmCount: _bpms.length,
      revision: _revision,
      canUndo: _canUndo,
      canRedo: _canRedo,
      title: _metadata.title,
      artist: _metadata.artist,
      difficulty: _metadata.difficulty,
    );
  }

  @override
  CoreNoteSnapshot? noteSnapshot(int index) {
    if (index < 0 || index >= _notes.length) {
      return null;
    }
    return _notes[index];
  }

  @override
  List<CoreNoteSnapshot> noteSnapshots({
    required int startIndex,
    required int maxCount,
  }) {
    if (startIndex < 0 || startIndex >= _notes.length || maxCount <= 0) {
      return const <CoreNoteSnapshot>[];
    }
    final end = (startIndex + maxCount).clamp(0, _notes.length);
    return _notes.sublist(startIndex, end);
  }

  @override
  CoreBpmSnapshot? bpmSnapshot(int index) {
    if (index < 0 || index >= _bpms.length) {
      return null;
    }
    return _bpms[index];
  }

  @override
  List<CoreBpmSnapshot> bpmSnapshots() => List<CoreBpmSnapshot>.from(_bpms);

  @override
  CoreMetadataSnapshot? metadataSnapshot() => _metadata;

  @override
  bool setMetadata(CoreMetadataSnapshot metadata) {
    _metadata = metadata;
    _markChanged();
    return true;
  }

  @override
  bool addBpm({required CoreBeat beat, required double bpm}) {
    _bpms.add(CoreBpmSnapshot(beat: beat, bpm: bpm));
    _markChanged();
    return true;
  }

  @override
  bool updateBpm({
    required int index,
    required CoreBeat beat,
    required double bpm,
  }) {
    if (index < 0 || index >= _bpms.length) {
      _setMockError('bpm_index', 3, 'out_of_range');
      return false;
    }
    _bpms[index] = CoreBpmSnapshot(beat: beat, bpm: bpm);
    _markChanged();
    return true;
  }

  @override
  bool removeBpm(int index) {
    if (index < 0 || index >= _bpms.length) {
      _setMockError('bpm_index', 3, 'out_of_range');
      return false;
    }
    _bpms.removeAt(index);
    _markChanged();
    return true;
  }

  @override
  bool addNormalNote({
    required String id,
    required int measure,
    required int numerator,
    required int denominator,
    required int x,
  }) {
    _notes.add(
      CoreNoteSnapshot(
        id: id,
        type: 0,
        beat: CoreBeat(
          measure: measure,
          numerator: numerator,
          denominator: denominator,
        ),
        endBeat: CoreBeat(
          measure: measure,
          numerator: numerator,
          denominator: denominator,
        ),
        x: x,
        sound: '',
        volume: 100,
        offsetMs: 0,
      ),
    );
    _markChanged();
    return true;
  }

  @override
  bool addRainNote({
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    _notes.add(
      CoreNoteSnapshot(
        id: id,
        type: 3,
        beat: beat,
        endBeat: endBeat,
        x: x,
        sound: '',
        volume: 100,
        offsetMs: 0,
      ),
    );
    _markChanged();
    return true;
  }

  @override
  bool moveRainNote({
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    final index = _notes.indexWhere((n) => n.id == id && n.type == 3);
    if (index < 0) {
      _setMockError('not_found', 5, 'not_found');
      return false;
    }
    _notes[index] = CoreNoteSnapshot(
      id: _notes[index].id,
      type: 3,
      beat: beat,
      endBeat: endBeat,
      x: x,
      sound: '',
      volume: 100,
      offsetMs: 0,
    );
    _markChanged();
    return true;
  }

  @override
  bool addSoundNote({
    required String id,
    required CoreBeat beat,
    required String sound,
    required int volume,
    required int offsetMs,
  }) {
    _notes.add(
      CoreNoteSnapshot(
        id: id,
        type: 1,
        beat: beat,
        endBeat: beat,
        x: -1,
        sound: sound,
        volume: volume,
        offsetMs: offsetMs,
      ),
    );
    _markChanged();
    return true;
  }

  @override
  bool removeNoteById(String id) {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index < 0) {
      _setMockError('not_found', 5, 'not_found');
      return false;
    }
    _notes.removeAt(index);
    _markChanged();
    return true;
  }

  @override
  bool applyNoteBatch(List<CoreNoteBatchOp> operations) {
    for (final op in operations) {
      if (op.opType == CoreNoteBatchOpType.add) {
        _notes.add(op.note);
      } else if (op.opType == CoreNoteBatchOpType.remove) {
        _notes.removeWhere((n) => n.id == op.note.id);
      } else if (op.opType == CoreNoteBatchOpType.move) {
        final idx = _notes.indexWhere((n) => n.id == op.note.id);
        if (idx >= 0) {
          _notes[idx] = op.note;
        }
      }
    }
    _markChanged();
    return true;
  }

  @override
  bool get canUndo => _canUndo;

  @override
  bool get canRedo => _canRedo;

  @override
  bool undo() {
    if (!_canUndo) {
      _setMockError('cannot_undo', 6, 'operation_failed');
      return false;
    }
    _canUndo = false;
    _canRedo = true;
    _revision += 1;
    return true;
  }

  @override
  bool redo() {
    if (!_canRedo) {
      _setMockError('cannot_redo', 6, 'operation_failed');
      return false;
    }
    _canRedo = false;
    _canUndo = true;
    _revision += 1;
    return true;
  }

  void _markChanged() {
    _setMockError('', 0, 'none');
    _canUndo = true;
    _canRedo = false;
    _revision += 1;
  }

  void _setMockError(String message, int code, String name) {
    _lastError = message;
    _lastErrorCode = code;
    _lastErrorName = name;
  }

  @override
  void close() {
    _closed = true;
  }
}
