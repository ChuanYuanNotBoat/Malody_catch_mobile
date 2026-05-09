import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malody_catch_mobile/core/chart_document_controller.dart';
import 'package:malody_catch_mobile/core/mc_chart_io.dart';
import 'package:malody_catch_mobile/core/native_core.dart';
import 'package:malody_catch_mobile/io/chart_file_picker.dart';
import 'package:malody_catch_mobile/io/chart_audio.dart';
import 'package:malody_catch_mobile/main.dart';
import 'package:malody_catch_mobile/ui/simple_density_bar.dart';

import 'support/fake_chart_io_ports.dart';
import 'support/fake_chart_audio.dart';
import 'support/fake_core_session.dart';

class FakeChartFilePicker implements ChartFilePickerPort {
  FakeChartFilePicker({
    this.openPath,
    this.saveDirectory,
    this.throwOnOpen = false,
    this.throwOnSaveDirectory = false,
  });

  final String? openPath;
  final String? saveDirectory;
  final bool throwOnOpen;
  final bool throwOnSaveDirectory;
  int openCallCount = 0;
  int saveDirectoryCallCount = 0;

  @override
  Future<String?> pickChartToOpen() async {
    openCallCount += 1;
    if (throwOnOpen) {
      throw StateError('open picker unavailable');
    }
    return openPath;
  }

  @override
  Future<String?> pickDirectoryForSave() async {
    saveDirectoryCallCount += 1;
    if (throwOnSaveDirectory) {
      throw StateError('save picker unavailable');
    }
    return saveDirectory;
  }
}

void main() {
  testWidgets('Mobile editor page renders', (WidgetTester tester) async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pump();

    expect(find.text('Malody Catch Mobile Editor'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Startup Check'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open Session'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open .mc'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save .mc'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Export .mcz'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('playback controls update status and rate', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late FakeChartAudio fakeAudio;
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
      audioFactory: () {
        fakeAudio = FakeChartAudio(
          initialDuration: const Duration(seconds: 90),
        );
        return fakeAudio;
      },
    );
    controller.openSession();
    controller.updateMetadata(
      controller.metadata.copyWith(
        title: 'PlaybackUI',
        audioFile: 'audio/song.ogg',
        offsetMs: 120,
      ),
    );
    final root = Directory.systemTemp.createTempSync('mobile_playback_widget');
    final chartPath = '${root.path}${Platform.pathSeparator}playback.mc';
    controller.saveChart(path: chartPath);
    final audioFile = File(
      '${root.path}${Platform.pathSeparator}audio${Platform.pathSeparator}song.ogg',
    );
    audioFile.parent.createSync(recursive: true);
    audioFile.writeAsStringSync('audio');

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pumpAndSettle();
    expect(controller.playbackStatus, PlaybackStatus.playing);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);

    await tester.tap(find.text('Rate 1.00x'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.25x').last);
    await tester.pumpAndSettle();
    expect(controller.playbackRate, 1.25);

    fakeAudio.emitPosition(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(controller.playheadMs, inInclusiveRange(1600, 1616));

    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await tester.pumpAndSettle();
    expect(controller.playheadMs, 0);

    root.deleteSync(recursive: true);
  });

  testWidgets(
    'density bar preview does not seek until commit and pauses playback',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late FakeChartAudio fakeAudio;
      final controller = ChartDocumentController(
        sessionFactory: () => FakeCoreSession(),
        audioFactory: () {
          fakeAudio = FakeChartAudio(
            initialDuration: const Duration(seconds: 120),
          );
          return fakeAudio;
        },
      );
      controller.openSession();
      controller.addNormalNote(
        measure: 12,
        numerator: 0,
        denominator: 1,
        x: 200,
      );
      controller.updateMetadata(
        controller.metadata.copyWith(
          title: 'SeekUI',
          audioFile: 'audio/song.ogg',
        ),
      );
      final root = Directory.systemTemp.createTempSync('mobile_density_seek');
      final chartPath = '${root.path}${Platform.pathSeparator}seek_case.mc';
      controller.saveChart(path: chartPath);
      final audioPath = File(
        '${root.path}${Platform.pathSeparator}audio${Platform.pathSeparator}song.ogg',
      );
      audioPath.parent.createSync(recursive: true);
      audioPath.writeAsStringSync('audio');

      await tester.pumpWidget(
        MalodyCatchMobileApp(
          controller: controller,
          runStartupSelfCheckOnInit: false,
          forceStartupReady: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Play'));
      await tester.pumpAndSettle();

      final density = find.byType(SimpleDensityBar);
      expect(density, findsOneWidget);
      final densityWidget = tester.widget<SimpleDensityBar>(density);
      densityWidget.onSeekGestureStart?.call();
      await tester.pumpAndSettle();
      densityWidget.onSeekPreviewBeat(12.0);
      await tester.pumpAndSettle();

      expect(fakeAudio.seekCallCount, 0);
      expect(controller.playbackStatus, PlaybackStatus.paused);

      densityWidget.onSeekCommitBeat(12.0);
      await tester.pumpAndSettle();

      expect(fakeAudio.seekCallCount, 1);
      expect(controller.playheadMs, greaterThan(0));
      expect(controller.playheadBeat, greaterThan(0));

      root.deleteSync(recursive: true);
    },
  );

  testWidgets('playback missing audio shows error text', (
    WidgetTester tester,
  ) async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
      audioFactory: () => FakeChartAudio(),
    );
    controller.openSession();
    controller.updateMetadata(
      controller.metadata.copyWith(
        title: 'MissingAudioUI',
        audioFile: 'audio/missing.ogg',
      ),
    );
    final root = Directory.systemTemp.createTempSync('mobile_missing_audio_ui');
    final chartPath = '${root.path}${Platform.pathSeparator}missing_audio.mc';
    controller.saveChart(path: chartPath);

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pumpAndSettle();

    expect(
      controller.lastError,
      contains('audio_playback_audio_source_missing'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();
    expect(find.textContaining('error: audio_playback_'), findsOneWidget);

    root.deleteSync(recursive: true);
  });

  testWidgets('Open .mc uses picker path and imports chart', (
    WidgetTester tester,
  ) async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    final tempDir = Directory.systemTemp.createTempSync('mobile_open_mc');
    final chartPath = '${tempDir.path}${Platform.pathSeparator}open_case.mc';
    final content = McChartIo.encode(
      metadata: CoreMetadataSnapshot.empty().copyWith(title: 'PickerOpen'),
      bpms: const <CoreBpmSnapshot>[
        CoreBpmSnapshot(
          beat: CoreBeat(measure: 0, numerator: 0, denominator: 1),
          bpm: 120,
        ),
      ],
      notes: const <CoreNoteSnapshot>[
        CoreNoteSnapshot(
          id: 'n1',
          type: 0,
          beat: CoreBeat(measure: 1, numerator: 0, denominator: 1),
          endBeat: CoreBeat(measure: 1, numerator: 0, denominator: 1),
          x: 220,
          sound: '',
          volume: 100,
          offsetMs: 0,
        ),
      ],
    );
    File(chartPath).writeAsStringSync(content);

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: FakeChartFilePicker(openPath: chartPath),
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Open .mc'));
    await tester.pumpAndSettle();

    expect(controller.currentFilePath, chartPath);
    expect(controller.notes.length, 1);
    expect(controller.metadata.title, 'PickerOpen');

    tempDir.deleteSync(recursive: true);
  });

  testWidgets('Open .mc with mcz path routes to mcz import errors', (
    WidgetTester tester,
  ) async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: FakeChartFilePicker(openPath: r'C:\tmp\x.mcz'),
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Open .mc'));
    await tester.pumpAndSettle();

    expect(controller.lastError, contains('mcz_import_file_not_found'));
  });

  testWidgets('Open .mc imports mcz via archive/workspace flow', (
    WidgetTester tester,
  ) async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    final root = Directory.systemTemp.createTempSync('widget_mcz_import');
    final mczPath = '${root.path}${Platform.pathSeparator}widget_import.mcz';
    File(mczPath).writeAsStringSync('x');
    final picker = FakeChartFilePicker(openPath: mczPath);

    final archive = FakeChartArchive(
      onExtract: (source, target) async {
        final chartPath =
            '$target${Platform.pathSeparator}0${Platform.pathSeparator}main.mc';
        final chartFile = File(chartPath);
        chartFile.parent.createSync(recursive: true);
        chartFile.writeAsStringSync(
          McChartIo.encode(
            metadata: CoreMetadataSnapshot.empty().copyWith(
              title: 'WidgetMcz',
              artist: 'Tester',
              difficulty: 'Normal',
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
        final soundFile = File(
          '$target${Platform.pathSeparator}0${Platform.pathSeparator}song.ogg',
        );
        soundFile.writeAsStringSync('audio');
        return <String>[chartPath];
      },
    );
    final workspace = FakeChartWorkspace(root.path);

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: picker,
        chartArchive: archive,
        chartWorkspace: workspace,
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();
    final openButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Open .mc'),
    );
    expect(openButton.onPressed, isNotNull);

    await tester.runAsync(() async {
      openButton.onPressed!.call();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();
    expect(picker.openCallCount, 1);
    expect(archive.lastExtractMczPath, mczPath);

    root.deleteSync(recursive: true);
  });

  testWidgets('Open .mc reports picker exception', (WidgetTester tester) async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: FakeChartFilePicker(throwOnOpen: true),
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Open .mc'));
    await tester.pumpAndSettle();

    expect(controller.lastError, contains('open_picker_exception'));
  });

  testWidgets('Save .mc picks directory then file name', (
    WidgetTester tester,
  ) async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    controller.openSession();
    controller.addNormalNote(measure: 1, numerator: 0, denominator: 1, x: 180);

    final tempDir = Directory.systemTemp.createTempSync('mobile_save_mc');

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: FakeChartFilePicker(saveDirectory: tempDir.path),
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save .mc'));
    await tester.pumpAndSettle();

    expect(find.text('Save File Name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, 'widget_save');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    final savedPath = '${tempDir.path}${Platform.pathSeparator}widget_save.mc';
    expect(File(savedPath).existsSync(), isTrue);
    expect(controller.currentFilePath, savedPath);

    tempDir.deleteSync(recursive: true);
  });

  testWidgets('Save .mc reports directory cancel', (WidgetTester tester) async {
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    controller.openSession();

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: FakeChartFilePicker(saveDirectory: null),
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save .mc'));
    await tester.pumpAndSettle();

    expect(controller.lastError, contains('save_directory_not_selected'));
  });

  testWidgets('Export .mcz picks directory then file name', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    controller.openSession();
    controller.addNormalNote(measure: 1, numerator: 0, denominator: 1, x: 220);

    final root = Directory.systemTemp.createTempSync('mobile_export_widget');
    final sourceChartPath = '${root.path}${Platform.pathSeparator}source.mc';
    controller.saveChart(path: sourceChartPath);

    final archive = FakeChartArchive();
    final workspace = FakeChartWorkspace(root.path);
    final share = FakeChartShare();

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: FakeChartFilePicker(saveDirectory: root.path),
        chartArchive: archive,
        chartWorkspace: workspace,
        chartShare: share,
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    final exportButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export .mcz'),
    );
    await tester.runAsync(() async {
      exportButton.onPressed!.call();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();

    expect(find.text('Export File Name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, 'bundle_out');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();

    final outputPath = '${root.path}${Platform.pathSeparator}bundle_out.mcz';
    expect(archive.lastCreateOutputPath, outputPath);
    expect(
      archive.lastCreateFiles?.any(
            (entry) => entry.archivePath == '0/source.mc',
          ) ??
          false,
      isTrue,
    );
    expect(share.shareCallCount, 1);
    expect(share.lastFilePath, outputPath);

    root.deleteSync(recursive: true);
  });

  testWidgets('Export .mcz reports directory cancel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    controller.openSession();
    final root = Directory.systemTemp.createTempSync('mcz_export_cancel');
    final sourcePath = '${root.path}${Platform.pathSeparator}export_source.mc';
    controller.saveChart(path: sourcePath);

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: FakeChartFilePicker(saveDirectory: null),
        chartArchive: FakeChartArchive(),
        chartWorkspace: FakeChartWorkspace(root.path),
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export .mcz'));
    await tester.pumpAndSettle();

    expect(controller.lastError, contains('mcz_export_directory_not_selected'));

    root.deleteSync(recursive: true);
  });

  testWidgets('Export .mcz reports share unavailable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
    );
    controller.openSession();
    final root = Directory.systemTemp.createTempSync('mcz_export_share_fail');
    final sourcePath = '${root.path}${Platform.pathSeparator}share_source.mc';
    controller.saveChart(path: sourcePath);

    final share = FakeChartShare(returnValue: false);
    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        filePicker: FakeChartFilePicker(saveDirectory: root.path),
        chartArchive: FakeChartArchive(),
        chartWorkspace: FakeChartWorkspace(root.path),
        chartShare: share,
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    final exportButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export .mcz'),
    );
    await tester.runAsync(() async {
      exportButton.onPressed!.call();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, 'share_fail_case');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();

    expect(share.shareCallCount, 1);
    expect(controller.lastEventLog, 'mcz_export_share_failed');
    expect(controller.lastError, 'mcz_export_share_unavailable');

    root.deleteSync(recursive: true);
  });

  testWidgets('App lifecycle pause auto-pauses playback and saves draft', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late FakeChartAudio fakeAudio;
    final controller = ChartDocumentController(
      sessionFactory: () => FakeCoreSession(),
      audioFactory: () {
        fakeAudio = FakeChartAudio(
          initialDuration: const Duration(seconds: 90),
        );
        return fakeAudio;
      },
    );
    controller.openSession();
    controller.addNormalNote(measure: 1, numerator: 0, denominator: 1, x: 220);
    controller.updateMetadata(
      controller.metadata.copyWith(
        title: 'LifecycleCase',
        audioFile: 'audio/song.ogg',
      ),
    );

    final root = Directory.systemTemp.createTempSync('mobile_lifecycle_pause');
    final sourceChartPath = '${root.path}${Platform.pathSeparator}source.mc';
    controller.saveChart(path: sourceChartPath);
    controller.addNormalNote(measure: 2, numerator: 0, denominator: 1, x: 240);

    final audioFile = File(
      '${root.path}${Platform.pathSeparator}audio${Platform.pathSeparator}song.ogg',
    );
    audioFile.parent.createSync(recursive: true);
    audioFile.writeAsStringSync('audio');

    await tester.pumpWidget(
      MalodyCatchMobileApp(
        controller: controller,
        runStartupSelfCheckOnInit: false,
        forceStartupReady: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pumpAndSettle();
    expect(controller.playbackStatus, PlaybackStatus.playing);
    expect(controller.hasDraft, isFalse);

    final dynamic pageState = tester.state(find.byType(MobileEditorPage));
    pageState.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(controller.playbackStatus, PlaybackStatus.paused);
    expect(controller.hasDraft, isTrue);
    expect(fakeAudio.currentState, ChartAudioPlaybackState.paused);

    root.deleteSync(recursive: true);
  });
}
