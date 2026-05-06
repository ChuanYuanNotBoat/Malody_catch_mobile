import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

class ChartArchiveFileSpec {
  const ChartArchiveFileSpec({
    required this.sourcePath,
    required this.archivePath,
  });

  final String sourcePath;
  final String archivePath;
}

abstract class ChartArchivePort {
  Future<List<String>> extractMcz({
    required String mczPath,
    required String targetDirectoryPath,
  });

  Future<void> createMcz({
    required String outputPath,
    required List<ChartArchiveFileSpec> files,
  });
}

class ChartArchive implements ChartArchivePort {
  const ChartArchive();

  @override
  Future<List<String>> extractMcz({
    required String mczPath,
    required String targetDirectoryPath,
  }) async {
    final source = File(mczPath);
    if (!source.existsSync()) {
      throw StateError('mcz source not found: $mczPath');
    }

    final bytes = await source.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final targetDir = Directory(targetDirectoryPath);
    await targetDir.create(recursive: true);

    final extractedFiles = <String>[];
    for (final entry in archive) {
      final safeRelativePath = _sanitizeArchivePath(entry.name);
      final outputPath = _toNativePath(targetDirectoryPath, safeRelativePath);

      if (!entry.isFile) {
        await Directory(outputPath).create(recursive: true);
        continue;
      }

      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      final content = entry.content;
      if (content is! List<int>) {
        throw StateError('archive entry content unsupported: ${entry.name}');
      }
      await outputFile.writeAsBytes(content);
      extractedFiles.add(outputFile.path);
    }

    return extractedFiles;
  }

  @override
  Future<void> createMcz({
    required String outputPath,
    required List<ChartArchiveFileSpec> files,
  }) async {
    final archive = Archive();
    for (final spec in files) {
      final sourceFile = File(spec.sourcePath);
      if (!sourceFile.existsSync()) {
        throw StateError('archive source missing: ${spec.sourcePath}');
      }
      final safeArchivePath = _sanitizeArchivePath(spec.archivePath);
      final bytes = await sourceFile.readAsBytes();
      archive.addFile(ArchiveFile(safeArchivePath, bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('zip encode failed.');
    }

    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes(encoded);
  }

  String _sanitizeArchivePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      throw StateError('empty archive entry path');
    }

    final normalizedSeparators = trimmed.replaceAll('\\', '/');
    if (_looksAbsolute(normalizedSeparators)) {
      throw StateError('zip slip blocked absolute path: $rawPath');
    }

    final normalized = path.posix.normalize(normalizedSeparators);
    if (normalized == '.' || normalized == '..' || normalized.isEmpty) {
      throw StateError('invalid archive entry path: $rawPath');
    }
    if (normalized.startsWith('../') || normalized.contains('/../')) {
      throw StateError('zip slip blocked parent path: $rawPath');
    }

    final segments = path.posix.split(normalized);
    if (segments.any((segment) => segment.isEmpty || segment == '.')) {
      throw StateError('invalid archive entry segments: $rawPath');
    }
    if (segments.any((segment) => segment == '..')) {
      throw StateError('zip slip blocked segment: $rawPath');
    }
    return segments.join('/');
  }

  String _toNativePath(String rootPath, String relativePosixPath) {
    final segments = path.posix.split(relativePosixPath);
    return path.joinAll(<String>[rootPath, ...segments]);
  }

  bool _looksAbsolute(String p) {
    if (p.startsWith('/') || p.startsWith('\\')) {
      return true;
    }
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(p);
  }
}
