import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/widgets/bkdash_logo.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customers_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customers_screen.dart';
import 'package:bkdash_sanitary_ware/features/inventory/presentation/inventory_controller.dart';
import 'package:bkdash_sanitary_ware/features/inventory/presentation/inventory_screen.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoices_controller.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoices_screen.dart';
import 'package:bkdash_sanitary_ware/features/reports/presentation/reports_controller.dart';
import 'package:bkdash_sanitary_ware/features/reports/presentation/reports_screen.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:bkdash_sanitary_ware/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The unlocked app: five tabs and the controllers that feed them.
///
/// The controllers live only while the app is unlocked, so no business data
/// stays in memory behind the lock screen.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = context.read<AppDependencies>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<InventoryController>(
          create: (_) =>
              InventoryController(repository: deps.items, changes: deps.changes)
                ..load(),
        ),
        ChangeNotifierProvider<InvoicesController>(
          create: (_) => InvoicesController(
            repository: deps.invoices,
            changes: deps.changes,
          )..load(),
        ),
        ChangeNotifierProvider<CustomersController>(
          create: (_) => CustomersController(
            customers: deps.customers,
            payments: deps.payments,
            changes: deps.changes,
          )..load(),
        ),
        ChangeNotifierProvider<ReportsController>(
          create: (_) =>
              ReportsController(repository: deps.reports, changes: deps.changes)
                ..load(),
        ),
      ],
      child: const _HomeScaffold(),
    );
  }
}

class _HomeScaffold extends StatefulWidget {
  const _HomeScaffold();

  @override
  State<_HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<_HomeScaffold> {
  int _index = 0;

  static const List<_Tab> _tabs = <_Tab>[
    _Tab(
      AppStrings.tabInventory,
      Icons.inventory_2_outlined,
      Icons.inventory_2,
    ),
    _Tab(
      AppStrings.tabInvoices,
      Icons.receipt_long_outlined,
      Icons.receipt_long,
    ),
    _Tab(AppStrings.tabCustomers, Icons.people_outline, Icons.people),
    _Tab(AppStrings.tabReports, Icons.bar_chart_outlined, Icons.bar_chart),
    _Tab(AppStrings.tabSettings, Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: BkdashLogo(size: 34, isDark: isDark),
        actions: [
          IconButton(
            tooltip: AppStrings.lockNow,
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: context.read<SecurityController>().lock,
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          InventoryScreen(),
          InvoicesScreen(),
          CustomersScreen(),
          ReportsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
