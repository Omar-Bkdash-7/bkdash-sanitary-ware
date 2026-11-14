import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/services/file_sharer.dart';
import 'package:share_plus/share_plus.dart';

/// [FileSharer] backed by the `share_plus` plugin.
final class SharePlusFileSharer implements FileSharer {
  const SharePlusFileSharer();

  @override
  Future<void> shareFile(File file, {String? subject, String? text}) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path)],
        subject: subject,
        text: text,
      ),
    );
    if (result.status == ShareResultStatus.unavailable) {
      throw const BackupException('المشاركة غير متاحة على هذا الجهاز.');
    }
  }
}
