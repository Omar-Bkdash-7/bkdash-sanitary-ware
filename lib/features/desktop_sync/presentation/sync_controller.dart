import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/desktop_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/sync_settings.dart';

/// The "link with the computer" screen: settings, test, backup and Extract.
class SyncController extends BaseController {
  SyncController({required DesktopSyncService service}) : _service = service;

  final DesktopSyncService _service;

  SyncSettings _settings = const SyncSettings();
  int _pending = 0;
  bool _busy = false;
  String? _info;
  int _localBytes = 0;

  SyncSettings get settings => _settings;

  /// Invoices still waiting for Telegram or for the computer.
  int get pending => _pending;

  /// `true` while a connection, a backup or an Extract is running.
  bool get isBusy => _busy;

  /// The last thing that happened, shown under the buttons.
  String? get info => _info;

  /// Size of the phone database in bytes.
  int get localBytes => _localBytes;

  Future<void> load() => runLoad(() async {
    _settings = await _service.settings();
    _pending = await _service.pendingCount();
    _localBytes = await _service.localDatabaseBytes();
  });

  Future<void> save(SyncSettings settings) => _guard(() async {
    await _service.saveSettings(settings);
    _settings = settings;
    _info = 'تم حفظ الإعدادات.';
  });

  Future<void> testConnection() => _guard(() async {
    final info = await _service.ping();
    _info =
        'متصل بالكمبيوتر ✓  '
        '(${info.items} صنف • ${info.invoices} فاتورة)';
  });

  Future<void> sendTelegramTest() => _guard(() async {
    await _service.sendTelegramTest();
    _info = 'وصلت رسالة تجريبية إلى Telegram.';
  });

  Future<void> sendBackup() => _guard(() async {
    await _service.sendBackupToDesktop();
    _info = 'أُرسلت نسخة من قاعدة بيانات الهاتف إلى الكمبيوتر.';
  });

  /// Replaces the phone data with the computer database.
  Future<void> extract() => _guard(() async {
    await _service.extractFromDesktop();
    _pending = await _service.pendingCount();
    _localBytes = await _service.localDatabaseBytes();
    _info = 'تم سحب بيانات الكمبيوتر إلى الهاتف.';
  });

  Future<void> retryPending() => _guard(() async {
    await _service.flush();
    _pending = await _service.pendingCount();
    _info = _pending == 0
        ? 'أُرسلت كل الفواتير المعلّقة.'
        : 'ما زالت $_pending فاتورة بانتظار الإرسال.';
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
