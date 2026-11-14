import 'package:bkdash_sanitary_ware/features/desktop_sync/data/sync_outbox.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/sync_settings_store.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/sync_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

void main() {
  group('SyncSettingsStore', () {
    test('يعطي الجهاز معرّفاً ثابتاً في المرة الأولى', () async {
      final store = InMemoryKeyValueStore();
      final settingsStore = SyncSettingsStore(store);

      final first = await settingsStore.load();
      final second = await settingsStore.load();

      expect(first.deviceId, isNotEmpty);
      expect(second.deviceId, first.deviceId);
    });

    test('يحفظ الإعدادات ويقرأها كما هي', () async {
      final store = InMemoryKeyValueStore();
      final settingsStore = SyncSettingsStore(store);
      await settingsStore.load();

      await settingsStore.save(
        const SyncSettings(
          enabled: true,
          host: '192.168.1.20',
          port: 9000,
          token: 'secret',
          telegramEnabled: true,
          telegramToken: '123:abc',
          telegramChatId: '555',
        ),
      );
      final loaded = await settingsStore.load();

      expect(loaded.enabled, isTrue);
      expect(loaded.host, '192.168.1.20');
      expect(loaded.port, 9000);
      expect(loaded.hasDesktop, isTrue);
      expect(loaded.hasTelegram, isTrue);
      expect(loaded.telegramChatId, '555');
      expect(loaded.deviceId, isNotEmpty);
    });

    test('يعتبر الربط معطلاً بلا عنوان أو بلا تفعيل', () {
      const withoutHost = SyncSettings(
        enabled: true,
        telegramEnabled: true,
        telegramToken: 'x',
        telegramChatId: 'y',
      );
      expect(withoutHost.hasDesktop, isFalse);
      expect(withoutHost.hasTelegram, isTrue);

      const disabled = SyncSettings(host: '10.0.0.2');
      expect(disabled.hasDesktop, isFalse);
    });
  });

  group('SyncOutbox', () {
    test('يحفظ ما تبقّى ويحذف ما وصل', () async {
      final outbox = SyncOutbox(InMemoryKeyValueStore());
      await outbox.save(<OutboxEntry>[
        const OutboxEntry(invoiceId: 1, telegramDone: true),
        const OutboxEntry(invoiceId: 2, telegramDone: true, desktopDone: true),
      ]);

      final pending = await outbox.load();
      expect(pending, hasLength(2));
      expect(pending.first.isDone, isFalse);
      expect(pending.last.isDone, isTrue);

      await outbox.save(<OutboxEntry>[
        pending.first.copyWith(desktopDone: true),
      ]);
      final after = await outbox.load();
      expect(after, hasLength(1));
      expect(after.single.isDone, isTrue);
    });
  });
}
