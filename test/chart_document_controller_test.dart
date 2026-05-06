import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:malody_catch_mobile/core/chart_document_controller.dart';
import 'package:malody_catch_mobile/core/mc_chart_io.dart';
import 'package:malody_catch_mobile/core/native_core.dart';
import 'package:path/path.dart' as path;

import 'support/fake_chart_io_ports.dart';
import 'support/fake_core_session.dart';

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

  test('controller supports bpm/meta and batch move', () {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    controller.openSession();
    expect(controller.bpms.length, 1);

    controller.addBpmEntry(
      beat: const CoreBeat(measure: 8, numerator: 0, denominator: 1),
      bpm: 160,
    );
    expect(controller.bpms.length, 2);

    final nextMeta = controller.metadata.copyWith(title: 't1', artist: 'a1');
    controller.updateMetadata(nextMeta);
    expect(controller.metadata.title, 't1');

    controller.addNormalNote(measure: 2, numerator: 0, denominator: 1, x: 120);
    final original = controller.notes.first;
    controller.applyNoteBatch(<CoreNoteBatchOp>[
      CoreNoteBatchOp(
        opType: CoreNoteBatchOpType.move,
        note: CoreNoteSnapshot(
          id: original.id,
          type: original.type,
          beat: const CoreBeat(measure: 4, numerator: 0, denominator: 1),
          endBeat: original.endBeat,
          x: 300,
          sound: original.sound,
          volume: original.volume,
          offsetMs: original.offsetMs,
        ),
      ),
    ]);
    expect(controller.notes.first.beat.measure, 4);
    expect(controller.notes.first.x, 300);
  });

  test('controller .mc save and reopen roundtrip', () {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    controller.openSession();
    controller.addNormalNote(measure: 1, numerator: 0, denominator: 1, x: 200);
    controller.updateMetadata(controller.metadata.copyWith(title: 'Roundtrip'));

    final tempDir = Directory.systemTemp.createTempSync('malody_mobile_test');
    final path = '${tempDir.path}${Platform.pathSeparator}roundtrip.mc';

    final saved = controller.saveChart(path: path);
    expect(saved, isTrue);
    expect(File(path).existsSync(), isTrue);

    final another = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    final opened = another.openChartFile(path);
    expect(opened, isTrue);
    expect(another.notes.length, 1);
    expect(another.metadata.title, 'Roundtrip');

    tempDir.deleteSync(recursive: true);
  });

  test('controller keeps mcz fallback on open/save', () {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    final opened = controller.openChartFile(r'C:\tmp\fallback_case.mcz');
    expect(opened, isFalse);
    expect(controller.lastError, contains('mcz_fallback_required'));

    controller.openSession();
    final saved = controller.saveChart(path: r'C:\tmp\fallback_case.mcz');
    expect(saved, isFalse);
    expect(controller.lastError, contains('mcz_fallback_required'));
  });

  test(
    'controller imports mcz into workspace and rewrites resource paths',
    () async {
      final controller = ChartDocumentController(
        sessionFactory: () => FakeCoreSession(),
      );

      final root = Directory.systemTemp.createTempSync('mobile_mcz_import_ok');
      final mczPath = path.join(root.path, 'demo.mcz');
      File(mczPath).writeAsBytesSync(const <int>[1, 2, 3]);

      final archive = FakeChartArchive(
        onExtract: (source, target) async {
          final chartPath = path.join(target, '0', 'hard.mc');
          final chartFile = File(chartPath);
          chartFile.parent.createSync(recursive: true);
          chartFile.writeAsStringSync(
            McChartIo.encode(
              metadata: CoreMetadataSnapshot.empty().copyWith(
                title: 'ImportedChart',
                artist: 'Importer',
                difficulty: 'Hard',
                audioFile: 'audio/song.ogg',
                backgroundFile: 'bg/cover.png',
              ),
              bpms: const <CoreBpmSnapshot>[
                CoreBpmSnapshot(
                  beat: CoreBeat(measure: 0, numerator: 0, denominator: 1),
                  bpm: 120,
                ),
              ],
              notes: const <CoreNoteSnapshot>[
                CoreNoteSnapshot(
                  id: 'n0',
                  type: 1,
                  beat: CoreBeat(measure: 1, numerator: 0, denominator: 1),
                  endBeat: CoreBeat(measure: 1, numerator: 0, denominator: 1),
                  x: -1,
                  sound: 'sfx/hit.wav',
                  volume: 100,
                  offsetMs: 0,
                ),
              ],
            ),
          );
          final audioFile = File(path.join(target, '0', 'audio', 'song.ogg'));
          audioFile.parent.createSync(recursive: true);
          audioFile.writeAsStringSync('audio');
          final backgroundFile = File(
            path.join(target, '0', 'bg', 'cover.png'),
          );
          backgroundFile.parent.createSync(recursive: true);
          backgroundFile.writeAsStringSync('bg');
          final sfxFile = File(path.join(target, '0', 'sfx', 'hit.wav'));
          sfxFile.parent.createSync(recursive: true);
          sfxFile.writeAsStringSync('sfx');
          return <String>[
            chartPath,
            path.join(target, '0', 'audio', 'song.ogg'),
            path.join(target, '0', 'bg', 'cover.png'),
            path.join(target, '0', 'sfx', 'hit.wav'),
          ];
        },
      );
      final workspace = FakeChartWorkspace(root.path);

      final imported = await controller.importMczFile(
        mczPath: mczPath,
        archive: archive,
        workspace: workspace,
        chooseChart: (charts) async => charts.first.mcPath,
      );

      expect(imported, isTrue);
      expect(controller.lastEventLog, 'mcz_import_ok');
      expect(controller.currentFilePath, isNotNull);
      expect(File(controller.currentFilePath!).existsSync(), isTrue);

      final importedRoot = File(controller.currentFilePath!).parent.path;
      expect(
        File(path.join(importedRoot, 'audio', 'song.ogg')).existsSync(),
        isTrue,
      );
      expect(
        File(path.join(importedRoot, 'bg', 'cover.png')).existsSync(),
        isTrue,
      );
      expect(
        File(path.join(importedRoot, 'sfx', 'hit.wav')).existsSync(),
        isTrue,
      );

      final mc = McChartIo.parse(
        File(controller.currentFilePath!).readAsStringSync(),
      );
      expect(mc.metadata.audioFile, 'audio/song.ogg');
      expect(mc.metadata.backgroundFile, 'bg/cover.png');
      expect(
        mc.notes.where((note) => note.type == 1).first.sound,
        'sfx/hit.wav',
      );

      root.deleteSync(recursive: true);
    },
  );

  test('controller import mcz supports multi-chart selection', () async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    final root = Directory.systemTemp.createTempSync('mobile_mcz_multi');
    final mczPath = path.join(root.path, 'multi.mcz');
    File(mczPath).writeAsStringSync('x');

    final archive = FakeChartArchive(
      onExtract: (source, target) async {
        final easy = path.join(target, '0', 'easy.mc');
        final hard = path.join(target, '0', 'hard.mc');
        final easyFile = File(easy);
        easyFile.parent.createSync(recursive: true);
        easyFile.writeAsStringSync(
          McChartIo.encode(
            metadata: CoreMetadataSnapshot.empty().copyWith(
              title: 'EasyOne',
              artist: 'A',
              difficulty: 'Easy',
              audioFile: 'song.ogg',
            ),
            bpms: const <CoreBpmSnapshot>[
              CoreBpmSnapshot(
                beat: CoreBeat(measure: 0, numerator: 0, denominator: 1),
                bpm: 120,
              ),
            ],
            notes: const <CoreNoteSnapshot>[],
          ),
        );
        final hardFile = File(hard);
        hardFile.writeAsStringSync(
          McChartIo.encode(
            metadata: CoreMetadataSnapshot.empty().copyWith(
              title: 'HardOne',
              artist: 'A',
              difficulty: 'Hard',
              audioFile: 'song.ogg',
            ),
            bpms: const <CoreBpmSnapshot>[
              CoreBpmSnapshot(
                beat: CoreBeat(measure: 0, numerator: 0, denominator: 1),
                bpm: 120,
              ),
            ],
            notes: const <CoreNoteSnapshot>[],
          ),
        );
        File(path.join(target, '0', 'song.ogg')).writeAsStringSync('audio');
        return <String>[easy, hard];
      },
    );
    final workspace = FakeChartWorkspace(root.path);

    final imported = await controller.importMczFile(
      mczPath: mczPath,
      archive: archive,
      workspace: workspace,
      chooseChart: (charts) async => charts
          .firstWhere((candidate) => candidate.difficulty == 'Hard')
          .mcPath,
    );

    expect(imported, isTrue);
    expect(controller.metadata.title, 'HardOne');
    expect(controller.metadata.difficulty, 'Hard');

    root.deleteSync(recursive: true);
  });

  test(
    'controller import mcz fails when referenced resource is missing',
    () async {
      final controller = ChartDocumentController(
        sessionFactory: () => FakeCoreSession(),
      );

      final root = Directory.systemTemp.createTempSync('mobile_mcz_missing');
      final mczPath = path.join(root.path, 'missing.mcz');
      File(mczPath).writeAsStringSync('x');

      final archive = FakeChartArchive(
        onExtract: (source, target) async {
          final chartPath = path.join(target, '0', 'missing.mc');
          final chartFile = File(chartPath);
          chartFile.parent.createSync(recursive: true);
          chartFile.writeAsStringSync(
            McChartIo.encode(
              metadata: CoreMetadataSnapshot.empty().copyWith(
                title: 'MissingRef',
                artist: 'A',
                difficulty: 'Normal',
                audioFile: 'audio/not_found.ogg',
              ),
              bpms: const <CoreBpmSnapshot>[
                CoreBpmSnapshot(
                  beat: CoreBeat(measure: 0, numerator: 0, denominator: 1),
                  bpm: 120,
                ),
              ],
              notes: const <CoreNoteSnapshot>[],
            ),
          );
          return <String>[chartPath];
        },
      );
      final workspace = FakeChartWorkspace(root.path);

      final imported = await controller.importMczFile(
        mczPath: mczPath,
        archive: archive,
        workspace: workspace,
        chooseChart: (charts) async => charts.first.mcPath,
      );

      expect(imported, isFalse);
      expect(controller.lastError, contains('mcz_import_resource_missing'));

      root.deleteSync(recursive: true);
    },
  );

  test(
    'controller exports mcz with mc and referenced resources only',
    () async {
      final controller = ChartDocumentController(
        sessionFactory: () => FakeCoreSession(),
      );
      controller.openSession();
      controller.updateMetadata(
        controller.metadata.copyWith(
          title: 'ExportTarget',
          artist: 'Exporter',
          difficulty: 'Hard',
          audioFile: 'audio/song.ogg',
          backgroundFile: 'bg/cover.png',
        ),
      );
      controller.addSoundNote(
        beat: const CoreBeat(measure: 1, numerator: 0, denominator: 1),
        sound: 'sfx/hit.wav',
      );

      final root = Directory.systemTemp.createTempSync('mobile_mcz_export_ok');
      final chartPath = path.join(root.path, 'export_case.mc');
      final saved = controller.saveChart(path: chartPath);
      expect(saved, isTrue);

      final audioFile = File(path.join(root.path, 'audio', 'song.ogg'));
      audioFile.parent.createSync(recursive: true);
      audioFile.writeAsStringSync('audio');
      final backgroundFile = File(path.join(root.path, 'bg', 'cover.png'));
      backgroundFile.parent.createSync(recursive: true);
      backgroundFile.writeAsStringSync('bg');
      final sfxFile = File(path.join(root.path, 'sfx', 'hit.wav'));
      sfxFile.parent.createSync(recursive: true);
      sfxFile.writeAsStringSync('hit');
      File(path.join(root.path, 'unused.bin')).writeAsStringSync('unused');

      final archive = FakeChartArchive();
      final workspace = FakeChartWorkspace(root.path);
      final outputPath = path.join(root.path, 'export_case.mcz');

      final ok = await controller.exportMczFile(
        outputPath: outputPath,
        archive: archive,
        workspace: workspace,
      );

      expect(ok, isTrue);
      expect(archive.lastCreateOutputPath, outputPath);
      final archivePaths =
          archive.lastCreateFiles?.map((entry) => entry.archivePath).toSet() ??
          <String>{};
      expect(archivePaths.contains('0/export_case.mc'), isTrue);
      expect(archivePaths.contains('0/audio/song.ogg'), isTrue);
      expect(archivePaths.contains('0/bg/cover.png'), isTrue);
      expect(archivePaths.contains('0/sfx/hit.wav'), isTrue);
      expect(archivePaths.contains('0/unused.bin'), isFalse);

      root.deleteSync(recursive: true);
    },
  );

  test('controller export mcz fails on missing resource', () async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    controller.openSession();
    controller.updateMetadata(
      controller.metadata.copyWith(
        title: 'ExportMissing',
        artist: 'Exporter',
        difficulty: 'Hard',
        audioFile: 'audio/missing.ogg',
      ),
    );

    final root = Directory.systemTemp.createTempSync(
      'mobile_mcz_export_missing',
    );
    final chartPath = path.join(root.path, 'export_missing.mc');
    controller.saveChart(path: chartPath);

    final archive = FakeChartArchive();
    final workspace = FakeChartWorkspace(root.path);
    final ok = await controller.exportMczFile(
      outputPath: path.join(root.path, 'export_missing.mcz'),
      archive: archive,
      workspace: workspace,
    );

    expect(ok, isFalse);
    expect(controller.lastError, contains('mcz_export_resource_missing'));
    expect(archive.lastCreateFiles, isNull);

    root.deleteSync(recursive: true);
  });
}
