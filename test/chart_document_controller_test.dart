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

  @override
  bool get isClosed => _closed;

  @override
  String get lastError => _lastError;

  @override
  int get noteCount => _notes.length;

  @override
  CoreNoteSnapshot? noteSnapshot(int index) {
    if (index < 0 || index >= _notes.length) {
      return null;
    }
    return _notes[index];
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
  });
}
