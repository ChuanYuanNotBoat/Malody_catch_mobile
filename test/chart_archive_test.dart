import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malody_catch_mobile/io/chart_archive.dart';
import 'package:path/path.dart' as path;

void main() {
  test('chart archive extract rejects zip slip paths', () async {
    final root = Directory.systemTemp.createTempSync('chart_archive_slip');
    final mczPath = path.join(root.path, 'bad.mcz');

    final archive = Archive();
    archive.addFile(ArchiveFile('../evil.txt', 4, 'evil'.codeUnits));
    final encoded = ZipEncoder().encode(archive);
    File(mczPath).writeAsBytesSync(encoded!);

    final chartArchive = const ChartArchive();
    await expectLater(
      () => chartArchive.extractMcz(
        mczPath: mczPath,
        targetDirectoryPath: path.join(root.path, 'out'),
      ),
      throwsStateError,
    );

    root.deleteSync(recursive: true);
  });

  test(
    'chart archive create/extract roundtrip works for safe entries',
    () async {
      final root = Directory.systemTemp.createTempSync('chart_archive_ok');
      final source = path.join(root.path, 'song.ogg');
      File(source).writeAsStringSync('audio');
      final output = path.join(root.path, 'ok.mcz');

      final chartArchive = const ChartArchive();
      await chartArchive.createMcz(
        outputPath: output,
        files: <ChartArchiveFileSpec>[
          ChartArchiveFileSpec(sourcePath: source, archivePath: '0/song.ogg'),
        ],
      );

      final extracted = await chartArchive.extractMcz(
        mczPath: output,
        targetDirectoryPath: path.join(root.path, 'out'),
      );

      expect(
        extracted.any((entry) => entry.endsWith(path.join('0', 'song.ogg'))),
        isTrue,
      );
      expect(
        File(path.join(root.path, 'out', '0', 'song.ogg')).existsSync(),
        isTrue,
      );

      root.deleteSync(recursive: true);
    },
  );
}
