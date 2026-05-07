import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'core/chart_document_controller.dart';
import 'core/native_core.dart';
import 'io/chart_archive.dart';
import 'io/chart_file_picker.dart';
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
    this.runStartupSelfCheckOnInit = true,
    this.forceStartupReady,
  });

  final ChartDocumentController? controller;
  final ChartFilePickerPort? filePicker;
  final ChartArchivePort? chartArchive;
  final ChartWorkspacePort? chartWorkspace;
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
    this.runStartupSelfCheckOnInit = true,
    this.forceStartupReady,
  });

  final ChartDocumentController? controller;
  final ChartFilePickerPort? filePicker;
  final ChartArchivePort? chartArchive;
  final ChartWorkspacePort? chartWorkspace;
  final bool runStartupSelfCheckOnInit;
  final bool? forceStartupReady;

  @override
  State<MobileEditorPage> createState() => _MobileEditorPageState();
}

class _MobileEditorPageState extends State<MobileEditorPage>
    with WidgetsBindingObserver {
  static const double _visibleBeatWindow = 16.0;
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
  late final bool _ownsController;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _artistCtrl = TextEditingController();
  final TextEditingController _difficultyCtrl = TextEditingController();
  final TextEditingController _audioCtrl = TextEditingController();
  final TextEditingController _backgroundCtrl = TextEditingController();
  final TextEditingController _offsetCtrl = TextEditingController();
  final TextEditingController _speedCtrl = TextEditingController();

  double _viewBeat = 0;

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
    final high = _viewBeat + _visibleBeatWindow;
    if (head < low || head > high) {
      _viewBeat = (head - _visibleBeatWindow * 0.75).clamp(0.0, 1000000.0);
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
      await _controller.exportMczFile(
        outputPath: targetPath,
        archive: _chartArchive,
        workspace: _chartWorkspace,
      );
    } catch (e) {
      _controller.reportExternalError(
        event: 'mcz_export_failed',
        message: 'mcz_export_picker_exception:$e',
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
      _viewBeat = (beat - _visibleBeatWindow * 0.75).clamp(0.0, 1000000.0);
    });
    unawaited(_controller.seekToBeat(beat));
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
    _controller.addNormalNoteAtBeat(beat: beat, x: x);
  }

  void _handleCanvasPlaceRain(double beat, int x) {
    _controller.addRainNoteAtBeat(beat: beat, x: x);
  }

  void _handleMoveSelected(double beat, int x) {
    _controller.moveSelectedNoteTo(beat: beat, x: x);
  }

  void _handleLifecyclePause() {
    unawaited(_controller.handleAppPaused());
    if (_controller.sessionOpen && _controller.dirty) {
      _controller.saveDraftToMemory();
    }
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
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          dense: true,
          title: const Text('Selection'),
          subtitle: Text('count=${_controller.selectedCount}'),
        ),
        FilledButton.tonal(
          onPressed: canOperate && _controller.selectedCount > 0
              ? _deleteSelectedNotes
              : null,
          child: const Text('Delete Selected Notes'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: canOperate && _controller.selectedCount > 0
              ? _copySelectedNotes
              : null,
          child: const Text('Copy Selected Notes'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: canOperate && _controller.hasClipboardNotes
              ? _pasteNotesAtViewBeat
              : null,
          child: const Text('Paste Notes At View Beat'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: canOperate && _controller.selectedCount > 0
              ? _controller.clearSelection
              : null,
          child: const Text('Clear Selection'),
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

  Widget _buildInspectorPanel(bool canOperate, List<CoreBpmSnapshot> bpms) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Meta'),
              Tab(text: 'BPM'),
              Tab(text: 'Edit'),
              Tab(text: 'Debug'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildMetaPanel(canOperate),
                _buildBpmPanel(canOperate, bpms),
                _buildEditPanel(canOperate),
                _buildDebugPanel(),
              ],
            ),
          ),
        ],
      ),
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
      body: Column(
        children: [
          SizedBox(
            height: 192,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _controller.runStartupSelfCheck,
                          child: const Text('Startup Check'),
                        ),
                        FilledButton(
                          onPressed: startupReady
                              ? _controller.openSession
                              : null,
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
                          onSelected: (value) =>
                              unawaited(_setPlaybackRate(value)),
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
                        Chip(
                          label: Text('Time $positionLabel / $durationLabel'),
                        ),
                        Chip(label: Text('Beat $beatLabel')),
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
                          onPressed: canOperate
                              ? _controller.closeSession
                              : null,
                          child: const Text('Close Session'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'file: ${_controller.currentFilePath ?? '<none>'}',
                          ),
                        ),
                        Text('notes: ${notes.length}'),
                        const SizedBox(width: 12),
                        Text('bpms: ${bpms.length}'),
                        const SizedBox(width: 12),
                        Text('dirty: ${_controller.dirty}'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: EditorMode.values
                          .map(
                            (mode) => ChoiceChip(
                              label: Text(mode.name),
                              selected: _controller.editorMode == mode,
                              onSelected: canOperate
                                  ? (_) => _controller.setEditorMode(mode)
                                  : null,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: Text('Selected ${_controller.selectedCount}'),
                          onPressed: null,
                        ),
                        FilledButton.tonal(
                          onPressed: canOperate && _controller.selectedCount > 0
                              ? _deleteSelectedNotes
                              : null,
                          child: const Text('Delete Selected'),
                        ),
                        FilledButton.tonal(
                          onPressed: canOperate && _controller.selectedCount > 0
                              ? _copySelectedNotes
                              : null,
                          child: const Text('Copy Selected'),
                        ),
                        FilledButton.tonal(
                          onPressed: canOperate && _controller.hasClipboardNotes
                              ? _pasteNotesAtViewBeat
                              : null,
                          child: const Text('Paste @ View'),
                        ),
                        OutlinedButton(
                          onPressed: canOperate && _controller.selectedCount > 0
                              ? _controller.clearSelection
                              : null,
                          child: const Text('Clear Selection'),
                        ),
                      ],
                    ),
                  ),
                  if (_controller.recentFiles.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _controller.recentFiles
                              .map(
                                (path) => ActionChip(
                                  label: Text(
                                    path,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: () =>
                                      _controller.openChartFile(path),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(12),
                    clipBehavior: Clip.antiAlias,
                    child: SimpleChartCanvas(
                      notes: notes,
                      selectedIds: _controller.selectedNoteIds,
                      mode: _controller.editorMode,
                      viewBeat: _viewBeat,
                      playheadBeat: _controller.playheadBeat,
                      onViewBeatChanged: (value) =>
                          setState(() => _viewBeat = value),
                      onHitNote: _controller.handleNoteTap,
                      onPlaceNormal: _handleCanvasPlaceNormal,
                      onPlaceRain: _handleCanvasPlaceRain,
                      onMoveSelected: _handleMoveSelected,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    right: 12,
                    top: 12,
                    bottom: 12,
                  ),
                  child: Card(
                    child: SimpleDensityBar(
                      notes: notes,
                      playheadBeat: _controller.playheadBeat,
                      onSeekBeat: _seekFromDensity,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: _buildInspectorPanel(canOperate, bpms),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _handleLifecyclePause();
    }
  }
}
