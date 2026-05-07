import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'beat_time_mapper.dart';
import 'core_session.dart';
import 'mc_chart_io.dart';
import 'native_core.dart';
import '../io/chart_archive.dart';
import '../io/chart_audio.dart';
import '../io/chart_workspace.dart';

enum EditorMode { placeNormal, placeRain, delete, select, move }

enum PlaybackStatus { idle, loading, ready, playing, paused, error }

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

typedef ChartAudioFactory = ChartAudioPort Function();

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

class _ExportResourceSpec {
  const _ExportResourceSpec({
    required this.normalizedReference,
    required this.sourcePath,
    required this.archiveRelativePath,
  });

  final String normalizedReference;
  final String sourcePath;
  final String archiveRelativePath;
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

class _ClipboardNote {
  const _ClipboardNote(this.note);

  final CoreNoteSnapshot note;
}

class ChartDocumentController extends ChangeNotifier {
  ChartDocumentController({
    CoreSessionFactory? sessionFactory,
    ChartAudioFactory? audioFactory,
  }) : _sessionFactory = sessionFactory ?? CoreSession.open,
       _audioFactory = audioFactory ?? (() => ChartAudio());

  static const int _noteTypeRain = 3;
  static const int _snapshotBatchSize = 128;
  static const int _recentFileLimit = 12;
  static const String _mczImportEventPrefix = 'mcz_import_';
  static const String _mczExportEventPrefix = 'mcz_export_';
  static const String _audioEventPrefix = 'audio_playback_';

  final CoreSessionFactory _sessionFactory;
  final ChartAudioFactory _audioFactory;
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
  final List<_ClipboardNote> _noteClipboard = <_ClipboardNote>[];
  String _lastEventLog = '';
  String _lastError = '';
  int _lastErrorCode = 0;
  String _lastErrorName = 'none';
  int _noteIdSeed = 0;
  EditorMode _editorMode = EditorMode.select;
  int _timeDivision = 4;
  bool _gridSnapEnabled = true;
  int _gridDivision = 20;
  PlaybackStatus _playbackStatus = PlaybackStatus.idle;
  int _playheadMs = 0;
  double _playheadBeat = 0.0;
  int _durationMs = 0;
  double _playbackRate = 1.0;
  BeatTimeMapper? _beatTimeMapper;
  ChartAudioPort? _audio;
  StreamSubscription<Duration>? _audioPositionSub;
  StreamSubscription<Duration?>? _audioDurationSub;
  StreamSubscription<ChartAudioPlaybackState>? _audioStateSub;
  String? _preparedAudioPath;

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
  int get timeDivision => _timeDivision;
  bool get gridSnapEnabled => _gridSnapEnabled;
  int get gridDivision => _gridDivision;
  bool get hasDraft => _memoryDraft != null;
  int get selectedCount => _selectedNoteIds.length;
  bool get hasClipboardNotes => _noteClipboard.isNotEmpty;
  UnmodifiableListView<CoreNoteSnapshot> get selectedNotes {
    _refreshSnapshotsIfNeeded();
    final selected = _cachedNotes
        .where((note) => _selectedNoteIds.contains(note.id))
        .toList()
      ..sort((a, b) {
        final beatDiff = _beatToDouble(a.beat).compareTo(_beatToDouble(b.beat));
        if (beatDiff != 0) {
          return beatDiff;
        }
        return a.x.compareTo(b.x);
      });
    return UnmodifiableListView<CoreNoteSnapshot>(selected);
  }
  CoreNoteSnapshot? get primarySelectedNote {
    final selected = selectedNotes;
    if (selected.length != 1) {
      return null;
    }
    return selected.first;
  }
  PlaybackStatus get playbackStatus => _playbackStatus;
  int get playheadMs => _playheadMs;
  double get playheadBeat => _playheadBeat;
  int get durationMs => _durationMs;
  double get playbackRate => _playbackRate;

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
      _teardownAudio(resetRate: false);
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
      _rebuildBeatTimeMapper();
      _resetPlaybackState(notify: false, keepRate: true);
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
    _teardownAudio(resetRate: false);
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
    _beatTimeMapper = null;
    _resetPlaybackState(notify: false, keepRate: true);
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

  void setTimeDivision(int division) {
    final normalized = division.clamp(1, 96);
    if (_timeDivision == normalized) {
      return;
    }
    _timeDivision = normalized;
    _lastError = '';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    _lastEventLog = 'time_division_set:$_timeDivision';
    notifyListeners();
  }

  void setGridSnapEnabled(bool enabled) {
    if (_gridSnapEnabled == enabled) {
      return;
    }
    _gridSnapEnabled = enabled;
    _lastError = '';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    _lastEventLog = 'grid_snap_set:$_gridSnapEnabled';
    notifyListeners();
  }

  void setGridDivision(int division) {
    final normalized = division.clamp(4, 64);
    if (_gridDivision == normalized) {
      return;
    }
    _gridDivision = normalized;
    _lastError = '';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    _lastEventLog = 'grid_division_set:$_gridDivision';
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
      _rebuildBeatTimeMapper();
      _teardownAudio(resetRate: false);
      _resetPlaybackState(notify: false, keepRate: true);
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
    final normalizedOutputPath = outputPath.trim();
    if (!normalizedOutputPath.toLowerCase().endsWith('.mcz')) {
      reportExternalError(
        event: '${_mczExportEventPrefix}failed',
        message: '${_mczExportEventPrefix}unsupported_extension',
      );
      return false;
    }

    if (_session == null) {
      reportExternalError(
        event: '${_mczExportEventPrefix}failed',
        message: '${_mczExportEventPrefix}session_not_open',
      );
      return false;
    }

    final sourceMcPath = (_currentFilePath ?? '').trim();
    if (sourceMcPath.isEmpty) {
      reportExternalError(
        event: '${_mczExportEventPrefix}failed',
        message: '${_mczExportEventPrefix}chart_path_required',
      );
      return false;
    }

    if (_dirty) {
      final saved = saveChart(path: sourceMcPath);
      if (!saved) {
        reportExternalError(
          event: '${_mczExportEventPrefix}failed',
          message: '${_mczExportEventPrefix}save_failed:$lastError',
        );
        return false;
      }
    }

    if (!File(sourceMcPath).existsSync()) {
      reportExternalError(
        event: '${_mczExportEventPrefix}failed',
        message: '${_mczExportEventPrefix}source_not_found:$sourceMcPath',
      );
      return false;
    }

    String? tempDirectoryPath;
    try {
      final sourceChart = McChartIo.parse(
        File(sourceMcPath).readAsStringSync(),
      );
      final sourceChartDirectory = File(sourceMcPath).parent.path;
      final exportResources = <_ExportResourceSpec>[];
      final seenReferences = <String>{};

      for (final ref in _collectReferencedResourcePaths(
        metadata: sourceChart.metadata,
        notes: sourceChart.notes,
      )) {
        final spec = _resolveExportResourceSpec(
          chartDirectory: sourceChartDirectory,
          normalizedReference: ref,
        );
        if (!seenReferences.add(spec.normalizedReference)) {
          continue;
        }
        if (!workspace.fileExists(spec.sourcePath)) {
          reportExternalError(
            event: '${_mczExportEventPrefix}failed',
            message:
                '${_mczExportEventPrefix}resource_missing:${spec.archiveRelativePath}',
          );
          return false;
        }
        exportResources.add(spec);
      }

      final rewriteMapping = <String, String>{
        for (final spec in exportResources)
          spec.normalizedReference: spec.archiveRelativePath,
      };
      final rewrittenMetadata = _rewriteMetadataReferences(
        sourceChart.metadata,
        rewriteMapping,
      );
      final rewrittenNotes = _rewriteNoteReferences(
        sourceChart.notes,
        rewriteMapping,
      );

      tempDirectoryPath = await workspace.createImportTempDirectory();
      final chartFileName = path.basename(sourceMcPath);
      final tempChartPath = path.join(tempDirectoryPath, chartFileName);
      final chartContent = McChartIo.encode(
        metadata: rewrittenMetadata,
        bpms: sourceChart.bpms,
        notes: rewrittenNotes,
      );
      await workspace.writeTextFile(
        targetPath: tempChartPath,
        content: chartContent,
      );

      final archiveFiles = <ChartArchiveFileSpec>[
        ChartArchiveFileSpec(
          sourcePath: tempChartPath,
          archivePath: '0/$chartFileName',
        ),
      ];
      final seenArchivePaths = <String>{'0/$chartFileName'};
      for (final resource in exportResources) {
        final archivePath = '0/${resource.archiveRelativePath}';
        if (!seenArchivePaths.add(archivePath)) {
          continue;
        }
        archiveFiles.add(
          ChartArchiveFileSpec(
            sourcePath: resource.sourcePath,
            archivePath: archivePath,
          ),
        );
      }

      await archive.createMcz(
        outputPath: normalizedOutputPath,
        files: archiveFiles,
      );
      _lastEventLog = '${_mczExportEventPrefix}ok';
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      notifyListeners();
      return true;
    } catch (e) {
      reportExternalError(
        event: '${_mczExportEventPrefix}failed',
        message: '${_mczExportEventPrefix}exception:$e',
      );
      return false;
    } finally {
      if (tempDirectoryPath != null && tempDirectoryPath.isNotEmpty) {
        await workspace.deleteDirectory(tempDirectoryPath);
      }
    }
  }

  Future<bool> prepareAudioFromCurrentChart() async {
    if (_session == null) {
      _setPlaybackFailure('session_not_open');
      return false;
    }
    final chartPath = (_currentFilePath ?? '').trim();
    if (chartPath.isEmpty) {
      _setPlaybackFailure('chart_path_required');
      return false;
    }

    _refreshSnapshotsIfNeeded();
    _rebuildBeatTimeMapper();

    final rawAudioRef = _cachedMetadata.audioFile.trim();
    final normalizedAudioRef = _normalizeResourceReference(rawAudioRef);
    if (normalizedAudioRef == null) {
      _setPlaybackFailure('audio_reference_missing');
      return false;
    }

    final resolvedAudioPath = _resolveAudioSourcePath(
      chartPath: chartPath,
      normalizedAudioReference: normalizedAudioRef,
    );
    if (!File(resolvedAudioPath).existsSync()) {
      _setPlaybackFailure('audio_source_missing:$resolvedAudioPath');
      return false;
    }

    try {
      _setPlaybackStatus(
        PlaybackStatus.loading,
        event: '${_audioEventPrefix}load',
      );
      await _ensureAudioReady();
      await _audio!.loadFile(resolvedAudioPath);
      await _audio!.setRate(_playbackRate);
      _preparedAudioPath = resolvedAudioPath;
      _durationMs = _audio!.currentDuration?.inMilliseconds ?? _durationMs;
      _playheadMs = _audio!.currentPosition.inMilliseconds;
      _playheadBeat = _msToBeat(_playheadMs);
      _setPlaybackStatus(
        PlaybackStatus.ready,
        event: '${_audioEventPrefix}prepared',
      );
      return true;
    } catch (e) {
      _setPlaybackFailure('prepare_failed:$e');
      return false;
    }
  }

  Future<bool> play() async {
    if (_session == null) {
      _setPlaybackFailure('session_not_open');
      return false;
    }
    if (_audio == null || _preparedAudioPath == null) {
      final prepared = await prepareAudioFromCurrentChart();
      if (!prepared) {
        return false;
      }
    }

    try {
      await _audio!.play();
      _setPlaybackStatus(
        PlaybackStatus.playing,
        event: '${_audioEventPrefix}play',
      );
      return true;
    } catch (e) {
      _setPlaybackFailure('play_failed:$e');
      return false;
    }
  }

  Future<bool> pause() async {
    if (_audio == null) {
      _setPlaybackFailure('audio_not_prepared');
      return false;
    }
    try {
      await _audio!.pause();
      _setPlaybackStatus(
        PlaybackStatus.paused,
        event: '${_audioEventPrefix}pause',
      );
      return true;
    } catch (e) {
      _setPlaybackFailure('pause_failed:$e');
      return false;
    }
  }

  Future<bool> seekToBeat(double beat) async {
    if (_audio == null || _beatTimeMapper == null) {
      _setPlaybackFailure('audio_not_prepared');
      return false;
    }

    try {
      final rawTargetMs = _beatToMs(beat);
      final targetMs = _durationMs > 0
          ? rawTargetMs.clamp(0, _durationMs)
          : max(0, rawTargetMs);
      final target = Duration(milliseconds: targetMs);
      await _audio!.seek(target);
      _playheadMs = targetMs;
      _playheadBeat = _msToBeat(targetMs);
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      _lastEventLog = '${_audioEventPrefix}seek';
      notifyListeners();
      return true;
    } catch (e) {
      _setPlaybackFailure('seek_failed:$e');
      return false;
    }
  }

  Future<bool> setPlaybackRate(double rate) async {
    if (rate <= 0) {
      _setPlaybackFailure('invalid_rate:$rate');
      return false;
    }
    _playbackRate = rate;
    if (_audio == null) {
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      _lastEventLog = '${_audioEventPrefix}rate_set';
      notifyListeners();
      return true;
    }
    try {
      await _audio!.setRate(rate);
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      _lastEventLog = '${_audioEventPrefix}rate_set';
      notifyListeners();
      return true;
    } catch (e) {
      _setPlaybackFailure('set_rate_failed:$e');
      return false;
    }
  }

  Future<bool> stopAndReset() async {
    if (_audio == null) {
      _setPlaybackFailure('audio_not_prepared');
      return false;
    }
    try {
      await _audio!.pause();
      await _audio!.seek(Duration.zero);
      _playheadMs = 0;
      _playheadBeat = _msToBeat(0);
      _setPlaybackStatus(
        PlaybackStatus.paused,
        event: '${_audioEventPrefix}stop',
      );
      return true;
    } catch (e) {
      _setPlaybackFailure('stop_failed:$e');
      return false;
    }
  }

  Future<void> handleAppPaused() async {
    if (_audio == null || _playbackStatus != PlaybackStatus.playing) {
      return;
    }
    await pause();
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
    final snappedBeat = _snapBeatForEdit(beat);
    final snappedX = _snapLaneXForEdit(x);
    final parsed = _doubleToBeat(snappedBeat);
    addNormalNote(
      measure: parsed.measure,
      numerator: parsed.numerator,
      denominator: parsed.denominator,
      x: snappedX,
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
    final snappedBeat = _snapBeatForEdit(beat);
    final snappedX = _snapLaneXForEdit(x);
    final start = _doubleToBeat(snappedBeat);
    final end = _doubleToBeat(_snapBeatForEdit(snappedBeat + 1.0));
    addRainNote(beat: start, endBeat: end, x: snappedX);
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

    final snappedBeat = _snapBeatForEdit(beat);
    final nextBeat = _doubleToBeat(snappedBeat);
    if (source.type == _noteTypeRain) {
      final span = max(
        0.0,
        _beatToDouble(source.endBeat) - _beatToDouble(source.beat),
      );
      final nextEnd = _doubleToBeat(_snapBeatForEdit(snappedBeat + max(span, 1.0)));
      moveSelectedRainNote(
        beat: nextBeat,
        endBeat: nextEnd,
        x: _snapLaneXForEdit(x),
      );
      return;
    }

    final moved = CoreNoteSnapshot(
      id: source.id,
      type: source.type,
      beat: nextBeat,
      endBeat: source.endBeat,
      x: _snapLaneXForEdit(x),
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

  void selectAllNotes() {
    _refreshSnapshotsIfNeeded();
    if (_cachedNotes.isEmpty) {
      _setFailure('select_all_failed', 'no_notes');
      return;
    }
    _selectedNoteIds
      ..clear()
      ..addAll(_cachedNotes.map((note) => note.id));
    _lastError = '';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    _lastEventLog = 'select_all_ok:${_selectedNoteIds.length}';
    notifyListeners();
  }

  bool deleteSelectedNotes() {
    _refreshSnapshotsIfNeeded();
    if (_selectedNoteIds.isEmpty) {
      _setFailure('delete_selected_failed', 'selection_empty');
      return false;
    }
    final idSet = Set<String>.from(_selectedNoteIds);
    final removeOps = _cachedNotes
        .where((note) => idSet.contains(note.id))
        .map(
          (note) =>
              CoreNoteBatchOp(opType: CoreNoteBatchOpType.remove, note: note),
        )
        .toList();
    if (removeOps.isEmpty) {
      _setFailure('delete_selected_failed', 'selection_not_found');
      return false;
    }
    final ok = applyNoteBatch(removeOps);
    if (!ok) {
      return false;
    }
    _lastEventLog = 'delete_selected_ok:${removeOps.length}';
    notifyListeners();
    return true;
  }

  bool copySelectedNotes() {
    _refreshSnapshotsIfNeeded();
    if (_selectedNoteIds.isEmpty) {
      _setFailure('copy_selected_failed', 'selection_empty');
      return false;
    }
    final selected =
        _cachedNotes
            .where((note) => _selectedNoteIds.contains(note.id))
            .toList()
          ..sort((a, b) {
            final beatDiff = _beatToDouble(
              a.beat,
            ).compareTo(_beatToDouble(b.beat));
            if (beatDiff != 0) {
              return beatDiff;
            }
            return a.x.compareTo(b.x);
          });
    if (selected.isEmpty) {
      _setFailure('copy_selected_failed', 'selection_not_found');
      return false;
    }
    _noteClipboard
      ..clear()
      ..addAll(selected.map((note) => _ClipboardNote(note)));
    _lastError = '';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    _lastEventLog = 'copy_selected_ok:${selected.length}';
    notifyListeners();
    return true;
  }

  bool pasteClipboardAtBeat(double anchorBeat) {
    final session = _session;
    if (session == null) {
      _setFailure('paste_selected_failed', 'session_not_open');
      return false;
    }
    if (_noteClipboard.isEmpty) {
      _setFailure('paste_selected_failed', 'clipboard_empty');
      return false;
    }

    final sourceNotes = _noteClipboard.map((entry) => entry.note).toList();
    final minBeat = sourceNotes
        .map((note) => _beatToDouble(note.beat))
        .reduce(min);
    final snappedAnchor = _snapBeatForEdit(anchorBeat);
    final beatDelta = snappedAnchor - minBeat;
    final addOps = <CoreNoteBatchOp>[];
    final newIds = <String>{};
    for (final source in sourceNotes) {
      final shiftedBeat = _beatToDouble(source.beat) + beatDelta;
      final nextBeatValue = _snapBeatForEdit(max(0.0, shiftedBeat));
      final nextBeat = _doubleToBeat(nextBeatValue);
      CoreBeat nextEndBeat;
      if (source.type == _noteTypeRain) {
        final span = max(
          0.0,
          _beatToDouble(source.endBeat) - _beatToDouble(source.beat),
        );
        nextEndBeat = _doubleToBeat(
          _snapBeatForEdit(max(0.0, nextBeatValue + span)),
        );
      } else {
        nextEndBeat = nextBeat;
      }

      final nextId = _nextGeneratedIdForType(source.type);
      final nextX = source.type == 1 ? source.x : _snapLaneXForEdit(source.x);
      final pasted = CoreNoteSnapshot(
        id: nextId,
        type: source.type,
        beat: nextBeat,
        endBeat: nextEndBeat,
        x: nextX,
        sound: source.sound,
        volume: source.volume,
        offsetMs: source.offsetMs,
      );
      addOps.add(
        CoreNoteBatchOp(opType: CoreNoteBatchOpType.add, note: pasted),
      );
      newIds.add(nextId);
    }

    final ok = session.applyNoteBatch(addOps);
    if (!ok) {
      _setFailureFromSession('paste_selected_failed', session);
      return false;
    }
    _selectedNoteIds
      ..clear()
      ..addAll(newIds);
    _markChanged('paste_selected_ok:${addOps.length}');
    return true;
  }

  bool nudgeSelectedNotes({required double beatDelta, required int xDelta}) {
    final session = _session;
    if (session == null) {
      _setFailure('nudge_selected_failed', 'session_not_open');
      return false;
    }
    if (_selectedNoteIds.isEmpty) {
      _setFailure('nudge_selected_failed', 'selection_empty');
      return false;
    }

    _refreshSnapshotsIfNeeded();
    final selected = _cachedNotes
        .where((note) => _selectedNoteIds.contains(note.id))
        .toList();
    if (selected.isEmpty) {
      _setFailure('nudge_selected_failed', 'selection_not_found');
      return false;
    }
    if (beatDelta.abs() < 0.00001 && xDelta == 0) {
      _lastError = '';
      _lastErrorCode = 0;
      _lastErrorName = 'none';
      _lastEventLog = 'nudge_selected_noop';
      notifyListeners();
      return true;
    }

    final moveOps = <CoreNoteBatchOp>[];
    for (final note in selected) {
      final nextBeatValue = _snapBeatForEdit(
        max(0.0, _beatToDouble(note.beat) + beatDelta),
      );
      final nextBeat = _doubleToBeat(nextBeatValue);
      CoreBeat nextEndBeat = note.endBeat;
      if (note.type == _noteTypeRain) {
        final span = max(
          0.0,
          _beatToDouble(note.endBeat) - _beatToDouble(note.beat),
        );
        nextEndBeat = _doubleToBeat(nextBeatValue + span);
      }

      final nextX = note.type == 1
          ? note.x
          : _snapLaneXForEdit(note.x + xDelta);
      moveOps.add(
        CoreNoteBatchOp(
          opType: CoreNoteBatchOpType.move,
          note: CoreNoteSnapshot(
            id: note.id,
            type: note.type,
            beat: nextBeat,
            endBeat: nextEndBeat,
            x: nextX,
            sound: note.sound,
            volume: note.volume,
            offsetMs: note.offsetMs,
          ),
        ),
      );
    }

    final ok = session.applyNoteBatch(moveOps);
    if (!ok) {
      _setFailureFromSession('nudge_selected_failed', session);
      return false;
    }
    _markChanged('nudge_selected_ok:${moveOps.length}');
    return true;
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
      _rebuildBeatTimeMapper();
      _teardownAudio(resetRate: false);
      _resetPlaybackState(notify: false, keepRate: true);
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

  Future<void> _ensureAudioReady() async {
    if (_audio != null) {
      return;
    }
    final created = _audioFactory();
    _audio = created;
    _audioPositionSub = created.positionStream.listen((position) {
      _playheadMs = position.inMilliseconds;
      _playheadBeat = _msToBeat(_playheadMs);
      if (_playbackStatus == PlaybackStatus.playing ||
          _playbackStatus == PlaybackStatus.paused ||
          _playbackStatus == PlaybackStatus.ready) {
        notifyListeners();
      }
    });
    _audioDurationSub = created.durationStream.listen((duration) {
      _durationMs = duration?.inMilliseconds ?? 0;
      notifyListeners();
    });
    _audioStateSub = created.stateStream.listen(
      (state) {
        switch (state) {
          case ChartAudioPlaybackState.idle:
            _playbackStatus = PlaybackStatus.idle;
            break;
          case ChartAudioPlaybackState.loading:
            _playbackStatus = PlaybackStatus.loading;
            break;
          case ChartAudioPlaybackState.ready:
            _playbackStatus = PlaybackStatus.ready;
            break;
          case ChartAudioPlaybackState.playing:
            _playbackStatus = PlaybackStatus.playing;
            break;
          case ChartAudioPlaybackState.paused:
          case ChartAudioPlaybackState.completed:
            _playbackStatus = PlaybackStatus.paused;
            break;
          case ChartAudioPlaybackState.error:
            _playbackStatus = PlaybackStatus.error;
            break;
        }
        notifyListeners();
      },
      onError: (Object err) {
        _setPlaybackFailure('stream_error:$err');
      },
    );
  }

  String _resolveAudioSourcePath({
    required String chartPath,
    required String normalizedAudioReference,
  }) {
    if (_looksAbsolutePath(normalizedAudioReference)) {
      return path.normalize(normalizedAudioReference);
    }
    final chartDirectory = File(chartPath).parent.path;
    return path.joinAll(<String>[
      chartDirectory,
      ...path.posix.split(normalizedAudioReference),
    ]);
  }

  void _setPlaybackStatus(PlaybackStatus status, {required String event}) {
    _playbackStatus = status;
    _lastError = '';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    _lastEventLog = event;
    notifyListeners();
  }

  void _setPlaybackFailure(String message) {
    _playbackStatus = PlaybackStatus.error;
    _lastEventLog = '${_audioEventPrefix}failed';
    _lastError = '$_audioEventPrefix$message';
    _lastErrorCode = 0;
    _lastErrorName = 'none';
    notifyListeners();
  }

  void _resetPlaybackState({required bool notify, required bool keepRate}) {
    _playbackStatus = PlaybackStatus.idle;
    _playheadMs = 0;
    _playheadBeat = 0.0;
    _durationMs = 0;
    _preparedAudioPath = null;
    if (!keepRate) {
      _playbackRate = 1.0;
    }
    if (notify) {
      notifyListeners();
    }
  }

  void _teardownAudio({required bool resetRate}) {
    final positionSub = _audioPositionSub;
    _audioPositionSub = null;
    if (positionSub != null) {
      unawaited(positionSub.cancel());
    }
    final durationSub = _audioDurationSub;
    _audioDurationSub = null;
    if (durationSub != null) {
      unawaited(durationSub.cancel());
    }
    final stateSub = _audioStateSub;
    _audioStateSub = null;
    if (stateSub != null) {
      unawaited(stateSub.cancel());
    }
    final audio = _audio;
    _audio = null;
    if (audio != null) {
      unawaited(audio.dispose());
    }
    _resetPlaybackState(notify: false, keepRate: !resetRate);
  }

  void _rebuildBeatTimeMapper() {
    _refreshSnapshotsIfNeeded();
    _beatTimeMapper = BeatTimeMapper.fromChart(
      bpms: _cachedBpms,
      offsetMs: _cachedMetadata.offsetMs,
    );
    _playheadBeat = _msToBeat(_playheadMs);
  }

  int _beatToMs(double beat) {
    final mapper =
        _beatTimeMapper ??
        BeatTimeMapper.fromChart(
          bpms: _cachedBpms,
          offsetMs: _cachedMetadata.offsetMs,
        );
    _beatTimeMapper = mapper;
    return mapper.beatToMs(beat);
  }

  double _msToBeat(int ms) {
    final mapper =
        _beatTimeMapper ??
        BeatTimeMapper.fromChart(
          bpms: _cachedBpms,
          offsetMs: _cachedMetadata.offsetMs,
        );
    _beatTimeMapper = mapper;
    return mapper.msToBeat(ms);
  }

  @override
  void dispose() {
    _teardownAudio(resetRate: false);
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

  _ExportResourceSpec _resolveExportResourceSpec({
    required String chartDirectory,
    required String normalizedReference,
  }) {
    if (normalizedReference.startsWith('../') ||
        normalizedReference.contains('/../')) {
      throw StateError('parent traversal not allowed: $normalizedReference');
    }

    final isAbsolute = _looksAbsolutePath(normalizedReference);
    if (isAbsolute) {
      final sourcePath = path.normalize(normalizedReference);
      final fileName = path.basename(sourcePath);
      if (fileName.trim().isEmpty) {
        throw StateError('absolute reference has no file name');
      }
      return _ExportResourceSpec(
        normalizedReference: normalizedReference,
        sourcePath: sourcePath,
        archiveRelativePath: 'assets/$fileName',
      );
    }

    final sourcePath = path.joinAll(<String>[
      chartDirectory,
      ...path.posix.split(normalizedReference),
    ]);
    return _ExportResourceSpec(
      normalizedReference: normalizedReference,
      sourcePath: sourcePath,
      archiveRelativePath: normalizedReference,
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
    _rebuildBeatTimeMapper();
    if (event.startsWith('set_meta_ok') ||
        event.startsWith('add_bpm_ok') ||
        event.startsWith('update_bpm_ok') ||
        event.startsWith('remove_bpm_ok')) {
      _teardownAudio(resetRate: false);
      _resetPlaybackState(notify: false, keepRate: true);
    }
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

  double _snapBeatForEdit(double beat) {
    final nonNegative = max(0.0, beat);
    if (_timeDivision <= 1) {
      return nonNegative;
    }
    final division = _timeDivision.toDouble();
    return (nonNegative * division).round() / division;
  }

  int _snapLaneXForEdit(int laneX) {
    var clamped = laneX.clamp(0, 512).toInt();
    if (!_gridSnapEnabled) {
      return clamped;
    }
    final normalizedDivision = _gridDivision.clamp(1, 512);
    final step = 512.0 / normalizedDivision;
    final snapped = (clamped / step).round() * step;
    clamped = snapped.round().clamp(0, 512);
    return clamped;
  }

  String _nextGeneratedIdForType(int type) {
    _noteIdSeed += 1;
    if (type == _noteTypeRain) {
      return 'mobile-rain-$_noteIdSeed';
    }
    if (type == 1) {
      return 'mobile-sound-$_noteIdSeed';
    }
    return 'mobile-note-$_noteIdSeed';
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
