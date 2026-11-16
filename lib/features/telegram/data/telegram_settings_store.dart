import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/core/storage/secret_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';

/// Keeps the Telegram settings.
///
/// The bot token and the chat id go to the encrypted [SecretStore]; only the
/// two switches stay in the ordinary preferences, so a copy of the preferences
/// (or of the exported database) never contains a credential.
class TelegramSettingsStore {
  TelegramSettingsStore(this._secrets, this._preferences);

  final SecretStore _secrets;
  final KeyValueStore _preferences;

  static const String _tokenKey = 'telegram.bot_token';
  static const String _chatKey = 'telegram.chat_id';
  static const String _pdfKey = 'telegram.send_invoice_pdf';
  static const String _databaseKey = 'telegram.send_database';

  Future<TelegramSettings> load() async => TelegramSettings(
    token: await _secrets.read(_tokenKey) ?? '',
    chatId: await _secrets.read(_chatKey) ?? '',
    sendInvoicePdf: await _preferences.getBool(_pdfKey) ?? true,
    sendDatabase: await _preferences.getBool(_databaseKey) ?? true,
  );

  Future<void> save(TelegramSettings settings) async {
    await _secrets.write(_tokenKey, settings.token.trim());
    await _secrets.write(_chatKey, settings.chatId.trim());
    await _preferences.setBool(_pdfKey, settings.sendInvoicePdf);
    await _preferences.setBool(_databaseKey, settings.sendDatabase);
  }

  /// `true` once a bot token was stored (used by the one-time migration).
  Future<bool> hasToken() async =>
      ((await _secrets.read(_tokenKey)) ?? '').trim().isNotEmpty;
}
