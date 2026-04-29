import 'package:flutter/material.dart';

import 'core/chart_document_controller.dart';

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

class _CoreSmokePageState extends State<CoreSmokePage> {
  late final ChartDocumentController _controller;
  int _seed = 0;

  @override
  void initState() {
    super.initState();
    _controller = ChartDocumentController()
      ..addListener(_onControllerChanged)
      ..runStartupSelfCheck();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final report = _controller.startupReport;
    final notes = _controller.notes;
    final selected = _controller.selectedNoteIds;

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
              Text('startup_ok: ${report?.success ?? false}'),
              if (report?.errorMessage != null)
                Text('startup_error: ${report!.errorMessage}'),
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
                    onPressed: _openSession,
                    child: const Text('Open Session'),
                  ),
                  ElevatedButton(
                    onPressed: _controller.closeSession,
                    child: const Text('Close Session'),
                  ),
                  ElevatedButton(
                    onPressed: _addNormalNote,
                    child: const Text('Add Note'),
                  ),
                  ElevatedButton(
                    onPressed: _controller.removeLastNote,
                    child: const Text('Remove Last'),
                  ),
                  ElevatedButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => _controller.removeNoteById(selected.first),
                    child: const Text('Remove Selected'),
                  ),
                  ElevatedButton(
                    onPressed: _controller.canUndo ? _controller.undo : null,
                    child: const Text('Undo'),
                  ),
                  ElevatedButton(
                    onPressed: _controller.canRedo ? _controller.redo : null,
                    child: const Text('Redo'),
                  ),
                ],
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
                          subtitle: Text('x=${note.x}  type=${note.type}'),
                          selected: selected.contains(note.id),
                          onTap: () => _controller.selectSingle(note.id),
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
}
