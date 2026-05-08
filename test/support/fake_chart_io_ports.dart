import 'dart:io';

import 'package:malody_catch_mobile/io/chart_archive.dart';
import 'package:malody_catch_mobile/io/chart_share.dart';
import 'package:malody_catch_mobile/io/chart_workspace.dart';
import 'package:path/path.dart' as path;

typedef ExtractCallback =
    Future<List<String>> Function(String mczPath, String targetDirectoryPath);
typedef CreateCallback =
    Future<void> Function(String outputPath, List<ChartArchiveFileSpec> files);

class FakeChartArchive implements ChartArchivePort {
  FakeChartArchive({this.onExtract, this.onCreate});

  final ExtractCallback? onExtract;
  final CreateCallback? onCreate;

  String? lastExtractMczPath;
  String? lastExtractTargetDirectoryPath;
  String? lastCreateOutputPath;
  List<ChartArchiveFileSpec>? lastCreateFiles;

  @override
  Future<List<String>> extractMcz({
    required String mczPath,
    required String targetDirectoryPath,
  }) async {
    lastExtractMczPath = mczPath;
    lastExtractTargetDirectoryPath = targetDirectoryPath;
    if (onExtract != null) {
      return onExtract!(mczPath, targetDirectoryPath);
    }
    return const <String>[];
  }

  @override
  Future<void> createMcz({
    required String outputPath,
    required List<ChartArchiveFileSpec> files,
  }) async {
    lastCreateOutputPath = outputPath;
    lastCreateFiles = List<ChartArchiveFileSpec>.from(files);
    if (onCreate != null) {
      await onCreate!(outputPath, files);
    }
  }
}

class FakeChartShare implements ChartSharePort {
  FakeChartShare({
    this.throwOnShare = false,
    this.returnValue = true,
  });

  final bool throwOnShare;
  final bool returnValue;
  int shareCallCount = 0;
  String? lastFilePath;
  String? lastSubject;
  String? lastText;

  @override
  Future<bool> shareFile({
    required String filePath,
    String? subject,
    String? text,
  }) async {
    shareCallCount += 1;
    lastFilePath = filePath;
    lastSubject = subject;
    lastText = text;
    if (throwOnShare) {
      throw StateError('share unavailable');
    }
    return returnValue;
  }
}

class FakeChartWorkspace implements ChartWorkspacePort {
  FakeChartWorkspace(this.rootPath);

  final String rootPath;
  int _tempSeed = 0;
  int _workspaceSeed = 0;

  @override
  Future<String> createImportTempDirectory() async {
    _tempSeed += 1;
    final temp = Directory(path.join(rootPath, 'temp_$_tempSeed'));
    await temp.create(recursive: true);
    return temp.path;
  }

  @override
  Future<ChartWorkspaceLocation> createChartWorkspace({
    required String suggestedStem,
    required String chartFileName,
  }) async {
    _workspaceSeed += 1;
    final chartId = '${suggestedStem}_$_workspaceSeed';
    final workspaceRoot = path.join(rootPath, 'charts', chartId);
    await Directory(workspaceRoot).create(recursive: true);
    final fileName = chartFileName.toLowerCase().endsWith('.mc')
        ? chartFileName
        : '$chartFileName.mc';
    return ChartWorkspaceLocation(
      chartId: chartId,
      rootDirectoryPath: workspaceRoot,
      chartFilePath: path.join(workspaceRoot, path.basename(fileName)),
    );
  }

  @override
  Future<void> ensureDirectory(String directoryPath) async {
    await Directory(directoryPath).create(recursive: true);
  }

  @override
  Future<void> copyFile({
    required String sourcePath,
    required String targetPath,
  }) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw StateError('missing source: $sourcePath');
    }
    File(targetPath).parent.createSync(recursive: true);
    source.copySync(targetPath);
  }

  @override
  Future<void> writeTextFile({
    required String targetPath,
    required String content,
  }) async {
    final file = File(targetPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  @override
  Future<void> deleteDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  @override
  bool fileExists(String filePath) {
    return File(filePath).existsSync();
  }
}
