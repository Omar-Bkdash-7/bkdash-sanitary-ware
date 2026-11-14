import 'dart:math';

/// Where the bridge program on the PC is, how to reach it and which Telegram
/// bot reports the new invoices.
///
/// Nothing here leaves the phone except to the address the user typed, so the
/// whole link is LAN-only: no cloud account, no cloud database.
final class SyncSettings {
  const SyncSettings({
    this.enabled = false,
    this.host = '',
    this.port = defaultPort,
    this.token = '',
    this.telegramEnabled = false,
    this.telegramToken = '',
    this.telegramChatId = '',
    this.deviceId = '',
  });

  factory SyncSettings.fromJson(Map<String, Object?> json) => SyncSettings(
    enabled: json['enabled'] == true,
    host: (json['host'] as String?) ?? '',
    port: (json['port'] as num?)?.toInt() ?? defaultPort,
    token: (json['token'] as String?) ?? '',
    telegramEnabled: json['telegramEnabled'] == true,
    telegramToken: (json['telegramToken'] as String?) ?? '',
    telegramChatId: (json['telegramChatId'] as String?) ?? '',
    deviceId: (json['deviceId'] as String?) ?? '',
  );

  /// The port the desktop bridge listens on by default.
  static const int defaultPort = 8756;

  /// Sends new invoices (and the database copies) to the PC.
  final bool enabled;

  /// The PC address on the local network, e.g. `192.168.1.20`.
  final String host;
  final int port;

  /// Shared secret of the bridge; the PC refuses requests without it.
  final String token;

  /// Sends every new invoice to Telegram as soon as it is saved.
  final bool telegramEnabled;
  final String telegramToken;
  final String telegramChatId;

  /// Identifies this phone, so the PC can recognise an invoice it already has
  /// when the phone retries a delivery.
  final String deviceId;

  bool get hasDesktop => enabled && host.trim().isNotEmpty;

  bool get hasTelegram =>
      telegramEnabled &&
      telegramToken.trim().isNotEmpty &&
      telegramChatId.trim().isNotEmpty;

  SyncSettings copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? token,
    bool? telegramEnabled,
    String? telegramToken,
    String? telegramChatId,
    String? deviceId,
  }) => SyncSettings(
    enabled: enabled ?? this.enabled,
    host: host ?? this.host,
    port: port ?? this.port,
    token: token ?? this.token,
    telegramEnabled: telegramEnabled ?? this.telegramEnabled,
    telegramToken: telegramToken ?? this.telegramToken,
    telegramChatId: telegramChatId ?? this.telegramChatId,
    deviceId: deviceId ?? this.deviceId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'host': host,
    'port': port,
    'token': token,
    'telegramEnabled': telegramEnabled,
    'telegramToken': telegramToken,
    'telegramChatId': telegramChatId,
    'deviceId': deviceId,
  };

  /// A new random id for a phone that has none yet.
  static String newDeviceId() {
    final random = Random.secure();
    return List<String>.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
