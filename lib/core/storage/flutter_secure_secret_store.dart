import 'package:bkdash_sanitary_ware/core/storage/secret_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [SecretStore] backed by the platform keystore (`flutter_secure_storage`).
///
/// The values are encrypted with a key held by Android's Keystore, so a copy of
/// the app's preferences folder does not reveal them.
final class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
