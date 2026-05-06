import 'dart:io';

import 'package:flutter/material.dart';

import 'core/chart_document_controller.dart';
import 'core/native_core.dart';
import 'io/chart_file_picker.dart';
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
    this.runStartupSelfCheckOnInit = true,
    this.forceStartupReady,
  });

  final ChartDocumentController? controller;
  final ChartFilePickerPort? filePicker;
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
    this.runStartupSelfCheckOnInit = true,
    this.forceStartupReady,
  });

  final ChartDocumentController? controller;
  final ChartFilePickerPort? filePicker;
  final bool runStartupSelfCheckOnInit;
  final bool? forceStartupReady;

  @override
  State<MobileEditorPage> createState() => _MobileEditorPageState();
}

class _MobileEditorPageState extends State<MobileEditorPage>
    with WidgetsBindingObserver {
  late final ChartDocumentController _controller;
  late final ChartFilePickerPort _filePicker;
  late final bool _ownsController;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _artistCtrl = TextEditingController();
  final TextEditingController _difficultyCtrl = TextEditingController();

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
    setState(() {});
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
      _controller.openChartFile(path.trim());
    } catch (e) {
      _controller.reportExternalError(
        event: 'open_chart_failed',
        message: 'open_picker_exception:$e',
      );
    }
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

        final fileName = await _requestSaveFileName();
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

  Future<String?> _requestSaveFileName() async {
    var candidate = 'mobile_chart.mc';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Save File Name'),
          content: TextFormField(
            initialValue: candidate,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'chart_name.mc'),
            onChanged: (value) => candidate = value,
            onFieldSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value),
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

  void _applyMeta() {
    final next = _controller.metadata.copyWith(
      title: _titleCtrl.text.trim(),
      artist: _artistCtrl.text.trim(),
      difficulty: _difficultyCtrl.text.trim().isEmpty
          ? 'Normal'
          : _difficultyCtrl.text.trim(),
    );
    _controller.updateMetadata(next);
  }

  void _addBpm() {
    _controller.addBpmEntry(
      beat: const CoreBeat(measure: 0, numerator: 0, denominator: 1),
      bpm: 120,
    );
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

  void _handleLifecycleSave() {
    if (_controller.sessionOpen && _controller.dirty) {
      _controller.saveDraftToMemory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _controller.startupReport;
    final notes = _controller.notes;
    final bpms = _controller.bpms;
    final startupReady = widget.forceStartupReady ?? (report?.success ?? false);
    final canOperate = startupReady && _controller.sessionOpen;

    return Scaffold(
      appBar: AppBar(title: const Text('Malody Catch Mobile Editor')),
      body: Column(
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
                          label: Text(path, overflow: TextOverflow.ellipsis),
                          onPressed: () => _controller.openChartFile(path),
                        ),
                      )
                      .toList(),
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
                      viewBeat: _viewBeat,
                      onSeekBeat: (value) => setState(() => _viewBeat = value),
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: ListView(
                    padding: const EdgeInsets.only(
                      top: 12,
                      right: 12,
                      bottom: 12,
                    ),
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
                        decoration: const InputDecoration(
                          labelText: 'Difficulty',
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: canOperate ? _applyMeta : null,
                        child: const Text('Apply Meta'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('BPM List'),
                          const Spacer(),
                          IconButton(
                            onPressed: canOperate ? _addBpm : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      ...bpms.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final bpm = entry.value;
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${bpm.beat.measure}:${bpm.beat.numerator}/${bpm.beat.denominator}',
                          ),
                          subtitle: Text('bpm=${bpm.bpm.toStringAsFixed(2)}'),
                          trailing: IconButton(
                            onPressed: canOperate
                                ? () => _controller.removeBpmEntry(idx)
                                : null,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Text('log: ${_controller.lastEventLog}'),
                      Text('error_code: ${_controller.lastErrorCode}'),
                      Text('error_name: ${_controller.lastErrorName}'),
                      if (_controller.lastError.isNotEmpty)
                        Text('error: ${_controller.lastError}'),
                    ],
                  ),
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
      _handleLifecycleSave();
    }
  }
}
