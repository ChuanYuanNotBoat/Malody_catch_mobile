import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ChartWorkspaceLocation {
  const ChartWorkspaceLocation({
    required this.chartId,
    required this.rootDirectoryPath,
    required this.chartFilePath,
  });

  final String chartId;
  final String rootDirectoryPath;
  final String chartFilePath;
}

abstract class ChartWorkspacePort {
  Future<String> createImportTempDirectory();

  Future<ChartWorkspaceLocation> createChartWorkspace({
    required String suggestedStem,
    required String chartFileName,
  });

  Future<void> ensureDirectory(String directoryPath);

  Future<void> copyFile({
    required String sourcePath,
    required String targetPath,
  });

  Future<void> writeTextFile({
    required String targetPath,
    required String content,
  });

  Future<void> deleteDirectory(String directoryPath);

  bool fileExists(String filePath);
}

class ChartWorkspace implements ChartWorkspacePort {
  const ChartWorkspace();

  @override
  Future<String> createImportTempDirectory() async {
    final root = await _tempRootPath();
    final unique =
        'mcz_import_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
    final directory = Directory(path.join(root, unique));
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<ChartWorkspaceLocation> createChartWorkspace({
    required String suggestedStem,
    required String chartFileName,
  }) async {
    final root = await _chartsRootPath();
    final safeStem = _sanitizeStem(suggestedStem);
    final chartId =
        '${safeStem}_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
    final workspaceRoot = path.join(root, chartId);
    await Directory(workspaceRoot).create(recursive: true);

    var safeChartFileName = path.basename(chartFileName.trim());
    if (!safeChartFileName.toLowerCase().endsWith('.mc')) {
      safeChartFileName = '${safeChartFileName.trim()}.mc';
    }
    if (safeChartFileName.isEmpty || safeChartFileName == '.mc') {
      safeChartFileName = '$safeStem.mc';
    }

    return ChartWorkspaceLocation(
      chartId: chartId,
      rootDirectoryPath: workspaceRoot,
      chartFilePath: path.join(workspaceRoot, safeChartFileName),
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
      throw StateError('source not found: $sourcePath');
    }
    await File(targetPath).parent.create(recursive: true);
    await source.copy(targetPath);
  }

  @override
  Future<void> writeTextFile({
    required String targetPath,
    required String content,
  }) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> deleteDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  bool fileExists(String filePath) {
    return File(filePath).existsSync();
  }

  Future<String> _chartsRootPath() async {
    final support = await getApplicationSupportDirectory();
    return path.join(support.path, 'charts');
  }

  Future<String> _tempRootPath() async {
    final support = await getApplicationSupportDirectory();
    return path.join(support.path, 'temp_imports');
  }

  String _sanitizeStem(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'chart';
    }
    final replaced = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final collapsed = replaced.replaceAll(RegExp(r'\s+'), '_');
    return collapsed.isEmpty ? 'chart' : collapsed;
  }

  String _randomSuffix() {
    final random = Random();
    final value = random.nextInt(0xFFFFFF);
    return value.toRadixString(16).padLeft(6, '0');
  }
}
