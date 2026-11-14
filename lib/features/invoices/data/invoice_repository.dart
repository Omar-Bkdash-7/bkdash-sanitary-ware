import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_line_export.dart';

/// Issues and reads invoices.
class InvoiceRepository {
  InvoiceRepository(this._database, this._changes, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DataChangeNotifier _changes;
  final Clock _clock;

  /// Saves [draft] as a new invoice and returns its number.
  ///
  /// Everything happens in one transaction: the stock is reduced, the invoice
  /// and its lines are written and the payment is recorded - or nothing is
  /// changed at all (for example when the stock is not enough).
  Future<int> create(InvoiceDraft draft) async {
    draft.validate();
    final now = _clock();
    final createdAt = AppDates.isoDateTime(now);
    final date = AppDates.isoDate(now);
    final total = draft.total;
    final paid = draft.paid;

    final invoiceId = await _database.db.transaction((txn) async {
      for (final line in draft.lines) {
        // Atomic: reduces the stock only when enough pieces are left.
        final changed = await txn.rawUpdate(
          'UPDATE ${DbTables.items} SET quantity = quantity - ? '
          'WHERE id = ? AND quantity >= ?',
          <Object?>[line.quantity, line.itemId, line.quantity],
        );
        if (changed == 0) {
          final rows = await txn.query(
            DbTables.items,
            columns: <String>['name', 'quantity'],
            where: 'id = ?',
            whereArgs: <Object?>[line.itemId],
          );
          if (rows.isEmpty) {
            throw NotFoundException('الصنف "${line.itemName}" لم يعد موجوداً.');
          }
          throw InsufficientStockException(
            itemName: rows.first['name']! as String,
            available: rows.first['quantity']! as int,
            requested: line.quantity,
          );
        }
      }

      final id = await txn.insert(DbTables.invoices, <String, Object?>{
        'customer_id': draft.customer?.id,
        'customer_name':
            draft.customer?.name ?? AppConstants.walkInCustomerName,
        'customer_phone': draft.customer?.phone ?? '',
        'payment_method': draft.paymentMethod.key,
        'invoice_date': date,
        'created_at': createdAt,
        'total_cents': total.cents,
        'paid_cents': paid.cents,
        'profit_cents': draft.profit.cents,
        'notes': draft.notes.trim(),
      });

      final lines = txn.batch();
      for (final line in draft.lines) {
        lines.insert(DbTables.invoiceItems, <String, Object?>{
          'invoice_id': id,
          'item_id': line.itemId,
          'item_name': line.itemName,
          'category': line.category,
          'sku': line.sku,
          'unit': line.unit,
          'quantity': line.quantity,
          'unit_cost_cents': line.unitCost.cents,
          'unit_price_cents': line.unitPrice.cents,
        });
      }
      await lines.commit(noResult: true);

      if (paid.isPositive) {
        await txn.insert(DbTables.payments, <String, Object?>{
          'invoice_id': id,
          'amount_cents': paid.cents,
          'paid_at': createdAt,
          'paid_date': date,
        });
      }
      return id;
    });

    _changes.markChanged();
    return invoiceId;
  }

  /// Invoices, newest first. [fromDate] / [toDate] are "yyyy-MM-dd" (inclusive).
  Future<List<Invoice>> getInvoices({
    int? customerId,
    String? fromDate,
    String? toDate,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      conditions.add('customer_id = ?');
      args.add(customerId);
    }
    if (fromDate != null) {
      conditions.add('invoice_date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      conditions.add('invoice_date <= ?');
      args.add(toDate);
    }
    final rows = await _database.db.query(
      DbTables.invoices,
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
    );
    return rows.map(Invoice.fromRow).toList();
  }

  Future<InvoiceDetails?> getDetails(int id) async {
    final db = _database.db;
    final headers = await db.query(
      DbTables.invoices,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (headers.isEmpty) return null;
    final lines = await db.query(
      DbTables.invoiceItems,
      where: 'invoice_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id',
    );
    final payments = await db.query(
      DbTables.payments,
      where: 'invoice_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id',
    );
    return InvoiceDetails(
      invoice: Invoice.fromRow(headers.first),
      lines: lines.map(InvoiceLineRecord.fromRow).toList(),
      payments: payments.map(PaymentRecord.fromRow).toList(),
    );
  }

  /// Every product line of every invoice (used by the CSV export).
  Future<List<InvoiceLineExport>> getAllLines() async {
    final rows = await _database.db.rawQuery(
      'SELECT l.*, i.invoice_date, i.customer_name '
      'FROM ${DbTables.invoiceItems} l '
      'JOIN ${DbTables.invoices} i ON i.id = l.invoice_id '
      'ORDER BY l.invoice_id, l.id',
    );
    return rows
        .map(
          (row) => InvoiceLineExport(
            invoiceId: row['invoice_id']! as int,
            invoiceDate: row['invoice_date']! as String,
            customerName: row['customer_name']! as String,
            line: InvoiceLineRecord.fromRow(row),
          ),
        )
        .toList();
  }
}
