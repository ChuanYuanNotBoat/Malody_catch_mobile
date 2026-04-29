import 'package:flutter_test/flutter_test.dart';
import 'package:malody_catch_mobile/core/chart_document_controller.dart';
import 'package:malody_catch_mobile/core/core_session.dart';
import 'package:malody_catch_mobile/core/native_core.dart';

class FakeCoreSession implements CoreSessionPort {
  final List<CoreNoteSnapshot> _notes = <CoreNoteSnapshot>[];
  bool _closed = false;
  bool _canUndo = false;
  bool _canRedo = false;
  String _lastError = '';
  int _revision = 0;

  @override
  bool get isClosed => _closed;

  @override
  String get lastError => _lastError;

  @override
  String get lastErrorDetails =>
      _lastError.isEmpty ? 'none(0)' : 'mock(6): $_lastError';

  @override
  int get noteCount => _notes.length;

  @override
  int get chartRevision => _revision;

  @override
  CoreChartSummary? chartSummary() {
    return CoreChartSummary(
      noteCount: _notes.length,
      bpmCount: 1,
      revision: _revision,
      canUndo: _canUndo,
      canRedo: _canRedo,
      title: '',
      artist: '',
      difficulty: '',
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
  bool addNormalNote({
    required String id,
    required int measure,
    required int numerator,
    required int denominator,
    required int x,
  }) {
    if (_closed) {
      _lastError = 'closed';
      return false;
    }
    if (x < 0 || x > 512) {
      _lastError = 'invalid_x';
      return false;
    }
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
    _lastError = '';
    _canUndo = true;
    _canRedo = false;
    _revision += 1;
    return true;
  }

  @override
  bool addRainNote({
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    if (_closed) {
      _lastError = 'closed';
      return false;
    }
    if (x < 0 || x > 512) {
      _lastError = 'invalid_x';
      return false;
    }
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
    _lastError = '';
    _canUndo = true;
    _canRedo = false;
    _revision += 1;
    return true;
  }

  @override
  bool moveRainNote({
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    if (_closed) {
      _lastError = 'closed';
      return false;
    }
    final index = _notes.indexWhere((n) => n.id == id && n.type == 3);
    if (index < 0) {
      _lastError = 'not_found';
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
    _lastError = '';
    _canUndo = true;
    _canRedo = false;
    _revision += 1;
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
    if (_closed) {
      _lastError = 'closed';
      return false;
    }
    if (sound.isEmpty) {
      _lastError = 'invalid_sound';
      return false;
    }
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
    _lastError = '';
    _canUndo = true;
    _canRedo = false;
    _revision += 1;
    return true;
  }

  @override
  bool removeNoteById(String id) {
    if (_closed) {
      _lastError = 'closed';
      return false;
    }
    final index = _notes.indexWhere((n) => n.id == id);
    if (index < 0) {
      _lastError = 'not_found';
      return false;
    }
    _notes.removeAt(index);
    _lastError = '';
    _canUndo = true;
    _canRedo = false;
    _revision += 1;
    return true;
  }

  @override
  bool get canUndo => _canUndo;

  @override
  bool get canRedo => _canRedo;

  @override
  bool undo() {
    if (!_canUndo) {
      _lastError = 'cannot_undo';
      return false;
    }
    _canUndo = false;
    _canRedo = true;
    _lastError = '';
    _revision += 1;
    return true;
  }

  @override
  bool redo() {
    if (!_canRedo) {
      _lastError = 'cannot_redo';
      return false;
    }
    _canRedo = false;
    _canUndo = true;
    _lastError = '';
    _revision += 1;
    return true;
  }

  @override
  void close() {
    _closed = true;
  }
}

void main() {
  test('controller open/add/select/remove flow', () {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    controller.openSession();
    expect(controller.sessionOpen, isTrue);
    expect(controller.dirty, isFalse);

    controller.addNormalNote(measure: 1, numerator: 0, denominator: 1, x: 128);

    expect(controller.notes.length, 1);
    expect(controller.dirty, isTrue);

    final id = controller.notes.first.id;
    controller.selectSingle(id);
    expect(controller.selectedNoteIds.contains(id), isTrue);

    controller.removeNoteById(id);
    expect(controller.notes, isEmpty);
  });

  test('controller handles failures and keeps error text', () {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    controller.openSession();
    controller.addNormalNote(measure: 1, numerator: 0, denominator: 1, x: 999);

    expect(controller.notes.length, 0);
    expect(controller.lastError, isNotEmpty);
    expect(controller.lastError, contains('mock(6):'));
  });

  test('controller mode and draft roundtrip', () {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    controller.openSession();
    controller.setEditorMode(EditorMode.delete);
    expect(controller.editorMode, EditorMode.delete);

    controller.addNormalNote(measure: 2, numerator: 0, denominator: 1, x: 160);
    final originalId = controller.notes.first.id;
    controller.selectSingle(originalId);
    controller.saveDraftToMemory();
    expect(controller.hasDraft, isTrue);

    controller.closeSession();
    expect(controller.sessionOpen, isFalse);

    controller.restoreDraftFromMemory();
    expect(controller.sessionOpen, isTrue);
    expect(controller.notes.length, 1);
    expect(controller.notes.first.id, originalId);
    expect(controller.selectedNoteIds.contains(originalId), isTrue);
    expect(controller.editorMode, EditorMode.delete);
  });

  test('controller supports rain add/move and sound add', () {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    controller.openSession();

    controller.addRainNote(
      beat: const CoreBeat(measure: 1, numerator: 0, denominator: 1),
      endBeat: const CoreBeat(measure: 1, numerator: 1, denominator: 1),
      x: 192,
    );
    controller.addSoundNote(
      beat: const CoreBeat(measure: 2, numerator: 0, denominator: 1),
      sound: 'sfx/tap.wav',
      volume: 80,
      offsetMs: 12,
    );

    expect(controller.notes.length, 2);
    final rain = controller.notes.firstWhere((n) => n.type == 3);
    controller.selectSingle(rain.id);
    controller.moveSelectedRainNote(
      beat: const CoreBeat(measure: 3, numerator: 0, denominator: 1),
      endBeat: const CoreBeat(measure: 3, numerator: 1, denominator: 1),
      x: 256,
    );

    final moved = controller.notes.firstWhere((n) => n.id == rain.id);
    expect(moved.beat.measure, 3);
    expect(moved.x, 256);
    expect(controller.lastError, isEmpty);
  });
}
