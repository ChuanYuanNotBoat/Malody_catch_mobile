import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:malody_catch_mobile/core/chart_document_controller.dart';
import 'package:malody_catch_mobile/core/native_core.dart';

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
}
