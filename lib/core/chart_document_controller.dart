import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'core_session.dart';
import 'mc_chart_io.dart';
import 'native_core.dart';
import '../io/chart_archive.dart';
import '../io/chart_workspace.dart';

enum EditorMode { placeNormal, placeRain, delete, select, move }

class MczChartCandidate {
  const MczChartCandidate({
    required this.mcPath,
    required this.relativePath,
    required this.difficulty,
  });

  final String mcPath;
  final String relativePath;
  final String difficulty;
}

typedef MczChartSelectionResolver =
    Future<String?> Function(List<MczChartCandidate> charts);

class _ResolvedResourcePath {
  const _ResolvedResourcePath({
    required this.normalizedReference,
    required this.sourcePath,
    required this.relativePath,
  });

  final String normalizedReference;
  final String sourcePath;
  final String relativePath;
}

class _DraftState {
  const _DraftState({
    required this.filePath,
    required this.notes,
    required this.bpms,
    required this.metadata,
    required this.selectedIds,
    required this.dirty,
    required this.revision,
    required this.mode,
  });

  final String? filePath;
  final List<CoreNoteSnapshot> notes;
  final List<CoreBpmSnapshot> bpms;
  final CoreMetadataSnapshot metadata;
  final Set<String> selectedIds;
  final bool dirty;
  final int revision;
  final EditorMode mode;
}

class ChartDocumentController extends ChangeNotifier {
  ChartDocumentController({CoreSessionFactory? sessionFactory})
    : _sessionFactory = sessionFactory ?? CoreSession.open;

  static const int _noteTypeRain = 3;
  static const int _snapshotBatchSize = 128;
  static const int _recentFileLimit = 12;
  static const String _mczImportEventPrefix = 'mcz_import_';
  static const String _mczExportEventPrefix = 'mcz_export_';

  final CoreSessionFactory _sessionFactory;
  static _DraftState? _memoryDraft;
  static final List<String> _memoryRecentFiles = <String>[];

  CoreStartupReport? _startupReport;
  CoreSessionPort? _session;
  String? _currentFilePath;
  bool _dirty = false;
  int _revision = 0;
  int _cacheRevision = -1;
  final List<CoreNoteSnapshot> _cachedNotes = <CoreNoteSnapshot>[];
  final List<CoreBpmSnapshot> _cachedBpms = <CoreBpmSnapshot>[];
  CoreMetadataSnapshot _cachedMetadata = CoreMetadataSnapshot.empty();
  final Set<String> _selectedNoteIds = <String>{};
  String _lastEventLog = '';
  String _lastError = '';
  int _lastErrorCode = 0;
  String _lastErrorName = 'none';
  int _noteIdSeed = 0;
  EditorMode _editorMode = EditorMode.select;

  CoreStartupReport? get startupReport => _startupReport;
  bool get sessionOpen => _session != null;
  String? get currentFilePath => _currentFilePath;
  bool get dirty => _dirty;
  int get revision => _revision;
  String get lastEventLog => _lastEventLog;
  String get lastError => _lastError;
  int get lastErrorCode => _lastErrorCode;
  String get lastErrorName => _lastErrorName;
  bool get canUndo => _session?.canUndo ?? false;
  bool get canRedo => _session?.canRedo ?? false;
  EditorMode get editorMode => _editorMode;
  bool get hasDraft => _memoryDraft != null;

  UnmodifiableListView<CoreNoteSnapshot> get notes {
    _refreshSnapshotsIfNeeded();
    return UnmodifiableListView<CoreNoteSnapshot>(_cachedNotes);
  }

  UnmodifiableListView<CoreBpmSnapshot> get bpms {
    _refreshSnapshotsIfNeeded();
    return UnmodifiableListView<CoreBpmSnapshot>(_cachedBpms);
  }

  CoreMetadataSnapshot get metadata {
    _refreshSnapshotsIfNeeded();
    return _cachedMetadata;
  }

  UnmodifiableSetView<String> get selectedNoteIds {
    return UnmodifiableSetView<String>(_selectedNoteIds);
  }

  UnmodifiableListView<String> get recentFiles {
    return UnmodifiableListView<String>(_memoryRecentFiles);
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
      _cachedBpms.clear();
      _cachedMetadata = CoreMetadataSnapshot.empty();
      _selectedNoteIds.clear();
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      _syncRevisionFromCore();
      _lastEventLog = 'session_opened';
      _refreshSnapshotsIfNeeded();
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
    _cachedBpms.clear();
    _cachedMetadata = CoreMetadataSnapshot.empty();
    _selectedNoteIds.clear();
    _lastError = '';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
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

  bool openChartFile(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mcz')) {
      _setFailure(
        'open_chart_failed',
        'mcz_fallback_required: please extract .mc from .mcz first.',
      );
      return false;
    }
    if (!lower.endsWith('.mc')) {
      _setFailure('open_chart_failed', 'unsupported_extension');
      return false;
    }

    final file = File(path);
    if (!file.existsSync()) {
      _setFailure('open_chart_failed', 'file_not_found:$path');
      return false;
    }

    try {
      final chart = McChartIo.parse(file.readAsStringSync());
      openSession(filePath: path);
      final session = _session;
      if (session == null) {
        _setFailure('open_chart_failed', 'session_not_open');
        return false;
      }

      if (!_replaceBpms(session, chart.bpms)) {
        _setFailureFromSession('open_chart_failed', session);
        return false;
      }
      if (!session.setMetadata(chart.metadata)) {
        _setFailureFromSession('open_chart_failed', session);
        return false;
      }

      final ops = chart.notes
          .map(
            (note) =>
                CoreNoteBatchOp(opType: CoreNoteBatchOpType.add, note: note),
          )
          .toList();
      if (!session.applyNoteBatch(ops)) {
        _setFailureFromSession('open_chart_failed', session);
        return false;
      }

      _currentFilePath = path;
      _dirty = false;
      _cacheRevision = -1;
      _refreshSnapshotsIfNeeded();
      _appendRecentFile(path);
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      _lastEventLog = 'open_chart_ok';
      notifyListeners();
      return true;
    } catch (e) {
      _setFailure('open_chart_failed', 'parse_error:$e');
      return false;
    }
  }

  bool saveChart({String? path}) {
    final session = _session;
    if (session == null) {
      _setFailure('save_chart_failed', 'session_not_open');
      return false;
    }

    final target = (path ?? _currentFilePath ?? '').trim();
    if (target.isEmpty) {
      _setFailure('save_chart_failed', 'target_path_required');
      return false;
    }

    final lower = target.toLowerCase();
    if (lower.endsWith('.mcz')) {
      _setFailure(
        'save_chart_failed',
        'mcz_fallback_required: save .mc first, then package externally.',
      );
      return false;
    }
    if (!lower.endsWith('.mc')) {
      _setFailure('save_chart_failed', 'unsupported_extension');
      return false;
    }

    _refreshSnapshotsIfNeeded();

    final content = McChartIo.encode(
      metadata: _cachedMetadata,
      bpms: _cachedBpms,
      notes: _cachedNotes,
    );

    try {
      File(target).writeAsStringSync(content);
      _currentFilePath = target;
      _dirty = false;
      _appendRecentFile(target);
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      _lastEventLog = 'save_chart_ok';
      notifyListeners();
      return true;
    } catch (e) {
      _setFailure('save_chart_failed', 'write_error:$e');
      return false;
    }
  }

  Future<bool> importMczFile({
    required String mczPath,
    required ChartArchivePort archive,
    required ChartWorkspacePort workspace,
    required MczChartSelectionResolver chooseChart,
  }) async {
    final sourcePath = mczPath.trim();
    if (!sourcePath.toLowerCase().endsWith('.mcz')) {
      reportExternalError(
        event: '${_mczImportEventPrefix}failed',
        message: '${_mczImportEventPrefix}unsupported_extension',
      );
      return false;
    }
    if (!File(sourcePath).existsSync()) {
      reportExternalError(
        event: '${_mczImportEventPrefix}failed',
        message: '${_mczImportEventPrefix}file_not_found:$sourcePath',
      );
      return false;
    }

    String? tempDirectoryPath;
    try {
      tempDirectoryPath = await workspace.createImportTempDirectory();
      final extractedFiles = await archive.extractMcz(
        mczPath: sourcePath,
        targetDirectoryPath: tempDirectoryPath,
      );

      final mcFiles =
          extractedFiles
              .where((entry) => entry.toLowerCase().endsWith('.mc'))
              .toList()
            ..sort();
      if (mcFiles.isEmpty) {
        reportExternalError(
          event: '${_mczImportEventPrefix}failed',
          message: '${_mczImportEventPrefix}mc_not_found',
        );
        return false;
      }

      final parsedByPath = <String, ParsedMcChart>{};
      final candidates = <MczChartCandidate>[];
      for (final mcFilePath in mcFiles) {
        try {
          final parsed = McChartIo.parse(File(mcFilePath).readAsStringSync());
          parsedByPath[mcFilePath] = parsed;
          candidates.add(
            MczChartCandidate(
              mcPath: mcFilePath,
              relativePath: path.relative(mcFilePath, from: tempDirectoryPath),
              difficulty: parsed.metadata.difficulty.trim().isEmpty
                  ? path.basenameWithoutExtension(mcFilePath)
                  : parsed.metadata.difficulty,
            ),
          );
        } catch (_) {
          // Ignore unparseable files and continue scanning the archive.
        }
      }

      if (candidates.isEmpty) {
        reportExternalError(
          event: '${_mczImportEventPrefix}failed',
          message: '${_mczImportEventPrefix}parse_failed',
        );
        return false;
      }

      String selectedPath = candidates.first.mcPath;
      if (candidates.length > 1) {
        final selected = await chooseChart(candidates);
        if (selected == null || selected.trim().isEmpty) {
          reportExternalError(
            event: '${_mczImportEventPrefix}cancelled',
            message: '${_mczImportEventPrefix}chart_not_selected',
          );
          return false;
        }
        selectedPath = selected.trim();
      }

      final selectedChart = parsedByPath[selectedPath];
      if (selectedChart == null) {
        reportExternalError(
          event: '${_mczImportEventPrefix}failed',
          message: '${_mczImportEventPrefix}chart_selection_invalid',
        );
        return false;
      }

      final selectedChartDirectory = File(selectedPath).parent.path;
      final resolvedResources = <_ResolvedResourcePath>[];
      final seen = <String>{};

      for (final ref in _collectReferencedResourcePaths(
        metadata: selectedChart.metadata,
        notes: selectedChart.notes,
      )) {
        final resolved = _resolveImportResourcePath(
          chartDirectory: selectedChartDirectory,
          reference: ref,
        );
        if (!seen.add(resolved.normalizedReference)) {
          continue;
        }
        if (!workspace.fileExists(resolved.sourcePath)) {
          reportExternalError(
            event: '${_mczImportEventPrefix}failed',
            message:
                '${_mczImportEventPrefix}resource_missing:${resolved.relativePath}',
          );
          return false;
        }
        resolvedResources.add(resolved);
      }

      final workspaceLocation = await workspace.createChartWorkspace(
        suggestedStem: _buildWorkspaceStem(selectedChart, selectedPath),
        chartFileName: path.basename(selectedPath),
      );

      final rewriteMapping = <String, String>{};
      for (final resource in resolvedResources) {
        final targetPath = path.joinAll(<String>[
          workspaceLocation.rootDirectoryPath,
          ...path.posix.split(resource.relativePath),
        ]);
        await workspace.copyFile(
          sourcePath: resource.sourcePath,
          targetPath: targetPath,
        );
        rewriteMapping[resource.normalizedReference] = resource.relativePath;
      }

      final rewrittenMetadata = _rewriteMetadataReferences(
        selectedChart.metadata,
        rewriteMapping,
      );
      final rewrittenNotes = _rewriteNoteReferences(
        selectedChart.notes,
        rewriteMapping,
      );
      final chartContent = McChartIo.encode(
        metadata: rewrittenMetadata,
        bpms: selectedChart.bpms,
        notes: rewrittenNotes,
      );

      await workspace.writeTextFile(
        targetPath: workspaceLocation.chartFilePath,
        content: chartContent,
      );

      final opened = openChartFile(workspaceLocation.chartFilePath);
      if (!opened) {
        reportExternalError(
          event: '${_mczImportEventPrefix}failed',
          message: '${_mczImportEventPrefix}open_failed:$lastError',
        );
        return false;
      }

      _lastEventLog = '${_mczImportEventPrefix}ok';
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      notifyListeners();
      return true;
    } catch (e) {
      reportExternalError(
        event: '${_mczImportEventPrefix}failed',
        message: '${_mczImportEventPrefix}exception:$e',
      );
      return false;
    } finally {
      if (tempDirectoryPath != null && tempDirectoryPath.isNotEmpty) {
        await workspace.deleteDirectory(tempDirectoryPath);
      }
    }
  }

  Future<bool> exportMczFile({
    required String outputPath,
    required ChartArchivePort archive,
    required ChartWorkspacePort workspace,
  }) async {
    reportExternalError(
      event: '${_mczExportEventPrefix}failed',
      message: '${_mczExportEventPrefix}not_implemented',
    );
    return false;
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
    _noteIdSeed += 1;
    final id = 'mobile-note-$_noteIdSeed';
    _commitMutation('add_note_failed', (session) {
      return session.addNormalNote(
        id: id,
        measure: measure,
        numerator: numerator,
        denominator: denominator,
        x: x,
      );
    }, 'add_note_ok:$id');
  }

  void addNormalNoteAtBeat({required double beat, required int x}) {
    final parsed = _doubleToBeat(beat);
    addNormalNote(
      measure: parsed.measure,
      numerator: parsed.numerator,
      denominator: parsed.denominator,
      x: x,
    );
  }

  void addRainNote({
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    _noteIdSeed += 1;
    final id = 'mobile-rain-$_noteIdSeed';
    _commitMutation('add_rain_failed', (session) {
      return session.addRainNote(id: id, beat: beat, endBeat: endBeat, x: x);
    }, 'add_rain_ok:$id');
  }

  void addRainNoteAtBeat({required double beat, required int x}) {
    final start = _doubleToBeat(beat);
    final end = _doubleToBeat(beat + 1.0);
    addRainNote(beat: start, endBeat: end, x: x);
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
      _setFailureFromSession('move_rain_failed', session);
      return;
    }

    _markChanged('move_rain_ok:$id');
  }

  void moveSelectedNoteTo({required double beat, required int x}) {
    final session = _session;
    if (session == null) {
      _setFailure('move_note_failed', 'session_not_open');
      return;
    }
    if (_selectedNoteIds.length != 1) {
      _setFailure('move_note_failed', 'select_single_note');
      return;
    }

    final selectedId = _selectedNoteIds.first;
    final source = _findNoteById(selectedId);
    if (source == null) {
      _setFailure('move_note_failed', 'note_not_found:$selectedId');
      return;
    }

    final nextBeat = _doubleToBeat(beat);
    if (source.type == _noteTypeRain) {
      final span = max(
        0.0,
        _beatToDouble(source.endBeat) - _beatToDouble(source.beat),
      );
      final nextEnd = _doubleToBeat(beat + max(span, 1.0));
      moveSelectedRainNote(beat: nextBeat, endBeat: nextEnd, x: x);
      return;
    }

    final moved = CoreNoteSnapshot(
      id: source.id,
      type: source.type,
      beat: nextBeat,
      endBeat: source.endBeat,
      x: x,
      sound: source.sound,
      volume: source.volume,
      offsetMs: source.offsetMs,
    );

    final ok = session.applyNoteBatch(<CoreNoteBatchOp>[
      CoreNoteBatchOp(opType: CoreNoteBatchOpType.move, note: moved),
    ]);
    if (!ok) {
      _setFailureFromSession('move_note_failed', session);
      return;
    }

    _markChanged('move_note_ok:${source.id}');
  }

  void addSoundNote({
    required CoreBeat beat,
    required String sound,
    int volume = 100,
    int offsetMs = 0,
  }) {
    _noteIdSeed += 1;
    final id = 'mobile-sound-$_noteIdSeed';
    _commitMutation('add_sound_failed', (session) {
      return session.addSoundNote(
        id: id,
        beat: beat,
        sound: sound,
        volume: volume,
        offsetMs: offsetMs,
      );
    }, 'add_sound_ok:$id');
  }

  void removeNoteById(String id) {
    _commitMutation(
      'remove_note_failed',
      (session) {
        return session.removeNoteById(id);
      },
      'remove_note_ok:$id',
      beforeSuccess: () {
        _selectedNoteIds.remove(id);
      },
    );
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
    _commitMutation('undo_failed', (session) => session.undo(), 'undo_ok');
  }

  void redo() {
    _commitMutation('redo_failed', (session) => session.redo(), 'redo_ok');
  }

  bool applyNoteBatch(List<CoreNoteBatchOp> operations) {
    final session = _session;
    if (session == null) {
      _setFailure('batch_edit_failed', 'session_not_open');
      return false;
    }
    final ok = session.applyNoteBatch(operations);
    if (!ok) {
      _setFailureFromSession('batch_edit_failed', session);
      return false;
    }
    _markChanged('batch_edit_ok:${operations.length}');
    return true;
  }

  bool addBpmEntry({required CoreBeat beat, required double bpm}) {
    final session = _session;
    if (session == null) {
      _setFailure('add_bpm_failed', 'session_not_open');
      return false;
    }
    final ok = session.addBpm(beat: beat, bpm: bpm);
    if (!ok) {
      _setFailureFromSession('add_bpm_failed', session);
      return false;
    }
    _markChanged('add_bpm_ok');
    return true;
  }

  bool updateBpmEntry({
    required int index,
    required CoreBeat beat,
    required double bpm,
  }) {
    final session = _session;
    if (session == null) {
      _setFailure('update_bpm_failed', 'session_not_open');
      return false;
    }
    final ok = session.updateBpm(index: index, beat: beat, bpm: bpm);
    if (!ok) {
      _setFailureFromSession('update_bpm_failed', session);
      return false;
    }
    _markChanged('update_bpm_ok:$index');
    return true;
  }

  bool removeBpmEntry(int index) {
    final session = _session;
    if (session == null) {
      _setFailure('remove_bpm_failed', 'session_not_open');
      return false;
    }
    final ok = session.removeBpm(index);
    if (!ok) {
      _setFailureFromSession('remove_bpm_failed', session);
      return false;
    }
    _markChanged('remove_bpm_ok:$index');
    return true;
  }

  bool updateMetadata(CoreMetadataSnapshot metadata) {
    final session = _session;
    if (session == null) {
      _setFailure('set_meta_failed', 'session_not_open');
      return false;
    }
    final ok = session.setMetadata(metadata);
    if (!ok) {
      _setFailureFromSession('set_meta_failed', session);
      return false;
    }
    _markChanged('set_meta_ok');
    return true;
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
      bpms: List<CoreBpmSnapshot>.from(_cachedBpms),
      metadata: _cachedMetadata,
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
      _cachedBpms.clear();
      _cachedMetadata = CoreMetadataSnapshot.empty();
      _selectedNoteIds.clear();
      _editorMode = draft.mode;

      if (!_replaceBpms(session, draft.bpms)) {
        _setFailureFromSession('draft_restore_failed', session);
        return;
      }
      if (!session.setMetadata(draft.metadata)) {
        _setFailureFromSession('draft_restore_failed', session);
        return;
      }

      final ops = draft.notes
          .map(
            (note) =>
                CoreNoteBatchOp(opType: CoreNoteBatchOpType.add, note: note),
          )
          .toList();
      if (!session.applyNoteBatch(ops)) {
        _setFailureFromSession('draft_restore_failed', session);
        return;
      }

      _syncRevisionFromCore();
      _refreshSnapshotsIfNeeded();
      _selectedNoteIds.addAll(
        draft.selectedIds.where((id) => _containsNoteId(id)),
      );

      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      _lastEventLog = 'draft_restored:${draft.notes.length}';
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

  bool _replaceBpms(CoreSessionPort session, List<CoreBpmSnapshot> target) {
    final count = session.bpmCount;
    for (var i = count - 1; i >= 0; i--) {
      if (!session.removeBpm(i)) {
        return false;
      }
    }

    if (target.isEmpty) {
      return session.addBpm(
        beat: const CoreBeat(measure: 0, numerator: 0, denominator: 1),
        bpm: 120.0,
      );
    }

    for (final bpm in target) {
      if (!session.addBpm(beat: bpm.beat, bpm: bpm.bpm)) {
        return false;
      }
    }
    return true;
  }

  String _buildWorkspaceStem(ParsedMcChart chart, String selectedPath) {
    final title = chart.metadata.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    return path.basenameWithoutExtension(selectedPath);
  }

  Set<String> _collectReferencedResourcePaths({
    required CoreMetadataSnapshot metadata,
    required List<CoreNoteSnapshot> notes,
  }) {
    final refs = <String>{};
    final audio = _normalizeResourceReference(metadata.audioFile);
    if (audio != null) {
      refs.add(audio);
    }
    final background = _normalizeResourceReference(metadata.backgroundFile);
    if (background != null) {
      refs.add(background);
    }
    for (final note in notes) {
      if (note.type != 1) {
        continue;
      }
      final sound = _normalizeResourceReference(note.sound);
      if (sound != null) {
        refs.add(sound);
      }
    }
    return refs;
  }

  _ResolvedResourcePath _resolveImportResourcePath({
    required String chartDirectory,
    required String reference,
  }) {
    final normalizedRef = _normalizeResourceReference(reference);
    if (normalizedRef == null) {
      throw StateError('resource reference empty');
    }
    if (_looksAbsolutePath(normalizedRef)) {
      throw StateError('absolute reference not allowed: $reference');
    }
    if (normalizedRef.startsWith('../') || normalizedRef.contains('/../')) {
      throw StateError('parent traversal not allowed: $reference');
    }
    final sourcePath = path.joinAll(<String>[
      chartDirectory,
      ...path.posix.split(normalizedRef),
    ]);
    return _ResolvedResourcePath(
      normalizedReference: normalizedRef,
      sourcePath: sourcePath,
      relativePath: normalizedRef,
    );
  }

  CoreMetadataSnapshot _rewriteMetadataReferences(
    CoreMetadataSnapshot metadata,
    Map<String, String> rewriteMapping,
  ) {
    final nextAudio = _rewriteResourceReference(
      metadata.audioFile,
      rewriteMapping,
    );
    final nextBackground = _rewriteResourceReference(
      metadata.backgroundFile,
      rewriteMapping,
    );
    return metadata.copyWith(
      audioFile: nextAudio,
      backgroundFile: nextBackground,
    );
  }

  List<CoreNoteSnapshot> _rewriteNoteReferences(
    List<CoreNoteSnapshot> notes,
    Map<String, String> rewriteMapping,
  ) {
    return notes.map((note) {
      if (note.type != 1 || note.sound.trim().isEmpty) {
        return note;
      }
      final rewrittenSound = _rewriteResourceReference(
        note.sound,
        rewriteMapping,
      );
      return CoreNoteSnapshot(
        id: note.id,
        type: note.type,
        beat: note.beat,
        endBeat: note.endBeat,
        x: note.x,
        sound: rewrittenSound,
        volume: note.volume,
        offsetMs: note.offsetMs,
      );
    }).toList();
  }

  String _rewriteResourceReference(
    String rawValue,
    Map<String, String> rewriteMapping,
  ) {
    final normalized = _normalizeResourceReference(rawValue);
    if (normalized == null) {
      return rawValue;
    }
    return rewriteMapping[normalized] ?? rawValue;
  }

  String? _normalizeResourceReference(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    var normalized = trimmed.replaceAll('\\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    normalized = path.posix.normalize(normalized);
    if (normalized == '.' || normalized.isEmpty) {
      return null;
    }
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  bool _looksAbsolutePath(String rawPath) {
    if (rawPath.startsWith('/') || rawPath.startsWith('\\')) {
      return true;
    }
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(rawPath);
  }

  void _commitMutation(
    String failEvent,
    bool Function(CoreSessionPort session) mutate,
    String successEvent, {
    VoidCallback? beforeSuccess,
  }) {
    final session = _session;
    if (session == null) {
      _setFailure(failEvent, 'session_not_open');
      return;
    }

    final ok = mutate(session);
    if (!ok) {
      _setFailureFromSession(failEvent, session);
      return;
    }

    if (beforeSuccess != null) {
      beforeSuccess();
    }
    _markChanged(successEvent);
  }

  bool _containsNoteId(String id) => _findNoteById(id) != null;

  CoreNoteSnapshot? _findNoteById(String id) {
    _refreshSnapshotsIfNeeded();
    for (final note in _cachedNotes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  void _markChanged(String event) {
    _dirty = true;
    _cacheRevision = -1;
    _syncRevisionFromCore();
    _refreshSnapshotsIfNeeded();
    _selectedNoteIds.removeWhere((id) => !_containsNoteId(id));
    _lastError = '';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    _lastEventLog = event;
    notifyListeners();
  }

  void _setFailureFromSession(String event, CoreSessionPort session) {
    _lastEventLog = event;
    _lastError = session.lastErrorDetails;
    _lastErrorCode = session.lastErrorCode;
    _lastErrorName = session.lastErrorName;
    notifyListeners();
  }

  void _setFailure(String event, String error) {
    _lastEventLog = event;
    _lastError = error;
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    notifyListeners();
  }

  void reportExternalError({
    required String event,
    required String message,
    int code = 0,
    String name = 'none',
  }) {
    _lastEventLog = event;
    _lastError = message;
    _lastErrorCode = code;
    _lastErrorName = name;
    notifyListeners();
  }

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
      _cachedBpms.clear();
      _cachedMetadata = CoreMetadataSnapshot.empty();
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
    _cachedBpms
      ..clear()
      ..addAll(session.bpmSnapshots());
    _cachedMetadata =
        session.metadataSnapshot() ?? CoreMetadataSnapshot.empty();

    _selectedNoteIds.removeWhere(
      (id) => !_cachedNotes.any((note) => note.id == id),
    );
    _revision = coreRevision;
    _cacheRevision = coreRevision;
  }

  void _appendRecentFile(String path) {
    _memoryRecentFiles.remove(path);
    _memoryRecentFiles.insert(0, path);
    if (_memoryRecentFiles.length > _recentFileLimit) {
      _memoryRecentFiles.removeRange(
        _recentFileLimit,
        _memoryRecentFiles.length,
      );
    }
  }

  CoreBeat _doubleToBeat(double beat) {
    final measure = beat.floor();
    final frac = beat - measure;
    const den = 192;
    final num = (frac * den).round().clamp(0, den);
    final gcd = _gcd(num, den);
    return CoreBeat(
      measure: measure,
      numerator: num ~/ gcd,
      denominator: den ~/ gcd,
    );
  }

  double _beatToDouble(CoreBeat beat) {
    return beat.measure + beat.numerator / max(1, beat.denominator);
  }

  int _gcd(int a, int b) {
    var x = a.abs();
    var y = b.abs();
    while (y != 0) {
      final t = x % y;
      x = y;
      y = t;
    }
    return x == 0 ? 1 : x;
  }
}
