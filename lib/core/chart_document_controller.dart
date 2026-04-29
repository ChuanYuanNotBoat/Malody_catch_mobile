import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'core_session.dart';
import 'native_core.dart';

enum EditorMode { placeNormal, placeRain, delete, select, move }

class _DraftState {
  const _DraftState({
    required this.filePath,
    required this.notes,
    required this.selectedIds,
    required this.dirty,
    required this.revision,
    required this.mode,
  });

  final String? filePath;
  final List<CoreNoteSnapshot> notes;
  final Set<String> selectedIds;
  final bool dirty;
  final int revision;
  final EditorMode mode;
}

class ChartDocumentController extends ChangeNotifier {
  ChartDocumentController({CoreSessionFactory? sessionFactory})
    : _sessionFactory = sessionFactory ?? CoreSession.open;

  static const int _noteTypeNormal = 0;
  static const int _noteTypeSound = 1;
  static const int _noteTypeRain = 3;
  static const int _snapshotBatchSize = 128;

  final CoreSessionFactory _sessionFactory;
  static _DraftState? _memoryDraft;

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
  EditorMode _editorMode = EditorMode.select;

  CoreStartupReport? get startupReport => _startupReport;
  bool get sessionOpen => _session != null;
  String? get currentFilePath => _currentFilePath;
  bool get dirty => _dirty;
  int get revision => _revision;
  String get lastEventLog => _lastEventLog;
  String get lastError => _lastError;
  bool get canUndo => _session?.canUndo ?? false;
  bool get canRedo => _session?.canRedo ?? false;
  EditorMode get editorMode => _editorMode;
  bool get hasDraft => _memoryDraft != null;

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
      _cacheRevision = -1;
      _cachedNotes.clear();
      _selectedNoteIds.clear();
      _lastError = '';
      _syncRevisionFromCore();
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

  void setEditorMode(EditorMode mode) {
    if (_editorMode == mode) {
      return;
    }
    _editorMode = mode;
    _lastError = '';
    _lastEventLog = 'mode_set:${mode.name}';
    notifyListeners();
  }

  void handleNoteTap(String id) {
    switch (_editorMode) {
      case EditorMode.delete:
        removeNoteById(id);
        return;
      case EditorMode.select:
        toggleSelection(id);
        return;
      case EditorMode.placeNormal:
      case EditorMode.placeRain:
      case EditorMode.move:
        selectSingle(id);
        _lastEventLog = 'note_tap:${_editorMode.name}:$id';
        notifyListeners();
        return;
    }
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
      _setFailure('add_note_failed', session.lastErrorDetails);
      return;
    }

    _markChanged('add_note_ok:$id');
  }

  void addRainNote({
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    final session = _session;
    if (session == null) {
      _setFailure('add_rain_skipped', 'session_not_open');
      return;
    }

    _noteIdSeed += 1;
    final id = 'mobile-rain-$_noteIdSeed';
    final ok = session.addRainNote(id: id, beat: beat, endBeat: endBeat, x: x);
    if (!ok) {
      _setFailure('add_rain_failed', session.lastErrorDetails);
      return;
    }

    _markChanged('add_rain_ok:$id');
  }

  void moveSelectedRainNote({
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    final session = _session;
    if (session == null) {
      _setFailure('move_rain_skipped', 'session_not_open');
      return;
    }
    if (_selectedNoteIds.length != 1) {
      _setFailure('move_rain_skipped', 'select_single_rain_note');
      return;
    }

    final id = _selectedNoteIds.first;
    final note = _findNoteById(id);
    if (note == null) {
      _setFailure('move_rain_failed', 'note_not_found:$id');
      return;
    }
    if (note.type != _noteTypeRain) {
      _setFailure('move_rain_failed', 'note_not_rain:$id');
      return;
    }

    final ok = session.moveRainNote(id: id, beat: beat, endBeat: endBeat, x: x);
    if (!ok) {
      _setFailure('move_rain_failed', session.lastErrorDetails);
      return;
    }

    _markChanged('move_rain_ok:$id');
  }

  void addSoundNote({
    required CoreBeat beat,
    required String sound,
    int volume = 100,
    int offsetMs = 0,
  }) {
    final session = _session;
    if (session == null) {
      _setFailure('add_sound_skipped', 'session_not_open');
      return;
    }

    _noteIdSeed += 1;
    final id = 'mobile-sound-$_noteIdSeed';
    final ok = session.addSoundNote(
      id: id,
      beat: beat,
      sound: sound,
      volume: volume,
      offsetMs: offsetMs,
    );
    if (!ok) {
      _setFailure('add_sound_failed', session.lastErrorDetails);
      return;
    }

    _markChanged('add_sound_ok:$id');
  }

  void removeNoteById(String id) {
    final session = _session;
    if (session == null) {
      _setFailure('remove_note_skipped', 'session_not_open');
      return;
    }

    final ok = session.removeNoteById(id);
    if (!ok) {
      _setFailure('remove_note_failed', session.lastErrorDetails);
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
      _setFailure('undo_failed', session.lastErrorDetails);
      return;
    }
    _markChanged('undo_ok');
  }

  void redo() {
    final session = _session;
    if (session == null) {
      _setFailure('redo_skipped', 'session_not_open');
      return;
    }
    final ok = session.redo();
    if (!ok) {
      _setFailure('redo_failed', session.lastErrorDetails);
      return;
    }
    _markChanged('redo_ok');
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

  void toggleSelection(String id) {
    if (!_containsNoteId(id)) {
      _setFailure('toggle_select_failed', 'note_not_found:$id');
      return;
    }
    if (_selectedNoteIds.contains(id)) {
      _selectedNoteIds.remove(id);
    } else {
      _selectedNoteIds.add(id);
    }
    _lastError = '';
    _lastEventLog = 'toggle_select_ok:$id';
    notifyListeners();
  }

  void clearSelection() {
    _selectedNoteIds.clear();
    _lastError = '';
    _lastEventLog = 'selection_cleared';
    notifyListeners();
  }

  void saveDraftToMemory() {
    _refreshSnapshotsIfNeeded();
    _memoryDraft = _DraftState(
      filePath: _currentFilePath,
      notes: List<CoreNoteSnapshot>.from(_cachedNotes),
      selectedIds: Set<String>.from(_selectedNoteIds),
      dirty: _dirty,
      revision: _revision,
      mode: _editorMode,
    );
    _lastError = '';
    _lastEventLog = 'draft_saved:${_cachedNotes.length}';
    notifyListeners();
  }

  void restoreDraftFromMemory() {
    final draft = _memoryDraft;
    if (draft == null) {
      _setFailure('draft_restore_failed', 'draft_not_found');
      return;
    }

    try {
      _session?.close();
      final session = _sessionFactory();
      _session = session;
      _currentFilePath = draft.filePath;
      _dirty = draft.dirty;
      _cacheRevision = -1;
      _cachedNotes.clear();
      _selectedNoteIds.clear();
      _editorMode = draft.mode;

      var restored = 0;
      var skipped = 0;
      for (final note in draft.notes) {
        final ok = _restoreNote(session, note);
        if (ok) {
          restored += 1;
        } else {
          skipped += 1;
        }
      }

      _syncRevisionFromCore();
      _refreshSnapshotsIfNeeded();
      _selectedNoteIds.addAll(
        draft.selectedIds.where((id) => _containsNoteId(id)),
      );

      _lastError = '';
      _lastEventLog = 'draft_restored:$restored:$skipped';
      notifyListeners();
    } catch (e) {
      _setFailure('draft_restore_failed', e.toString());
    }
  }

  @override
  void dispose() {
    _session?.close();
    _session = null;
    super.dispose();
  }

  bool _restoreNote(CoreSessionPort session, CoreNoteSnapshot note) {
    switch (note.type) {
      case _noteTypeNormal:
        return session.addNormalNote(
          id: note.id,
          measure: note.beat.measure,
          numerator: note.beat.numerator,
          denominator: note.beat.denominator,
          x: note.x,
        );
      case _noteTypeRain:
        return session.addRainNote(
          id: note.id,
          beat: note.beat,
          endBeat: note.endBeat,
          x: note.x,
        );
      case _noteTypeSound:
        return session.addSoundNote(
          id: note.id,
          beat: note.beat,
          sound: note.sound,
          volume: note.volume,
          offsetMs: note.offsetMs,
        );
      default:
        return false;
    }
  }

  void _markChanged(String event) {
    _dirty = true;
    _cacheRevision = -1;
    _syncRevisionFromCore();
    _selectedNoteIds.removeWhere((id) => !_containsNoteId(id));
    _lastError = '';
    _lastEventLog = event;
    notifyListeners();
  }

  void _setFailure(String event, String error) {
    _lastEventLog = event;
    _lastError = error;
    notifyListeners();
  }

  CoreNoteSnapshot? _findNoteById(String id) {
    _refreshSnapshotsIfNeeded();
    for (final note in _cachedNotes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  bool _containsNoteId(String id) => _findNoteById(id) != null;

  void _syncRevisionFromCore() {
    final session = _session;
    if (session == null) {
      _revision = 0;
      return;
    }
    final summary = session.chartSummary();
    if (summary != null) {
      _revision = summary.revision;
      return;
    }
    _revision = session.chartRevision;
  }

  void _refreshSnapshotsIfNeeded() {
    final session = _session;
    if (session == null) {
      _cachedNotes.clear();
      _cacheRevision = _revision;
      return;
    }

    final coreRevision = session.chartRevision;
    if (_cacheRevision == coreRevision) {
      _revision = coreRevision;
      return;
    }

    final count = session.noteCount;
    final refreshed = <CoreNoteSnapshot>[];
    var cursor = 0;
    while (cursor < count) {
      final take = min(_snapshotBatchSize, count - cursor);
      final batch = session.noteSnapshots(startIndex: cursor, maxCount: take);
      if (batch.isEmpty) {
        break;
      }
      refreshed.addAll(batch);
      cursor += batch.length;
      if (batch.length < take) {
        break;
      }
    }

    if (refreshed.length < count) {
      for (var i = refreshed.length; i < count; i++) {
        final note = session.noteSnapshot(i);
        if (note != null) {
          refreshed.add(note);
        }
      }
    }

    _cachedNotes
      ..clear()
      ..addAll(refreshed);
    _selectedNoteIds.removeWhere(
      (id) => !_cachedNotes.any((note) => note.id == id),
    );
    _revision = coreRevision;
    _cacheRevision = coreRevision;
  }
}
