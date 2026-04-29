import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'core_session.dart';
import 'native_core.dart';

class ChartDocumentController extends ChangeNotifier {
  ChartDocumentController({CoreSessionFactory? sessionFactory})
    : _sessionFactory = sessionFactory ?? CoreSession.open;

  final CoreSessionFactory _sessionFactory;

  CoreStartupReport? _startupReport;
  CoreSessionPort? _session;
  String? _currentFilePath;
  bool _dirty = false;
  int _revision = 0;
  int _cacheRevision = -1;
  final List<CoreNoteSnapshot> _cachedNotes = <CoreNoteSnapshot>[];
  final Set<String> _selectedNoteIds = <String>{};
  String _lastEventLog = '';
  String _lastError = '';
  int _noteIdSeed = 0;

  CoreStartupReport? get startupReport => _startupReport;
  bool get sessionOpen => _session != null;
  String? get currentFilePath => _currentFilePath;
  bool get dirty => _dirty;
  int get revision => _revision;
  String get lastEventLog => _lastEventLog;
  String get lastError => _lastError;
  bool get canUndo => _session?.canUndo ?? false;
  bool get canRedo => _session?.canRedo ?? false;

  UnmodifiableListView<CoreNoteSnapshot> get notes {
    _refreshSnapshotsIfNeeded();
    return UnmodifiableListView<CoreNoteSnapshot>(_cachedNotes);
  }

  UnmodifiableSetView<String> get selectedNoteIds {
    return UnmodifiableSetView<String>(_selectedNoteIds);
  }

  void runStartupSelfCheck() {
    _startupReport = CoreSession.startupSelfCheck();
    _lastEventLog = _startupReport!.success
        ? 'startup_check_ok'
        : 'startup_check_failed';
    _lastError = _startupReport!.errorMessage ?? '';
    notifyListeners();
  }

  void openSession({String? filePath}) {
    try {
      _session?.close();
      _session = _sessionFactory();
      _currentFilePath = filePath;
      _dirty = false;
      _revision = 0;
      _cacheRevision = -1;
      _cachedNotes.clear();
      _selectedNoteIds.clear();
      _lastError = '';
      _lastEventLog = 'session_opened';
    } catch (e) {
      _session = null;
      _lastError = e.toString();
      _lastEventLog = 'session_open_failed';
    }
    notifyListeners();
  }

  void closeSession() {
    _session?.close();
    _session = null;
    _dirty = false;
    _currentFilePath = null;
    _revision = 0;
    _cacheRevision = -1;
    _cachedNotes.clear();
    _selectedNoteIds.clear();
    _lastError = '';
    _lastEventLog = 'session_closed';
    notifyListeners();
  }

  void addNormalNote({
    required int measure,
    required int numerator,
    required int denominator,
    required int x,
  }) {
    final session = _session;
    if (session == null) {
      _setFailure('add_note_skipped', 'session_not_open');
      return;
    }

    _noteIdSeed += 1;
    final id = 'mobile-note-$_noteIdSeed';
    final ok = session.addNormalNote(
      id: id,
      measure: measure,
      numerator: numerator,
      denominator: denominator,
      x: x,
    );
    if (!ok) {
      _setFailure('add_note_failed', session.lastError);
      return;
    }

    _markChanged('add_note_ok:$id');
  }

  void removeNoteById(String id) {
    final session = _session;
    if (session == null) {
      _setFailure('remove_note_skipped', 'session_not_open');
      return;
    }

    final ok = session.removeNoteById(id);
    if (!ok) {
      _setFailure('remove_note_failed', session.lastError);
      return;
    }

    _selectedNoteIds.remove(id);
    _markChanged('remove_note_ok:$id');
  }

  void removeLastNote() {
    _refreshSnapshotsIfNeeded();
    if (_cachedNotes.isEmpty) {
      _setFailure('remove_last_skipped', 'no_notes');
      return;
    }
    removeNoteById(_cachedNotes.last.id);
  }

  void undo() {
    final session = _session;
    if (session == null) {
      _setFailure('undo_skipped', 'session_not_open');
      return;
    }
    final ok = session.undo();
    if (!ok) {
      _setFailure('undo_failed', session.lastError);
      return;
    }
    _revision += 1;
    _dirty = true;
    _cacheRevision = -1;
    _selectedNoteIds.removeWhere((id) => !_containsNoteId(id));
    _lastError = '';
    _lastEventLog = 'undo_ok';
    notifyListeners();
  }

  void redo() {
    final session = _session;
    if (session == null) {
      _setFailure('redo_skipped', 'session_not_open');
      return;
    }
    final ok = session.redo();
    if (!ok) {
      _setFailure('redo_failed', session.lastError);
      return;
    }
    _revision += 1;
    _dirty = true;
    _cacheRevision = -1;
    _selectedNoteIds.removeWhere((id) => !_containsNoteId(id));
    _lastError = '';
    _lastEventLog = 'redo_ok';
    notifyListeners();
  }

  void selectSingle(String id) {
    if (!_containsNoteId(id)) {
      _setFailure('select_failed', 'note_not_found:$id');
      return;
    }
    _selectedNoteIds
      ..clear()
      ..add(id);
    _lastError = '';
    _lastEventLog = 'select_ok:$id';
    notifyListeners();
  }

  void clearSelection() {
    _selectedNoteIds.clear();
    _lastError = '';
    _lastEventLog = 'selection_cleared';
    notifyListeners();
  }

  @override
  void dispose() {
    _session?.close();
    _session = null;
    super.dispose();
  }

  void _markChanged(String event) {
    _dirty = true;
    _revision += 1;
    _cacheRevision = -1;
    _lastError = '';
    _lastEventLog = event;
    notifyListeners();
  }

  void _setFailure(String event, String error) {
    _lastEventLog = event;
    _lastError = error;
    notifyListeners();
  }

  bool _containsNoteId(String id) {
    _refreshSnapshotsIfNeeded();
    for (final note in _cachedNotes) {
      if (note.id == id) {
        return true;
      }
    }
    return false;
  }

  void _refreshSnapshotsIfNeeded() {
    final session = _session;
    if (session == null) {
      _cachedNotes.clear();
      _cacheRevision = _revision;
      return;
    }
    if (_cacheRevision == _revision) {
      return;
    }

    final count = session.noteCount;
    final refreshed = <CoreNoteSnapshot>[];
    for (var i = 0; i < count; i++) {
      final note = session.noteSnapshot(i);
      if (note != null) {
        refreshed.add(note);
      }
    }
    _cachedNotes
      ..clear()
      ..addAll(refreshed);
    _cacheRevision = _revision;
  }
}
