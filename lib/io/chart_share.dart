import 'package:share_plus/share_plus.dart';

abstract class ChartSharePort {
  Future<bool> shareFile({
    required String filePath,
    String? subject,
    String? text,
  });
}

class ChartShare implements ChartSharePort {
  const ChartShare();

  @override
  Future<bool> shareFile({
    required String filePath,
    String? subject,
    String? text,
  }) async {
    final result = await Share.shareXFiles(
      <XFile>[XFile(filePath)],
      subject: subject,
      text: text,
    );

    return result.status != ShareResultStatus.unavailable;
  }
}
