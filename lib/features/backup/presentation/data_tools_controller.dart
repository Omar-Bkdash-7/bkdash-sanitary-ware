import 'dart:io';

import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/services/file_sharer.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_file_picker.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/export_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/restore_preview.dart';

/// The CSV files the user can export.
enum ExportKind {
  inventory('المخزون'),
  invoices('الفواتير'),
  invoiceLines('الأصناف المباعة'),
  customers('الزبائن والديون');

  const ExportKind(this.label);

  final String label;
}

/// Backup, restore and export (the "data tools" screen).
class DataToolsController extends BaseController {
  DataToolsController({
    required BackupService backups,
    required ExportService exports,
    required BackupFilePicker picker,
    required FileSharer sharer,
  }) : _backups = backups,
       _exports = exports,
       _picker = picker,
       _sharer = sharer;

  final BackupService _backups;
  final ExportService _exports;
  final BackupFilePicker _picker;
  final FileSharer _sharer;

  List<BackupFile> _files = const <BackupFile>[];
  bool _busy = false;

  List<BackupFile> get backups => _files;

  /// `true` while a backup, restore or export is running.
  bool get isBusy => _busy;

  Future<void> load() => runLoad(() async {
    _files = await _backups.listBackups();
  });

  /// Creates a backup and returns it (the screen then offers to share it).
  Future<BackupFile> createBackup() => _guard(() async {
    final backup = await _backups.createBackup();
    _files = await _backups.listBackups();
    return backup;
  });

  Future<void> share(BackupFile backup) => _guard(
    () => _sharer.shareFile(
      backup.file,
      subject: 'نسخة احتياطية - بكداش',
      text: backup.name,
    ),
  );

  Future<void> delete(BackupFile backup) => _guard(() async {
    await _backups.deleteBackup(backup);
    _files = await _backups.listBackups();
  });

  /// Asks the user to choose a file; `null` when he cancelled.
  Future<File?> pickBackupFile() => _guard(_picker.pickBackup);

  /// Counts of the current data and of [source], for the confirmation dialog.
  Future<RestorePreview> previewRestore(File source) => _guard(() async {
    final current = await _backups.summarize();
    final incoming = await _backups.summarizeIncoming(source);
    return RestorePreview(current: current, incoming: incoming);
  });

  Future<void> restore(File source) => _guard(() async {
    await _backups.restore(source);
    _files = await _backups.listBackups();
  });

  Future<void> restoreStored(BackupFile backup) => restore(backup.file);

  /// Writes the CSV file of [kind] and opens the share sheet for it.
  Future<void> export(ExportKind kind) => _guard(() async {
    final file = switch (kind) {
      ExportKind.inventory => await _exports.exportInventory(),
      ExportKind.invoices => await _exports.exportInvoices(),
      ExportKind.invoiceLines => await _exports.exportInvoiceLines(),
      ExportKind.customers => await _exports.exportCustomers(),
    };
    await _sharer.shareFile(file, subject: 'بكداش - ${kind.label}');
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
