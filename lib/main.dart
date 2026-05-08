import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'core/chart_document_controller.dart';
import 'core/native_core.dart';
import 'io/chart_archive.dart';
import 'io/chart_file_picker.dart';
import 'io/chart_share.dart';
import 'io/chart_workspace.dart';
import 'ui/simple_chart_canvas.dart';
import 'ui/simple_density_bar.dart';

void main() {
  runApp(const MalodyCatchMobileApp());
}

class MalodyCatchMobileApp extends StatelessWidget {
  const MalodyCatchMobileApp({
    super.key,
    this.controller,
    this.filePicker,
    this.chartArchive,
    this.chartWorkspace,
    this.chartShare,
    this.runStartupSelfCheckOnInit = true,
    this.forceStartupReady,
  });

  final ChartDocumentController? controller;
  final ChartFilePickerPort? filePicker;
  final ChartArchivePort? chartArchive;
  final ChartWorkspacePort? chartWorkspace;
  final ChartSharePort? chartShare;
  final bool runStartupSelfCheckOnInit;
  final bool? forceStartupReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Malody Catch Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF165B44)),
      ),
      home: MobileEditorPage(
        controller: controller,
        filePicker: filePicker,
        chartArchive: chartArchive,
        chartWorkspace: chartWorkspace,
        chartShare: chartShare,
        runStartupSelfCheckOnInit: runStartupSelfCheckOnInit,
        forceStartupReady: forceStartupReady,
      ),
    );
  }
}

class MobileEditorPage extends StatefulWidget {
  const MobileEditorPage({
    super.key,
    this.controller,
    this.filePicker,
    this.chartArchive,
    this.chartWorkspace,
    this.chartShare,
    this.runStartupSelfCheckOnInit = true,
    this.forceStartupReady,
  });

  final ChartDocumentController? controller;
  final ChartFilePickerPort? filePicker;
  final ChartArchivePort? chartArchive;
  final ChartWorkspacePort? chartWorkspace;
  final ChartSharePort? chartShare;
  final bool runStartupSelfCheckOnInit;
  final bool? forceStartupReady;

  @override
  State<MobileEditorPage> createState() => _MobileEditorPageState();
}

class _MobileEditorPageState extends State<MobileEditorPage>
    with WidgetsBindingObserver {
  static const double _desktopLikeMinWidth = 1200.0;
  static const double _defaultVisibleBeats = 16.0;
  static const double _minVisibleBeats = 4.0;
  static const double _maxVisibleBeats = 64.0;
  static const List<int> _snapDivisions = <int>[
    1,
    2,
    3,
    4,
    6,
    8,
    12,
    16,
    24,
    32,
    48,
  ];
  static const List<double> _playbackRates = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
  ];

  late final ChartDocumentController _controller;
  late final ChartFilePickerPort _filePicker;
  late final ChartArchivePort _chartArchive;
  late final ChartWorkspacePort _chartWorkspace;
  late final ChartSharePort _chartShare;
  late final bool _ownsController;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _artistCtrl = TextEditingController();
  final TextEditingController _difficultyCtrl = TextEditingController();
  final TextEditingController _audioCtrl = TextEditingController();
  final TextEditingController _backgroundCtrl = TextEditingController();
  final TextEditingController _offsetCtrl = TextEditingController();
  final TextEditingController _speedCtrl = TextEditingController();
  final TextEditingController _jumpBeatCtrl = TextEditingController(text: '0');

  double _viewBeat = 0;
  double _visibleBeats = _defaultVisibleBeats;
  double? _pendingRainStartBeat;
  int? _pendingRainLaneX;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.controller == null) {
      _controller = ChartDocumentController();
      _ownsController = true;
    } else {
      _controller = widget.controller!;
      _ownsController = false;
    }
    _filePicker = widget.filePicker ?? const ChartFilePicker();
    _chartArchive = widget.chartArchive ?? const ChartArchive();
    _chartWorkspace = widget.chartWorkspace ?? const ChartWorkspace();
    _chartShare = widget.chartShare ?? const ChartShare();

    _controller.addListener(_onControllerChanged);
    if (widget.runStartupSelfCheckOnInit) {
      _controller.runStartupSelfCheck();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _difficultyCtrl.dispose();
    _audioCtrl.dispose();
    _backgroundCtrl.dispose();
    _offsetCtrl.dispose();
    _speedCtrl.dispose();
    _jumpBeatCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final meta = _controller.metadata;
    if (_titleCtrl.text != meta.title) {
      _titleCtrl.text = meta.title;
    }
    if (_artistCtrl.text != meta.artist) {
      _artistCtrl.text = meta.artist;
    }
    if (_difficultyCtrl.text != meta.difficulty) {
      _difficultyCtrl.text = meta.difficulty;
    }
    if (_audioCtrl.text != meta.audioFile) {
      _audioCtrl.text = meta.audioFile;
    }
    if (_backgroundCtrl.text != meta.backgroundFile) {
      _backgroundCtrl.text = meta.backgroundFile;
    }
    final offsetText = '${meta.offsetMs}';
    if (_offsetCtrl.text != offsetText) {
      _offsetCtrl.text = offsetText;
    }
    final speedText = '${meta.speed}';
    if (_speedCtrl.text != speedText) {
      _speedCtrl.text = speedText;
    }
    _softFollowPlaybackHead();
    setState(() {});
  }

  void _softFollowPlaybackHead() {
    if (_controller.playbackStatus != PlaybackStatus.playing) {
      return;
    }
    final head = _controller.playheadBeat;
    final low = _viewBeat;
    final high = _viewBeat + _visibleBeats;
    if (head < low || head > high) {
      _viewBeat = (head - _visibleBeats * 0.75).clamp(0.0, 1000000.0);
    }
  }

  Future<void> _openChart() async {
    try {
      final path = await _filePicker.pickChartToOpen();
      if (path == null || path.trim().isEmpty) {
        _controller.reportExternalError(
          event: 'open_chart_cancelled',
          message: 'open_cancelled_or_picker_unavailable',
        );
        return;
      }
      final normalizedPath = path.trim();
      if (normalizedPath.toLowerCase().endsWith('.mcz')) {
        await _controller.importMczFile(
          mczPath: normalizedPath,
          archive: _chartArchive,
          workspace: _chartWorkspace,
          chooseChart: _chooseMczChart,
        );
        return;
      }
      _controller.openChartFile(normalizedPath);
    } catch (e) {
      _controller.reportExternalError(
        event: 'open_chart_failed',
        message: 'open_picker_exception:$e',
      );
    }
  }

  Future<String?> _chooseMczChart(List<MczChartCandidate> charts) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select Chart'),
          content: SizedBox(
            width: 420,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: charts.length,
              itemBuilder: (context, index) {
                final candidate = charts[index];
                return ListTile(
                  dense: true,
                  title: Text(candidate.difficulty),
                  subtitle: Text(candidate.relativePath),
                  onTap: () =>
                      Navigator.of(dialogContext).pop(candidate.mcPath),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveChart() async {
    try {
      var target = _controller.currentFilePath;
      if (target == null || target.trim().isEmpty) {
        final dir = await _filePicker.pickDirectoryForSave();
        if (dir == null || dir.trim().isEmpty) {
          _controller.reportExternalError(
            event: 'save_chart_cancelled',
            message: 'save_directory_not_selected',
          );
          return;
        }

        final fileName = await _requestFileName(
          dialogTitle: 'Save File Name',
          hintText: 'chart_name.mc',
          defaultValue: 'mobile_chart.mc',
        );
        if (fileName == null || fileName.trim().isEmpty) {
          _controller.reportExternalError(
            event: 'save_chart_cancelled',
            message: 'save_file_name_not_provided',
          );
          return;
        }

        final normalized = fileName.trim().toLowerCase().endsWith('.mc')
            ? fileName.trim()
            : '${fileName.trim()}.mc';
        target = '$dir${Platform.pathSeparator}$normalized';
      }

      _controller.saveChart(path: target.trim());
    } catch (e) {
      _controller.reportExternalError(
        event: 'save_chart_failed',
        message: 'save_picker_exception:$e',
      );
    }
  }

  Future<void> _exportMcz() async {
    try {
      if (_controller.dirty) {
        await _saveChart();
      }
      if (_controller.dirty) {
        _controller.reportExternalError(
          event: 'mcz_export_cancelled',
          message: 'mcz_export_save_required',
        );
        return;
      }

      final sourceChartPath = _controller.currentFilePath;
      if (sourceChartPath == null || sourceChartPath.trim().isEmpty) {
        _controller.reportExternalError(
          event: 'mcz_export_failed',
          message: 'mcz_export_chart_path_required',
        );
        return;
      }

      final outputDir = await _filePicker.pickDirectoryForSave();
      if (outputDir == null || outputDir.trim().isEmpty) {
        _controller.reportExternalError(
          event: 'mcz_export_cancelled',
          message: 'mcz_export_directory_not_selected',
        );
        return;
      }

      final suggestedName =
          '${path.basenameWithoutExtension(sourceChartPath.trim())}.mcz';
      final fileName = await _requestFileName(
        dialogTitle: 'Export File Name',
        hintText: 'chart_pack.mcz',
        defaultValue: suggestedName,
      );
      if (fileName == null || fileName.trim().isEmpty) {
        _controller.reportExternalError(
          event: 'mcz_export_cancelled',
          message: 'mcz_export_file_name_not_provided',
        );
        return;
      }

      final normalized = fileName.trim().toLowerCase().endsWith('.mcz')
          ? fileName.trim()
          : '${fileName.trim()}.mcz';
      final targetPath = '$outputDir${Platform.pathSeparator}$normalized';
      final exported = await _controller.exportMczFile(
        outputPath: targetPath,
        archive: _chartArchive,
        workspace: _chartWorkspace,
      );
      if (exported) {
        await _shareExportedMcz(targetPath);
      }
    } catch (e) {
      _controller.reportExternalError(
        event: 'mcz_export_failed',
        message: 'mcz_export_picker_exception:$e',
      );
    }
  }

  Future<void> _shareExportedMcz(String targetPath) async {
    try {
      final shared = await _chartShare.shareFile(
        filePath: targetPath,
        subject: path.basename(targetPath),
        text: path.basename(targetPath),
      );
      if (!shared) {
        _controller.reportExternalError(
          event: 'mcz_export_share_failed',
          message: 'mcz_export_share_unavailable',
        );
      }
    } catch (e) {
      _controller.reportExternalError(
        event: 'mcz_export_share_failed',
        message: 'mcz_export_share_exception:$e',
      );
    }
  }

  Future<String?> _requestFileName({
    required String dialogTitle,
    required String hintText,
    required String defaultValue,
  }) async {
    var candidate = defaultValue;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: TextFormField(
            initialValue: candidate,
            autofocus: true,
            decoration: InputDecoration(hintText: hintText),
            onChanged: (value) => candidate = value,
            onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(candidate),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _togglePlayPause() async {
    final status = _controller.playbackStatus;
    if (status == PlaybackStatus.playing) {
      await _controller.pause();
      return;
    }
    if (status == PlaybackStatus.idle || status == PlaybackStatus.error) {
      final prepared = await _controller.prepareAudioFromCurrentChart();
      if (!prepared) {
        return;
      }
    }
    await _controller.play();
  }

  Future<void> _stopPlayback() async {
    await _controller.stopAndReset();
  }

  Future<void> _setPlaybackRate(double rate) async {
    await _controller.setPlaybackRate(rate);
  }

  void _seekFromDensity(double beat) {
    setState(() {
      _viewBeat = (beat - _visibleBeats * 0.75).clamp(0.0, 1000000.0);
    });
    unawaited(_controller.seekToBeat(beat));
  }

  void _setVisibleBeats(double beats) {
    final clamped = beats.clamp(_minVisibleBeats, _maxVisibleBeats).toDouble();
    if ((clamped - _visibleBeats).abs() < 0.001) {
      return;
    }
    setState(() {
      _visibleBeats = clamped;
    });
  }

  Future<void> _showCanvasContextMenu({
    required double beat,
    required int x,
    required Offset globalPosition,
  }) async {
    if (!_controller.sessionOpen) {
      return;
    }
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'place_normal',
          child: Text('Place Normal Here'),
        ),
        const PopupMenuItem<String>(
          value: 'place_rain',
          child: Text('Place Rain Here'),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          enabled: _controller.hasClipboardNotes,
          child: const Text('Paste Here'),
        ),
        PopupMenuItem<String>(
          value: 'copy_selected',
          enabled: _controller.selectedCount > 0,
          child: const Text('Copy Selected'),
        ),
        PopupMenuItem<String>(
          value: 'delete_selected',
          enabled: _controller.selectedCount > 0,
          child: const Text('Delete Selected'),
        ),
      ],
    );
    switch (action) {
      case 'place_normal':
        _controller.addNormalNoteAtBeat(beat: beat, x: x);
        return;
      case 'place_rain':
        _controller.addRainNoteAtBeat(beat: beat, x: x);
        return;
      case 'paste':
        _controller.pasteClipboardAtBeat(beat);
        return;
      case 'copy_selected':
        _controller.copySelectedNotes();
        return;
      case 'delete_selected':
        _controller.deleteSelectedNotes();
        return;
      default:
        return;
    }
  }

  Future<void> _openRecentChart(String chartPath) async {
    final normalized = chartPath.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (normalized.toLowerCase().endsWith('.mcz')) {
      await _controller.importMczFile(
        mczPath: normalized,
        archive: _chartArchive,
        workspace: _chartWorkspace,
        chooseChart: _chooseMczChart,
      );
      return;
    }
    _controller.openChartFile(normalized);
  }

  Future<void> _seekBeatFromInput() async {
    final parsed = double.tryParse(_jumpBeatCtrl.text.trim());
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      _controller.reportExternalError(
        event: 'seek_input_invalid',
        message: 'seek_input_invalid_beat',
      );
      return;
    }
    _seekFromDensity(parsed);
  }

  Future<void> _showGridSettingsDialog() async {
    final timeDivisionCtrl = TextEditingController(
      text: '${_controller.timeDivision}',
    );
    final gridDivisionCtrl = TextEditingController(
      text: '${_controller.gridDivision}',
    );
    var gridSnap = _controller.gridSnapEnabled;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (statefulContext, setDialogState) {
            return AlertDialog(
              title: const Text('Grid Settings'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeDivisionCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Time Division (1-96)',
                      ),
                    ),
                    TextField(
                      controller: gridDivisionCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Grid Division (4-64)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Grid Snap'),
                        const Spacer(),
                        Switch(
                          value: gridSnap,
                          onChanged: (value) =>
                              setDialogState(() => gridSnap = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final timeDivision =
                        int.tryParse(timeDivisionCtrl.text.trim()) ??
                        _controller.timeDivision;
                    final gridDivision =
                        int.tryParse(gridDivisionCtrl.text.trim()) ??
                        _controller.gridDivision;
                    _controller.setTimeDivision(timeDivision);
                    _controller.setGridDivision(gridDivision);
                    _controller.setGridSnapEnabled(gridSnap);
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    timeDivisionCtrl.dispose();
    gridDivisionCtrl.dispose();
  }

  void _nudgeSelectionBeat(double beatDelta) {
    _controller.nudgeSelectedNotes(beatDelta: beatDelta, xDelta: 0);
  }

  void _nudgeSelectionX(int xDelta) {
    _controller.nudgeSelectedNotes(beatDelta: 0, xDelta: xDelta);
  }

  String _formatMs(int ms) {
    final clamped = ms < 0 ? 0 : ms;
    final totalSeconds = clamped ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hundredths = (clamped % 1000) ~/ 10;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    final hh = hundredths.toString().padLeft(2, '0');
    return '$mm:$ss.$hh';
  }

  int _parseIntOrDefault(String raw, int fallback) {
    final parsed = int.tryParse(raw.trim());
    return parsed ?? fallback;
  }

  double _parseDoubleOrDefault(String raw, double fallback) {
    final parsed = double.tryParse(raw.trim());
    return parsed ?? fallback;
  }

  void _applyMeta() {
    final current = _controller.metadata;
    final next = _controller.metadata.copyWith(
      title: _titleCtrl.text.trim(),
      artist: _artistCtrl.text.trim(),
      difficulty: _difficultyCtrl.text.trim().isEmpty
          ? 'Normal'
          : _difficultyCtrl.text.trim(),
      audioFile: _audioCtrl.text.trim(),
      backgroundFile: _backgroundCtrl.text.trim(),
      offsetMs: _parseIntOrDefault(_offsetCtrl.text, current.offsetMs),
      speed: _parseIntOrDefault(_speedCtrl.text, current.speed),
    );
    _controller.updateMetadata(next);
  }

  Future<void> _addBpm() async {
    await _showBpmEditor();
  }

  Future<void> _editBpm(int index, CoreBpmSnapshot bpm) async {
    await _showBpmEditor(index: index, existing: bpm);
  }

  Future<void> _showBpmEditor({int? index, CoreBpmSnapshot? existing}) async {
    final measureCtrl = TextEditingController(
      text: '${existing?.beat.measure ?? 0}',
    );
    final numeratorCtrl = TextEditingController(
      text: '${existing?.beat.numerator ?? 0}',
    );
    final denominatorCtrl = TextEditingController(
      text: '${existing?.beat.denominator ?? 1}',
    );
    final bpmCtrl = TextEditingController(
      text: existing?.bpm.toStringAsFixed(2) ?? '120.00',
    );
    final isEdit = index != null && existing != null;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit BPM' : 'Add BPM'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: measureCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Measure'),
                ),
                TextField(
                  controller: numeratorCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Numerator'),
                ),
                TextField(
                  controller: denominatorCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Denominator'),
                ),
                TextField(
                  controller: bpmCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'BPM'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final beat = CoreBeat(
                  measure: _parseIntOrDefault(measureCtrl.text, 0),
                  numerator: _parseIntOrDefault(numeratorCtrl.text, 0),
                  denominator: _parseIntOrDefault(denominatorCtrl.text, 1),
                );
                final bpmValue = _parseDoubleOrDefault(bpmCtrl.text, 120.0);
                if (isEdit) {
                  _controller.updateBpmEntry(
                    index: index,
                    beat: beat,
                    bpm: bpmValue,
                  );
                } else {
                  _controller.addBpmEntry(beat: beat, bpm: bpmValue);
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    measureCtrl.dispose();
    numeratorCtrl.dispose();
    denominatorCtrl.dispose();
    bpmCtrl.dispose();
  }

  void _deleteSelectedNotes() {
    _controller.deleteSelectedNotes();
  }

  void _copySelectedNotes() {
    _controller.copySelectedNotes();
  }

  void _pasteNotesAtViewBeat() {
    final anchorBeat = _controller.playheadBeat > 0
        ? _controller.playheadBeat
        : _viewBeat;
    _controller.pasteClipboardAtBeat(anchorBeat);
  }

  void _handleCanvasPlaceNormal(double beat, int x) {
    _pendingRainStartBeat = null;
    _pendingRainLaneX = null;
    _controller.addNormalNoteAtBeat(beat: beat, x: x);
  }

  void _handleCanvasPlaceRain(double beat, int x) {
    final pendingStart = _pendingRainStartBeat;
    if (pendingStart == null) {
      setState(() {
        _pendingRainStartBeat = beat;
        _pendingRainLaneX = x;
      });
      return;
    }
    final laneX = _pendingRainLaneX ?? x;
    _controller.addRainNoteBetweenBeats(startBeat: pendingStart, endBeat: beat, x: laneX);
    setState(() {
      _pendingRainStartBeat = null;
      _pendingRainLaneX = null;
    });
  }

  void _handleMoveSelected(double beat, int x) {
    _controller.moveSelectedNoteTo(beat: beat, x: x);
  }

  void _handleMoveSelectedDelta(double beatDelta, int xDelta) {
    _controller.nudgeSelectedNotes(beatDelta: beatDelta, xDelta: xDelta);
  }

  void _handleCanvasSelectRegion({
    required double startBeat,
    required double endBeat,
    required int startX,
    required int endX,
  }) {
    _controller.selectNotesInRegion(
      startBeat: startBeat,
      endBeat: endBeat,
      startX: startX,
      endX: endX,
    );
  }

  String _modeLabel(EditorMode mode) {
    return switch (mode) {
      EditorMode.placeNormal => 'Place Note',
      EditorMode.placeRain => 'Place Rain',
      EditorMode.delete => 'Delete',
      EditorMode.select => 'Select',
      EditorMode.move => 'Move',
    };
  }

  String _noteTypeLabel(int type) {
    return switch (type) {
      0 => 'Normal',
      1 => 'Sound',
      3 => 'Rain',
      _ => 'Type $type',
    };
  }

  double _beatValue(CoreBeat beat) {
    return beat.measure + beat.numerator / (beat.denominator == 0 ? 1 : beat.denominator);
  }

  void _handleLifecyclePause() {
    unawaited(_controller.handleAppPaused());
    if (_controller.sessionOpen && _controller.dirty) {
      _controller.saveDraftToMemory();
    }
  }

  void _handleLifecycleResume() {
    unawaited(_controller.handleAppResumed());
  }

  Widget _buildMetaPanel(bool canOperate) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        TextField(
          controller: _artistCtrl,
          decoration: const InputDecoration(labelText: 'Artist'),
        ),
        TextField(
          controller: _difficultyCtrl,
          decoration: const InputDecoration(labelText: 'Difficulty'),
        ),
        TextField(
          controller: _audioCtrl,
          decoration: const InputDecoration(labelText: 'Audio File'),
        ),
        TextField(
          controller: _backgroundCtrl,
          decoration: const InputDecoration(labelText: 'Background File'),
        ),
        TextField(
          controller: _offsetCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Offset (ms)'),
        ),
        TextField(
          controller: _speedCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Speed'),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: canOperate ? _applyMeta : null,
          child: const Text('Apply Meta'),
        ),
      ],
    );
  }

  Widget _buildBpmPanel(bool canOperate, List<CoreBpmSnapshot> bpms) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const Text('BPM List'),
            const Spacer(),
            IconButton(
              onPressed: canOperate ? () => unawaited(_addBpm()) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        ...bpms.asMap().entries.map((entry) {
          final idx = entry.key;
          final bpm = entry.value;
          return Card(
            child: ListTile(
              dense: true,
              title: Text(
                '${bpm.beat.measure}:${bpm.beat.numerator}/${bpm.beat.denominator}',
              ),
              subtitle: Text('bpm=${bpm.bpm.toStringAsFixed(2)}'),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: 'Edit BPM',
                    onPressed: canOperate
                        ? () => unawaited(_editBpm(idx, bpm))
                        : null,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete BPM',
                    onPressed: canOperate
                        ? () => _controller.removeBpmEntry(idx)
                        : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEditPanel(bool canOperate) {
    final primary = _controller.primarySelectedNote;
    final beatStep = 1 / _controller.timeDivision;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          dense: true,
          title: const Text('Selection'),
          subtitle: Text(
            'count=${_controller.selectedCount} | step=1/${_controller.timeDivision}',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: canOperate ? _controller.selectAllNotes : null,
              child: const Text('Select All'),
            ),
            OutlinedButton(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? _controller.clearSelection
                  : null,
              child: const Text('Clear'),
            ),
            FilledButton.tonal(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? _deleteSelectedNotes
                  : null,
              child: const Text('Delete'),
            ),
            FilledButton.tonal(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? _copySelectedNotes
                  : null,
              child: const Text('Copy'),
            ),
            FilledButton.tonal(
              onPressed: canOperate && _controller.hasClipboardNotes
                  ? _pasteNotesAtViewBeat
                  : null,
              child: const Text('Paste'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text('Nudge Selection'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? () => _nudgeSelectionBeat(-beatStep)
                  : null,
              icon: const Icon(Icons.expand_less),
              label: Text('-1/${_controller.timeDivision} Beat'),
            ),
            OutlinedButton.icon(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? () => _nudgeSelectionBeat(beatStep)
                  : null,
              icon: const Icon(Icons.expand_more),
              label: Text('+1/${_controller.timeDivision} Beat'),
            ),
            OutlinedButton.icon(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? () => _nudgeSelectionX(-8)
                  : null,
              icon: const Icon(Icons.arrow_left),
              label: const Text('X -8'),
            ),
            OutlinedButton.icon(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? () => _nudgeSelectionX(8)
                  : null,
              icon: const Icon(Icons.arrow_right),
              label: const Text('X +8'),
            ),
          ],
        ),
        if (primary != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Primary: ${primary.id}'),
                  Text('Type: ${_noteTypeLabel(primary.type)}'),
                  Text('Beat: ${_beatValue(primary.beat).toStringAsFixed(3)}'),
                  Text('X: ${primary.x}'),
                  if (primary.type == 3)
                    Text(
                      'End: ${_beatValue(primary.endBeat).toStringAsFixed(3)}',
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLeftToolsPanel(bool canOperate) {
    const modeOrder = <EditorMode>[
      EditorMode.placeNormal,
      EditorMode.placeRain,
      EditorMode.delete,
      EditorMode.select,
    ];
    final beatStep = 1 / _controller.timeDivision;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'Mode',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ...modeOrder.map(
          (mode) => RadioListTile<EditorMode>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_modeLabel(mode)),
            value: mode,
            groupValue: _controller.editorMode,
            onChanged: canOperate
                ? (value) {
                    if (value == null) {
                      return;
                    }
                    _controller.setEditorMode(value);
                    if (value != EditorMode.placeRain &&
                        (_pendingRainStartBeat != null ||
                            _pendingRainLaneX != null)) {
                      setState(() {
                        _pendingRainStartBeat = null;
                        _pendingRainLaneX = null;
                      });
                    }
                  }
                : null,
          ),
        ),
        if (_pendingRainStartBeat != null)
          Text(
            'Rain start: ${_pendingRainStartBeat!.toStringAsFixed(3)}',
            style: const TextStyle(color: Colors.amber),
          ),
        if (_pendingRainStartBeat != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() {
                  _pendingRainStartBeat = null;
                  _pendingRainLaneX = null;
                });
              },
              child: const Text('Cancel Rain Start'),
            ),
          ),
        const Divider(height: 18),
        const Text(
          'Grid',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        PopupMenuButton<int>(
          enabled: canOperate,
          onSelected: _controller.setTimeDivision,
          itemBuilder: (context) => _snapDivisions
              .map(
                (division) => PopupMenuItem<int>(
                  value: division,
                  child: Text('1/$division'),
                ),
              )
              .toList(),
          child: Chip(
            label: Text('Time Division 1/${_controller.timeDivision}'),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(child: Text('Grid Snap')),
            Switch(
              value: _controller.gridSnapEnabled,
              onChanged: canOperate ? _controller.setGridSnapEnabled : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        PopupMenuButton<int>(
          enabled: canOperate,
          onSelected: _controller.setGridDivision,
          itemBuilder: (context) => List<int>.generate(16, (i) => i + 4)
              .map(
                (division) => PopupMenuItem<int>(
                  value: division,
                  child: Text('Grid $division'),
                ),
              )
              .toList(),
          child: Chip(label: Text('Grid ${_controller.gridDivision}')),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: canOperate ? () => unawaited(_showGridSettingsDialog()) : null,
          child: const Text('Grid Settings'),
        ),
        const Divider(height: 18),
        const Text(
          'Selection',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text('Selected: ${_controller.selectedCount}'),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: canOperate ? _controller.selectAllNotes : null,
          child: const Text('Select All'),
        ),
        const SizedBox(height: 6),
        FilledButton.tonal(
          onPressed: canOperate && _controller.selectedCount > 0
              ? _deleteSelectedNotes
              : null,
          child: const Text('Delete'),
        ),
        const SizedBox(height: 6),
        FilledButton.tonal(
          onPressed: canOperate && _controller.selectedCount > 0
              ? _copySelectedNotes
              : null,
          child: const Text('Copy'),
        ),
        const SizedBox(height: 6),
        FilledButton.tonal(
          onPressed: canOperate && _controller.hasClipboardNotes
              ? _pasteNotesAtViewBeat
              : null,
          child: const Text('Paste'),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: canOperate && _controller.selectedCount > 0
              ? _controller.clearSelection
              : null,
          child: const Text('Clear Selection'),
        ),
        const SizedBox(height: 8),
        const Text('Nudge'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? () => _nudgeSelectionBeat(-beatStep)
                  : null,
              child: Text('-1/${_controller.timeDivision}'),
            ),
            OutlinedButton(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? () => _nudgeSelectionBeat(beatStep)
                  : null,
              child: Text('+1/${_controller.timeDivision}'),
            ),
            OutlinedButton(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? () => _nudgeSelectionX(-8)
                  : null,
              child: const Text('X -8'),
            ),
            OutlinedButton(
              onPressed: canOperate && _controller.selectedCount > 0
                  ? () => _nudgeSelectionX(8)
                  : null,
              child: const Text('X +8'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDebugPanel() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('log: ${_controller.lastEventLog}'),
        Text('error_code: ${_controller.lastErrorCode}'),
        Text('error_name: ${_controller.lastErrorName}'),
        if (_controller.lastError.isNotEmpty)
          Text('error: ${_controller.lastError}'),
      ],
    );
  }

  Widget _buildInspectorPanel({
    required bool canOperate,
    required List<CoreBpmSnapshot> bpms,
    required bool includeToolsTab,
  }) {
    final tabs = <Tab>[
      if (includeToolsTab) const Tab(text: 'Tools'),
      const Tab(text: 'Meta'),
      const Tab(text: 'BPM'),
      const Tab(text: 'Edit'),
      const Tab(text: 'Debug'),
    ];
    final views = <Widget>[
      if (includeToolsTab) _buildLeftToolsPanel(canOperate),
      _buildMetaPanel(canOperate),
      _buildBpmPanel(canOperate, bpms),
      _buildEditPanel(canOperate),
      _buildDebugPanel(),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(tabs: tabs),
          Expanded(
            child: TabBarView(
              children: views,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls({
    required bool startupReady,
    required bool canOperate,
    required bool canPlayback,
    required bool isPlaying,
    required String rateLabel,
    required String positionLabel,
    required String durationLabel,
    required String beatLabel,
    required List<CoreNoteSnapshot> notes,
    required List<CoreBpmSnapshot> bpms,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _controller.runStartupSelfCheck,
                  child: const Text('Startup Check'),
                ),
                FilledButton(
                  onPressed: startupReady ? _controller.openSession : null,
                  child: const Text('Open Session'),
                ),
                FilledButton(
                  onPressed: startupReady ? _openChart : null,
                  child: const Text('Open .mc'),
                ),
                FilledButton(
                  onPressed: canOperate ? _saveChart : null,
                  child: const Text('Save .mc'),
                ),
                FilledButton(
                  onPressed: canOperate ? _exportMcz : null,
                  child: const Text('Export .mcz'),
                ),
                FilledButton(
                  onPressed: canPlayback ? _togglePlayPause : null,
                  child: Text(isPlaying ? 'Pause' : 'Play'),
                ),
                FilledButton(
                  onPressed: canPlayback ? _stopPlayback : null,
                  child: const Text('Stop'),
                ),
                PopupMenuButton<double>(
                  enabled: canPlayback,
                  tooltip: 'Playback Rate',
                  onSelected: (value) => unawaited(_setPlaybackRate(value)),
                  itemBuilder: (context) => _playbackRates
                      .map(
                        (value) => PopupMenuItem<double>(
                          value: value,
                          child: Text('${value.toStringAsFixed(2)}x'),
                        ),
                      )
                      .toList(),
                  child: Chip(label: Text('Rate $rateLabel')),
                ),
                Chip(label: Text('Time $positionLabel / $durationLabel')),
                Chip(label: Text('Beat $beatLabel')),
                OutlinedButton(
                  onPressed: canOperate
                      ? () => _setVisibleBeats(_visibleBeats * 1.2)
                      : null,
                  child: const Text('Zoom Out'),
                ),
                OutlinedButton(
                  onPressed: canOperate
                      ? () => _setVisibleBeats(_visibleBeats / 1.2)
                      : null,
                  child: const Text('Zoom In'),
                ),
                Chip(label: Text('View ${_visibleBeats.toStringAsFixed(1)}')),
                FilledButton(
                  onPressed: canOperate && _controller.canUndo
                      ? _controller.undo
                      : null,
                  child: const Text('Undo'),
                ),
                FilledButton(
                  onPressed: canOperate && _controller.canRedo
                      ? _controller.redo
                      : null,
                  child: const Text('Redo'),
                ),
                FilledButton(
                  onPressed: canOperate ? _controller.closeSession : null,
                  child: const Text('Close Session'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _jumpBeatCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Seek Beat',
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: canPlayback
                      ? () => unawaited(_seekBeatFromInput())
                      : null,
                  child: const Text('Seek'),
                ),
                ActionChip(
                  label: Text('Selected ${_controller.selectedCount}'),
                  onPressed: null,
                ),
              ],
            ),
            if (_controller.recentFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _controller.recentFiles
                    .map(
                      (path) => ActionChip(
                        label: Text(path, overflow: TextOverflow.ellipsis),
                        onPressed: () => unawaited(_openRecentChart(path)),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'file: ${_controller.currentFilePath ?? '<none>'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('notes: ${notes.length}'),
                const SizedBox(width: 12),
                Text('bpms: ${bpms.length}'),
                const SizedBox(width: 12),
                Text('dirty: ${_controller.dirty}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorSurface({
    required bool desktopLike,
    required bool canOperate,
    required List<CoreNoteSnapshot> notes,
    required List<CoreBpmSnapshot> bpms,
  }) {
    final canvasCard = Card(
      margin: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: SimpleChartCanvas(
        notes: notes,
        selectedIds: _controller.selectedNoteIds,
        mode: _controller.editorMode,
        timeDivision: _controller.timeDivision,
        viewBeat: _viewBeat,
        visibleBeats: _visibleBeats,
        playheadBeat: _controller.playheadBeat,
        onViewBeatChanged: (value) => setState(() => _viewBeat = value),
        onVisibleBeatsChanged: _setVisibleBeats,
        onHitNote: _controller.handleNoteTap,
        onPlaceNormal: _handleCanvasPlaceNormal,
        onPlaceRain: _handleCanvasPlaceRain,
        onMoveSelected: _handleMoveSelected,
        onMoveSelectedDelta: _handleMoveSelectedDelta,
        onSelectRegion: _handleCanvasSelectRegion,
        onClearSelection: _controller.clearSelection,
        onLongPressContext: (beat, x, globalPosition) => unawaited(
          _showCanvasContextMenu(
            beat: beat,
            x: x,
            globalPosition: globalPosition,
          ),
        ),
      ),
    );

    final densityCard = Padding(
      padding: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
      child: Card(
        child: SimpleDensityBar(
          notes: notes,
          playheadBeat: _controller.playheadBeat,
          viewBeat: _viewBeat,
          visibleBeats: _visibleBeats,
          onSeekBeat: _seekFromDensity,
        ),
      ),
    );

    if (desktopLike) {
      return Row(
        children: [
          SizedBox(
            width: 260,
            child: Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
              child: _buildLeftToolsPanel(canOperate),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: canvasCard),
                densityCard,
              ],
            ),
          ),
          SizedBox(
            width: 340,
            child: Card(
              margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
              child: _buildInspectorPanel(
                canOperate: canOperate,
                bpms: bpms,
                includeToolsTab: false,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: canvasCard),
              densityCard,
            ],
          ),
        ),
        SizedBox(
          height: 300,
          child: Card(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _buildInspectorPanel(
              canOperate: canOperate,
              bpms: bpms,
              includeToolsTab: true,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _controller.startupReport;
    final notes = _controller.notes;
    final bpms = _controller.bpms;
    final startupReady = widget.forceStartupReady ?? (report?.success ?? false);
    final canOperate = startupReady && _controller.sessionOpen;
    final playbackStatus = _controller.playbackStatus;
    final isPlaying = playbackStatus == PlaybackStatus.playing;
    final canPlayback = canOperate;
    final rateLabel = '${_controller.playbackRate.toStringAsFixed(2)}x';
    final durationLabel = _controller.durationMs > 0
        ? _formatMs(_controller.durationMs)
        : '--:--.--';
    final positionLabel = _formatMs(_controller.playheadMs);
    final beatLabel = _controller.playheadBeat.toStringAsFixed(3);

    return Scaffold(
      appBar: AppBar(title: const Text('Malody Catch Mobile Editor')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktopLike = constraints.maxWidth >= _desktopLikeMinWidth;
          final topPanelHeight = desktopLike ? 232.0 : 188.0;
          return Column(
            children: [
              SizedBox(
                height: topPanelHeight,
                child: SingleChildScrollView(
                  child: _buildTopControls(
                    startupReady: startupReady,
                    canOperate: canOperate,
                    canPlayback: canPlayback,
                    isPlaying: isPlaying,
                    rateLabel: rateLabel,
                    positionLabel: positionLabel,
                    durationLabel: durationLabel,
                    beatLabel: beatLabel,
                    notes: notes,
                    bpms: bpms,
                  ),
                ),
              ),
              Expanded(
                child: _buildEditorSurface(
                  desktopLike: desktopLike,
                  canOperate: canOperate,
                  notes: notes,
                  bpms: bpms,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _handleLifecyclePause();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _handleLifecycleResume();
    }
  }
}
