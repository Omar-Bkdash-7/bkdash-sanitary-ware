import 'dart:convert';

import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/sync_settings.dart';

/// Keeps [SyncSettings] in the phone preferences.
class SyncSettingsStore {
  SyncSettingsStore(this._store);

  final KeyValueStore _store;

  static const String _key = 'sync.settings';

  /// Reads the settings; a phone that has no id yet gets one on the first call.
  Future<SyncSettings> load() async {
    final raw = await _store.getString(_key);
    var settings = const SyncSettings();
    if (raw != null && raw.isNotEmpty) {
      try {
        settings = SyncSettings.fromJson(
          jsonDecode(raw) as Map<String, Object?>,
        );
      } on FormatException {
        // A damaged value is simply replaced by the defaults.
        settings = const SyncSettings();
      }
    }
    if (settings.deviceId.isEmpty) {
      settings = settings.copyWith(deviceId: SyncSettings.newDeviceId());
      await save(settings);
    }
    return settings;
  }

  Future<void> save(SyncSettings settings) =>
      _store.setString(_key, jsonEncode(settings.toJson()));
}
