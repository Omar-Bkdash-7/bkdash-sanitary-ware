import 'dart:async';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/services/file_sharer.dart';
import 'package:bkdash_sanitary_ware/core/services/share_plus_file_sharer.dart';
import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/core/storage/shared_preferences_store.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_file_picker.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/export_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/file_selector_backup_picker.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/desktop_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/sync_outbox.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/sync_settings_store.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/payment_repository.dart';
import 'package:bkdash_sanitary_ware/features/reports/data/report_repository.dart';
import 'package:bkdash_sanitary_ware/features/security/data/biometric_authenticator.dart';
import 'package:bkdash_sanitary_ware/features/security/data/local_auth_biometric_authenticator.dart';
import 'package:bkdash_sanitary_ware/features/security/data/security_repository.dart';
import 'package:bkdash_sanitary_ware/features/settings/data/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Everything the screens need, created once when the app starts.
///
/// This is the only place that knows which concrete classes are used; the
/// screens receive their controllers from it through `Provider`.
final class AppDependencies {
  AppDependencies._({
    required this.database,
    required this.changes,
    required this.items,
    required this.customers,
    required this.invoices,
    required this.payments,
    required this.reports,
    required this.security,
    required this.settings,
    required this.biometrics,
    required this.backups,
    required this.sync,
    required this.exports,
    required this.picker,
    required this.sharer,
  });

  /// Opens the database and builds every repository and service.
  static Future<AppDependencies> create() async {
    final database = await AppDatabase.open();
    final changes = DataChangeNotifier();
    final KeyValueStore store = SharedPreferencesStore();

    final items = ItemRepository(database, changes);
    final customers = CustomerRepository(database, changes);
    final invoices = InvoiceRepository(database, changes);
    final payments = PaymentRepository(database, changes);

    final backups = BackupService(
      database: database,
      changes: changes,
      backupsDirectory: _backupsDirectory,
    );
    final sync = DesktopSyncService(
      settingsStore: SyncSettingsStore(store),
      invoices: invoices,
      backups: backups,
      outbox: SyncOutbox(store),
      database: database,
      backupsDirectory: _backupsDirectory,
    );
    unawaited(sync.start());

    return AppDependencies._(
      database: database,
      changes: changes,
      items: items,
      customers: customers,
      invoices: invoices,
      payments: payments,
      reports: ReportRepository(database, invoices),
      security: SecurityRepository(store),
      settings: SettingsRepository(store),
      biometrics: LocalAuthBiometricAuthenticator(),
      backups: backups,
      sync: sync,
      exports: ExportService(
        items: items,
        invoices: invoices,
        customers: customers,
        exportDirectory: _exportsDirectory,
      ),
      picker: const FileSelectorBackupPicker(getTemporaryDirectory),
      sharer: const SharePlusFileSharer(),
    );
  }

  final AppDatabase database;
  final DataChangeNotifier changes;
  final ItemRepository items;
  final CustomerRepository customers;
  final InvoiceRepository invoices;
  final PaymentRepository payments;
  final ReportRepository reports;
  final SecurityRepository security;
  final SettingsRepository settings;
  final BiometricAuthenticator biometrics;
  final BackupService backups;
  final DesktopSyncService sync;
  final ExportService exports;
  final BackupFilePicker picker;
  final FileSharer sharer;

  static Future<Directory> _backupsDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'backups'));
  }

  static Future<Directory> _exportsDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory(p.join(temporary.path, 'exports'));
  }
}
