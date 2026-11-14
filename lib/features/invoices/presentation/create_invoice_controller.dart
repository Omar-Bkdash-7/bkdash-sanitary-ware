import 'dart:async';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/desktop_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';

/// The "new invoice" screen: edits an [InvoiceDraft] and saves it.
class CreateInvoiceController extends BaseController {
  CreateInvoiceController({
    required ItemRepository items,
    required CustomerRepository customers,
    required InvoiceRepository invoices,
    DesktopSyncService? sync,
  }) : _items = items,
       _customers = customers,
       _invoices = invoices,
       _sync = sync;

  final ItemRepository _items;
  final CustomerRepository _customers;
  final InvoiceRepository _invoices;

  /// Sends the saved invoice to Telegram and to the computer.
  final DesktopSyncService? _sync;

  InvoiceDraft _draft = const InvoiceDraft();
  List<Item> _catalog = const <Item>[];
  List<Customer> _customerList = const <Customer>[];
  bool _saving = false;

  InvoiceDraft get draft => _draft;

  /// Products that can be added (everything in stock first).
  List<Item> get catalog => _catalog;
  List<Customer> get customers => _customerList;
  bool get isSaving => _saving;

  Future<void> load() => runLoad(() async {
    _catalog = await _items.getAll();
    final summaries = await _customers.getAllWithSummary();
    _customerList = summaries.map((summary) => summary.customer).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  });

  /// Registers a new customer and selects him for this invoice.
  Future<void> addCustomer(CustomerInput input) async {
    final created = await _customers.create(input);
    _customerList = [..._customerList, created]
      ..sort((a, b) => a.name.compareTo(b.name));
    _draft = _draft.copyWith(customer: created);
    notifyListeners();
  }

  void selectCustomer(Customer? customer) {
    _draft = customer == null
        ? _draft.copyWith(clearCustomer: true)
        : _draft.copyWith(customer: customer);
    notifyListeners();
  }

  void setPaymentMethod(PaymentMethod method) {
    _draft = _draft.copyWith(paymentMethod: method);
    notifyListeners();
  }

  void setPartialPaid(Money amount) {
    _draft = _draft.copyWith(partialPaid: amount);
    notifyListeners();
  }

  void setNotes(String notes) => _draft = _draft.copyWith(notes: notes);

  /// Adds one piece of [item]; throws [InsufficientStockException] when the
  /// stock does not allow it.
  void addItem(Item item) {
    final index = _draft.lines.indexWhere((line) => line.itemId == item.id);
    final inInvoice = index == -1 ? 0 : _draft.lines[index].quantity;
    if (inInvoice + 1 > item.quantity) {
      throw InsufficientStockException(
        itemName: item.name,
        available: item.quantity,
        requested: inInvoice + 1,
      );
    }
    _draft = _draft.addItem(item);
    notifyListeners();
  }

  /// Changes a line quantity; throws [InsufficientStockException] above stock.
  void setLineQuantity(int index, int quantity) {
    final line = _draft.lines[index];
    if (quantity < 1) {
      throw const ValidationException('الكمية يجب أن تكون 1 على الأقل.');
    }
    if (quantity > line.available) {
      throw InsufficientStockException(
        itemName: line.itemName,
        available: line.available,
        requested: quantity,
      );
    }
    _draft = _draft.updateLine(index, quantity: quantity);
    notifyListeners();
  }

  void setLineUnitPrice(int index, Money price) {
    _draft = _draft.updateLine(index, unitPrice: price);
    notifyListeners();
  }

  void removeLine(int index) {
    _draft = _draft.removeLine(index);
    notifyListeners();
  }

  /// Saves the invoice and returns its number.
  Future<int> save() async {
    _saving = true;
    notifyListeners();
    try {
      final id = await _invoices.create(_draft);
      // The delivery runs on its own: a slow network never blocks the sale.
      final sync = _sync;
      if (sync != null) unawaited(sync.onInvoiceCreated(id));
      return id;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
