import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/sync_settings.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/presentation/sync_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Links the app with the shop computer and with Telegram.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SyncController>(
      create: (context) => SyncController(
        service: context.read<AppDependencies>().sync,
      )..load(),
      child: const _SyncView(),
    );
  }
}

class _SyncView extends StatefulWidget {
  const _SyncView();

  @override
  State<_SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends State<_SyncView> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _token = TextEditingController();
  final TextEditingController _botToken = TextEditingController();
  final TextEditingController _chatId = TextEditingController();

  bool _bound = false;

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _host,
      _port,
      _token,
      _botToken,
      _chatId,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  SyncSettings _collect(SyncController controller) =>
      controller.settings.copyWith(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? SyncSettings.defaultPort,
        token: _token.text.trim(),
        telegramToken: _botToken.text.trim(),
        telegramChatId: _chatId.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncController>();
    final theme = Theme.of(context);
    final busy = controller.isBusy;

    if (!_bound && controller.status == LoadStatus.ready) {
      final settings = controller.settings;
      _host.text = settings.host;
      _port.text = '${settings.port}';
      _token.text = settings.token;
      _botToken.text = settings.telegramToken;
      _chatId.text = settings.telegramChatId;
      _bound = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الربط مع الكمبيوتر و Telegram'),
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: LoadStateView(
        status: controller.status,
        errorMessage: controller.errorMessage,
        onRetry: controller.load,
        builder: (context) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _Section(
              title: 'برنامج الكمبيوتر',
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.desktop_windows_outlined),
                  title: const Text('إرسال الفواتير إلى الكمبيوتر'),
                  subtitle: const Text(
                    'فور حفظ أي فاتورة تصل نسخة إلى برنامج الكمبيوتر '
                    'على نفس شبكة الواي فاي.',
                  ),
                  value: controller.settings.enabled,
                  onChanged: busy
                      ? null
                      : (value) => _saveSettings(
                          controller,
                          _collect(controller).copyWith(enabled: value),
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _host,
                        enabled: !busy,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'عنوان الكمبيوتر (IP)',
                          hintText: '192.168.1.20',
                          helperText:
                              'يظهر العنوان في نافذة برنامج الكمبيوتر عند تشغيله.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _port,
                              enabled: !busy,
                              textDirection: TextDirection.ltr,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'المنفذ',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _token,
                              enabled: !busy,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'رمز الربط',
                                helperText: 'نفس الرمز الظاهر في برنامج الكمبيوتر',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => runUiAction(
                                      context,
                                      () => controller
                                          .save(_collect(controller)),
                                      successMessage: 'تم حفظ الإعدادات',
                                    ),
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('حفظ'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => runUiAction(
                                      context,
                                      controller.testConnection,
                                    ),
                              icon: const Icon(Icons.wifi_tethering_rounded),
                              label: const Text('اختبار'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'مزامنة البيانات',
              children: [
                ListTile(
                  enabled: !busy,
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('إرسال نسخة من قاعدة البيانات إلى الكمبيوتر'),
                  subtitle: const Text(
                    'نسخة احتياطية كاملة (أصناف، زبائن، فواتير) تُحفظ على '
                    'الكمبيوتر.',
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => runUiAction(context, controller.sendBackup),
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !busy,
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('سحب بيانات الكمبيوتر إلى الهاتف (Extract)'),
                  subtitle: const Text(
                    'يصبح الهاتف مطابقاً للكمبيوتر تماماً. تُحفظ نسخة من '
                    'بيانات الهاتف الحالية قبل الاستبدال.',
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => _confirmExtract(context, controller),
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !busy,
                  leading: const Icon(Icons.replay_rounded),
                  title: const Text('إعادة إرسال الفواتير المعلّقة'),
                  subtitle: Text(
                    controller.pending == 0
                        ? 'لا توجد فواتير بانتظار الإرسال.'
                        : '${controller.pending} فاتورة بانتظار الإرسال.',
                  ),
                  trailing: const Icon(Icons.refresh_rounded),
                  onTap: () => runUiAction(context, controller.retryPending),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Telegram',
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.send_rounded),
                  title: const Text('إرسال كل فاتورة جديدة إلى Telegram'),
                  subtitle: const Text(
                    'تصل رسالة منسّقة بمحتوى الفاتورة لحظة حفظها.',
                  ),
                  value: controller.settings.telegramEnabled,
                  onChanged: busy
                      ? null
                      : (value) => _saveSettings(
                          controller,
                          _collect(controller).copyWith(telegramEnabled: value),
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _botToken,
                        enabled: !busy,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'رمز البوت (Bot Token)',
                          helperText:
                              'من @BotFather في Telegram، مثل 123456:ABC...',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _chatId,
                        enabled: !busy,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'معرّف المحادثة (Chat ID)',
                          helperText:
                              'رقم المحادثة التي تصلها الفواتير، مثل 123456789',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => runUiAction(
                                      context,
                                      () => controller
                                          .save(_collect(controller)),
                                      successMessage: 'تم حفظ الإعدادات',
                                    ),
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('حفظ'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => runUiAction(
                                      context,
                                      controller.sendTelegramTest,
                                    ),
                              icon: const Icon(Icons.send_outlined),
                              label: const Text('رسالة تجريبية'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (controller.info != null) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(controller.info!),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings(
    SyncController controller,
    SyncSettings settings,
  ) => runUiAction(context, () => controller.save(settings));

  Future<void> _confirmExtract(
    BuildContext context,
    SyncController controller,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'سحب بيانات الكمبيوتر',
      message:
          'ستُستبدل كل بيانات الهاتف (المخزون والزبائن والفواتير) ببيانات '
          'الكمبيوتر. تُحفظ نسخة من بيانات الهاتف الحالية في «النسخ '
          'الاحتياطي» قبل الاستبدال. هل تريد المتابعة؟',
      confirmLabel: 'سحب واستبدال',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runUiAction(
      context,
      controller.extract,
      successMessage: 'تمت مطابقة الهاتف مع الكمبيوتر',
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}
