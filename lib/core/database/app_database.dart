import 'dart:io';

import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/seed_data.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection of the application.
///
/// Repositories always read [db] when they run a query (they never keep the
/// [Database] object), so [replaceWith] can swap the file while the app runs.
final class AppDatabase {
  AppDatabase._(this._factory, this._database, this.path);

  /// Opens (and creates on the first run) the application database.
  ///
  /// [factory] and [directory] exist for tests; the defaults are the platform
  /// factory and the platform databases folder.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? directory,
    bool seed = true,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final folder = directory ?? await dbFactory.getDatabasesPath();
    final path = p.join(folder, AppConstants.databaseFileName);
    final database = await _openAt(dbFactory, path, seed: seed);
    return AppDatabase._(dbFactory, database, path);
  }

  final DatabaseFactory _factory;
  Database _database;

  /// Absolute path of the database file.
  final String path;

  /// The live connection. Do not cache it.
  Database get db => _database;

  static Future<Database> _openAt(
    DatabaseFactory factory,
    String path, {
    required bool seed,
  }) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onConfigure: _onConfigure,
        onCreate: (db, version) => _onCreate(db, seed: seed),
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// SQLite ignores foreign keys unless they are switched on for the connection.
  static Future<void> _onConfigure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

  static Future<void> _onCreate(Database db, {required bool seed}) async {
    final schema = db.batch();
    for (final statement in DbSchema.createStatements) {
      schema.execute(statement);
    }
    await schema.commit(noResult: true);
    if (seed) await _seedCatalog(db);
  }

  /// Add one `if (oldVersion < N)` block per schema change here.
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {}

  static Future<void> _seedCatalog(Database db) async {
    final createdAt = AppDates.isoDateTime(DateTime.now());
    final batch = db.batch();
    for (final item in kSeedItems) {
      batch.insert(DbTables.items, <String, Object?>{
        'category': item.category,
        'name': item.name,
        'sku': item.sku,
        'unit': item.unit,
        'cost_cents': item.costCents,
        'price_cents': item.priceCents,
        'quantity': item.quantity,
        'notes': item.notes,
        'created_at': createdAt,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Copies the database file to [target] (used to create backups).
  Future<void> copyTo(File target) async {
    try {
      // Move everything still sitting in the journal into the main file.
      await _database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } on DatabaseException {
      // Not in WAL mode: nothing to flush.
    }
    await target.parent.create(recursive: true);
    await File(path).copy(target.path);
  }

  /// Replaces the whole database with the content of [source].
  ///
  /// The caller must have validated [source] with [validateBackupFile].
  Future<void> replaceWith(File source) async {
    await _database.close();
    try {
      for (final suffix in const <String>['-wal', '-shm', '-journal']) {
        final leftover = File('$path$suffix');
        if (leftover.existsSync()) await leftover.delete();
      }
      final staged = File('$path.restoring');
      await source.copy(staged.path);
      await staged.rename(path);
    } finally {
      _database = await _openAt(_factory, path, seed: false);
    }
  }

  Future<void> close() => _database.close();

  /// Checks [file] with the same database factory this instance uses; throws
  /// [BackupException] unless it is a healthy copy of this app's data.
  Future<void> validateBackup(File file) =>
      validateBackupFile(file, factory: _factory);

  /// Throws [BackupException] unless [file] is a healthy copy of this app's data.
  static Future<void> validateBackupFile(
    File file, {
    DatabaseFactory? factory,
  }) async {
    if (!file.existsSync()) {
      throw const BackupException('الملف المحدد غير موجود.');
    }
    if (!await _hasSqliteHeader(file)) {
      throw const BackupException('الملف المحدد ليس نسخة احتياطية صالحة.');
    }

    final dbFactory = factory ?? databaseFactory;
    Database? candidate;
    try {
      candidate = await dbFactory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version =
          Sqflite.firstIntValue(
            await candidate.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      if (version < 1 || version > AppConstants.databaseVersion) {
        throw const BackupException(
          'هذه النسخة أُنشئت بإصدار غير مدعوم من التطبيق.',
        );
      }
      final rows = await candidate.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = rows.map((row) => row['name']).toSet();
      if (!DbTables.all.every(tables.contains)) {
        throw const BackupException(
          'النسخة الاحتياطية ناقصة أو من برنامج آخر.',
        );
      }
      final integrity = await candidate.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw const BackupException('النسخة الاحتياطية تالفة.');
      }
    } on DatabaseException {
      throw const BackupException('تعذّرت قراءة النسخة الاحتياطية.');
    } finally {
      await candidate?.close();
    }
  }

  static Future<bool> _hasSqliteHeader(File file) async {
    const magic = 'SQLite format 3\u0000';
    final reader = await file.open();
    try {
      final bytes = await reader.read(magic.length);
      return String.fromCharCodes(bytes) == magic;
    } finally {
      await reader.close();
    }
  }
}
