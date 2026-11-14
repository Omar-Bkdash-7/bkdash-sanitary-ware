import 'package:flutter/foundation.dart';

/// Tells every screen holding cached data that the database content changed.
///
/// Repositories call [markChanged] after each successful write; controllers
/// listen to it and reload what they display. This keeps the controllers
/// independent from each other.
class DataChangeNotifier extends ChangeNotifier {
  void markChanged() => notifyListeners();
}
