import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';

/// Sends messages through the Telegram bot API.
///
/// The bot token and the chat id belong to the shop; they are only used from
/// the phone and never stored anywhere else.
class TelegramNotifier {
  TelegramNotifier({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  /// Sends [text] to the chat; throws [SyncException] when Telegram refuses.
  Future<void> send({
    required String botToken,
    required String chatId,
    required String text,
  }) async {
    final token = botToken.trim();
    final chat = chatId.trim();
    if (token.isEmpty || chat.isEmpty) {
      throw const SyncException('أدخل رمز بوت Telegram ومعرّف المحادثة أولاً.');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(Uri.https('api.telegram.org', '/bot$token/sendMessage'))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'chat_id': chat,
            'text': text,
            'disable_web_page_preview': true,
          }),
        ),
      );
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw SyncException('تعذّر إرسال رسالة Telegram: ${_reason(body)}');
      }
    } on SocketException {
      throw const SyncException(
        'لا يوجد اتصال بالإنترنت لإرسال رسالة Telegram.',
      );
    } on TimeoutException {
      throw const SyncException('انتهت مهلة الاتصال بـ Telegram.');
    } on HandshakeException {
      throw const SyncException('تعذّر الاتصال الآمن بـ Telegram.');
    } finally {
      client.close(force: true);
    }
  }

  /// The `description` Telegram returns with an error, when it is readable.
  String _reason(String body) {
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      final description = json['description'];
      if (description is String && description.isNotEmpty) return description;
    } on FormatException {
      // Not JSON: fall through to the generic text.
    }
    return 'تحقّق من رمز البوت ومعرّف المحادثة.';
  }
}
