import 'package:flutter/material.dart';

import 'core/chart_document_controller.dart';
import 'core/native_core.dart';

void main() {
  runApp(const MalodyCatchMobileApp());
}

class MalodyCatchMobileApp extends StatelessWidget {
  const MalodyCatchMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Malody Catch Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1C6D52)),
      ),
      home: const CoreSmokePage(),
    );
  }
}

class CoreSmokePage extends StatefulWidget {
  const CoreSmokePage({super.key});

  @override
  State<CoreSmokePage> createState() => _CoreSmokePageState();
}

class _CoreSmokePageState extends State<CoreSmokePage>
    with WidgetsBindingObserver {
  late final ChartDocumentController _controller;
  int _seed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ChartDocumentController()
      ..addListener(_onControllerChanged)
      ..runStartupSelfCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openSession() {
    _controller.openSession();
  }

  void _addNormalNote() {
    _seed += 1;
    _controller.addNormalNote(
      measure: _seed,
      numerator: 0,
      denominator: 1,
      x: 128 + (_seed % 4) * 64,
    );
  }

  void _addRainNote() {
    _seed += 1;
    _controller.addRainNote(
      beat: CoreBeat(measure: _seed, numerator: 0, denominator: 1),
      endBeat: CoreBeat(measure: _seed, numerator: 1, denominator: 1),
      x: 96 + (_seed % 5) * 64,
    );
  }

  void _addSoundNote() {
    _seed += 1;
    _controller.addSoundNote(
      beat: CoreBeat(measure: _seed, numerator: 0, denominator: 1),
      sound: 'mobile_sfx/tap.wav',
      volume: 90,
      offsetMs: 0,
    );
  }

  void _moveSelectedRain() {
    _seed += 1;
    _controller.moveSelectedRainNote(
      beat: CoreBeat(measure: _seed, numerator: 0, denominator: 1),
      endBeat: CoreBeat(measure: _seed, numerator: 1, denominator: 1),
      x: 128 + (_seed % 3) * 80,
    );
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
    final selected = _controller.selectedNoteIds;
    final startupReady = report?.success ?? false;
    final canOperateSession = startupReady && _controller.sessionOpen;
    final canMoveSelectedRain =
        canOperateSession &&
        selected.length == 1 &&
        notes.any((note) => note.id == selected.first && note.type == 3);

    return Scaffold(
      appBar: AppBar(title: const Text('Core FFI Smoke')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('library_loaded: ${report?.libraryLoaded ?? false}'),
              Text('session_create_probe: ${report?.sessionCreated ?? false}'),
              Text('core_version: ${report?.coreVersion ?? ''}'),
              Text('abi_version: ${report?.abiVersion ?? -1}'),
              Text(
                'abi_min_required: ${report?.minimumAbiVersion ?? mceMinimumAbiVersion}',
              ),
              Text('startup_ok: ${report?.success ?? false}'),
              if (report?.errorMessage != null)
                Text('startup_error: ${report!.errorMessage}'),
              if (!startupReady)
                const Text(
                  'status: startup check required (or ABI mismatch), editing actions are disabled',
                ),
              const SizedBox(height: 12),
              Text('session_open: ${_controller.sessionOpen}'),
              Text('note_count: ${notes.length}'),
              Text('can_undo: ${_controller.canUndo}'),
              Text('can_redo: ${_controller.canRedo}'),
              Text('dirty: ${_controller.dirty}'),
              Text('revision: ${_controller.revision}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _controller.runStartupSelfCheck,
                    child: const Text('Startup Check'),
                  ),
                  ElevatedButton(
                    onPressed: startupReady ? _openSession : null,
                    child: const Text('Open Session'),
                  ),
                  ElevatedButton(
                    onPressed: _controller.sessionOpen
                        ? _controller.closeSession
                        : null,
                    child: const Text('Close Session'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession ? _addNormalNote : null,
                    child: const Text('Add Note'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession ? _addRainNote : null,
                    child: const Text('Add Rain'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession ? _addSoundNote : null,
                    child: const Text('Add Sound'),
                  ),
                  ElevatedButton(
                    onPressed: canMoveSelectedRain ? _moveSelectedRain : null,
                    child: const Text('Move Rain'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession
                        ? _controller.removeLastNote
                        : null,
                    child: const Text('Remove Last'),
                  ),
                  ElevatedButton(
                    onPressed: !canOperateSession || selected.isEmpty
                        ? null
                        : () => _controller.removeNoteById(selected.first),
                    child: const Text('Remove Selected'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession && _controller.canUndo
                        ? _controller.undo
                        : null,
                    child: const Text('Undo'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession && _controller.canRedo
                        ? _controller.redo
                        : null,
                    child: const Text('Redo'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession
                        ? _controller.saveDraftToMemory
                        : null,
                    child: const Text('Save Draft'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession && _controller.hasDraft
                        ? _controller.restoreDraftFromMemory
                        : null,
                    child: const Text('Restore Draft'),
                  ),
                  ElevatedButton(
                    onPressed: canOperateSession
                        ? _controller.clearSelection
                        : null,
                    child: const Text('Clear Selection'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('mode:'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: EditorMode.values
                    .map(
                      (mode) => ChoiceChip(
                        label: Text(mode.name),
                        selected: _controller.editorMode == mode,
                        onSelected: canOperateSession
                            ? (_) => _controller.setEditorMode(mode)
                            : null,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text('log: ${_controller.lastEventLog}'),
              if (_controller.lastError.isNotEmpty)
                Text('error: ${_controller.lastError}'),
              const SizedBox(height: 12),
              Text('selected_count: ${selected.length}'),
              const SizedBox(height: 8),
              if (notes.isEmpty)
                const Text('notes: <empty>')
              else
                Column(
                  children: notes
                      .map(
                        (note) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${note.id}  beat=${note.beat.measure}'),
                          subtitle: Text(
                            'x=${note.x}  type=${note.type}  end=${note.endBeat.measure}:${note.endBeat.numerator}/${note.endBeat.denominator}  sound=${note.sound}',
                          ),
                          selected: selected.contains(note.id),
                          onTap: () => _controller.handleNoteTap(note.id),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
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
