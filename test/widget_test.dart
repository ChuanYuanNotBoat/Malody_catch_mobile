import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malody_catch_mobile/core/chart_document_controller.dart';
import 'package:malody_catch_mobile/core/mc_chart_io.dart';
import 'package:malody_catch_mobile/core/native_core.dart';
import 'package:malody_catch_mobile/io/chart_file_picker.dart';
import 'package:malody_catch_mobile/main.dart';

import 'support/fake_chart_io_ports.dart';
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
    expect(find.byType(Scaffold), findsOneWidget);
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
}
