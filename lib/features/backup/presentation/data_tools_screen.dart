import 'dart:io';

import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:bkdash_sanitary_ware/features/backup/presentation/data_tools_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Backup, restore and export of the shop data.
class DataToolsScreen extends StatelessWidget {
  const DataToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DataToolsController>(
      create: (context) {
        final deps = context.read<AppDependencies>();
        return DataToolsController(
          backups: deps.backups,
          exports: deps.exports,
          picker: deps.picker,
          sharer: deps.sharer,
        )..load();
      },
      child: const _DataToolsView(),
    );
  }
}

class _DataToolsView extends StatelessWidget {
  const _DataToolsView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DataToolsController>();
    final theme = Theme.of(context);
    final busy = controller.isBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي والتصدير'),
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Block(
            title: 'النسخ الاحتياطي',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'تُحفظ النسخة على الهاتف، ويمكنك مشاركتها (واتساب، Drive، بريد) '
                  'لتبقى محفوظة خارج الجهاز.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => _backup(context, controller, share: true),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('إنشاء نسخة ومشاركتها'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _backup(context, controller, share: false),
                      icon: const Icon(Icons.save_alt_rounded),
                      label: const Text('إنشاء نسخة على الهاتف فقط'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Block(
            title: 'الاستعادة',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'تستبدل الاستعادة كل البيانات الحالية ببيانات النسخة. '
                  'تُحفظ نسخة من بياناتك الحالية قبل الاستبدال.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _restoreFromFile(context, controller),
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('استعادة من ملف...'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Block(
            title: 'النسخ المحفوظة على الهاتف (${controller.backups.length})',
            children: [
              if (controller.backups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد نسخ محفوظة بعد.'),
                )
              else
                for (final backup in controller.backups)
                  _BackupTile(
                    backup: backup,
                    enabled: !busy,
                    onShare: () =>
                        runUiAction(context, () => controller.share(backup)),
                    onRestore: () =>
                        _confirmRestore(context, controller, backup.file),
                    onDelete: () => _delete(context, controller, backup),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          _Block(
            title: 'التصدير إلى Excel (CSV)',
            children: [
              for (final kind in ExportKind.values)
                ListTile(
                  enabled: !busy,
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(kind.label),
                  trailing: const Icon(Icons.ios_share_rounded),
                  onTap: () =>
                      runUiAction(context, () => controller.export(kind)),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _backup(
    BuildContext context,
    DataToolsController controller, {
    required bool share,
  }) {
    return runUiAction(context, () async {
      final backup = await controller.createBackup();
      if (share) await controller.share(backup);
    }, successMessage: share ? null : 'تم إنشاء النسخة الاحتياطية على الهاتف');
  }

  Future<void> _restoreFromFile(
    BuildContext context,
    DataToolsController controller,
  ) async {
    File? picked;
    final ok = await runUiAction(context, () async {
      picked = await controller.pickBackupFile();
    });
    final file = picked;
    if (!ok || file == null || !context.mounted) return;
    await _confirmRestore(context, controller, file);
  }

  Future<void> _confirmRestore(
    BuildContext context,
    DataToolsController controller,
    File file,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'استعادة نسخة احتياطية',
      message:
          'ستُستبدل كل البيانات الحالية (المخزون والفواتير والزبائن) ببيانات '
          'النسخة المحددة. هل تريد المتابعة؟',
      confirmLabel: 'استعادة',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runUiAction(
      context,
      () => controller.restore(file),
      successMessage: 'تمت استعادة البيانات بنجاح',
    );
  }

  Future<void> _delete(
    BuildContext context,
    DataToolsController controller,
    BackupFile backup,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف النسخة',
      message: 'هل تريد حذف "${backup.name}"؟',
      confirmLabel: AppStrings.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runUiAction(context, () => controller.delete(backup));
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.children});

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

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.backup,
    required this.enabled,
    required this.onShare,
    required this.onRestore,
    required this.onDelete,
  });

  final BackupFile backup;
  final bool enabled;
  final VoidCallback onShare;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: const Icon(Icons.storage_rounded),
      title: Text(
        backup.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${AppDates.display(backup.modified)}  ${AppDates.time12(backup.modified)}'
        '  •  ${backup.sizeLabel}',
      ),
      trailing: PopupMenuButton<String>(
        enabled: enabled,
        onSelected: (value) {
          switch (value) {
            case 'share':
              onShare();
            case 'restore':
              onRestore();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'share', child: Text(AppStrings.share)),
          PopupMenuItem(value: 'restore', child: Text('استعادة')),
          PopupMenuItem(value: 'delete', child: Text(AppStrings.delete)),
        ],
      ),
    );
  }
}
