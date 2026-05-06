import 'package:file_picker/file_picker.dart';

abstract class ChartFilePickerPort {
  Future<String?> pickChartToOpen();

  Future<String?> pickDirectoryForSave();
}

class ChartFilePicker implements ChartFilePickerPort {
  const ChartFilePicker();

  @override
  Future<String?> pickChartToOpen() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['mc', 'mcz'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return null;
      }
      return result.files.single.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> pickDirectoryForSave() async {
    try {
      return await FilePicker.platform.getDirectoryPath();
    } catch (_) {
      return null;
    }
  }
}
