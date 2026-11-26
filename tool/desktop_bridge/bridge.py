#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""برنامج الكمبيوتر (Bridge) لتطبيق بكداش.

يعمل على جهاز الكمبيوتر داخل شبكة المحل ويقوم بثلاثة أمور:
  1. يستقبل كل فاتورة جديدة من الهاتف ويسجّلها في قاعدة بيانات SQLite
     لها نفس جداول التطبيق (items / customers / invoices / invoice_items /
     payments / customer_receipts / purchases / purchase_items /
     customer_payouts / purchase_payments)، فيمكن لأي برنامج سطح مكتب أن يقرأها.
  2. يستقبل نسخة كاملة من قاعدة بيانات الهاتف ويحفظها في مجلد backups.
  3. يرسل قاعدة بياناته إلى الهاتف عند طلب "سحب البيانات (Extract)".

لا يستخدم أي قاعدة بيانات سحابية: كل شيء داخل الشبكة المحلية.

التشغيل:
    python bridge.py

الخيارات:
    --port 8756              المنفذ (نفسه في التطبيق)
    --host 0.0.0.0           العنوان الذي يستمع عليه
    --database bkdash.db     ملف قاعدة البيانات (يُنشأ تلقائياً)
    --token  رمز-الربط       رمز مشترك (يُولّد ويُحفظ في token.txt إن لم يُعط)
"""

from __future__ import annotations

import argparse
import hmac
import json
import os
import secrets
import socket
import sqlite3
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

# النصوص العربية في الطرفية: اطبع دائماً UTF-8 ولا تفشل مهما كانت الصفحة الرمزية.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

VERSION = "1.0"
MAX_BODY_BYTES = 256 * 1024 * 1024  # 256 MB: تكفي لأي قاعدة بيانات واقعية.

HERE = os.path.dirname(os.path.abspath(__file__))

# نفس مخطط التطبيق (lib/core/database/db_schema.dart) مع IF NOT EXISTS.
SCHEMA = [
    """
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      name TEXT NOT NULL,
      sku TEXT NOT NULL UNIQUE,
      unit TEXT NOT NULL DEFAULT 'قطعة',
      cost_cents INTEGER NOT NULL CHECK (cost_cents >= 0),
      price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
      quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
      notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )""",
    "CREATE INDEX IF NOT EXISTS idx_items_category ON items (category)",
    """
    CREATE TABLE IF NOT EXISTS customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      address TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )""",
    "CREATE INDEX IF NOT EXISTS idx_customers_name ON customers (name)",
    """
    CREATE TABLE IF NOT EXISTS invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER REFERENCES customers (id) ON DELETE RESTRICT,
      customer_name TEXT NOT NULL,
      customer_phone TEXT NOT NULL DEFAULT '',
      payment_method TEXT NOT NULL,
      invoice_date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
      paid_cents INTEGER NOT NULL DEFAULT 0
        CHECK (paid_cents >= 0 AND paid_cents <= total_cents),
      profit_cents INTEGER NOT NULL DEFAULT 0,
      notes TEXT NOT NULL DEFAULT ''
    )""",
    "CREATE INDEX IF NOT EXISTS idx_invoices_date ON invoices (invoice_date)",
    "CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices (customer_id)",
    """
    CREATE TABLE IF NOT EXISTS invoice_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
      item_id INTEGER REFERENCES items (id) ON DELETE SET NULL,
      item_name TEXT NOT NULL,
      category TEXT NOT NULL,
      sku TEXT NOT NULL,
      unit TEXT NOT NULL,
      quantity INTEGER NOT NULL CHECK (quantity > 0),
      unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
      unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0)
    )""",
    "CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice "
    "ON invoice_items (invoice_id)",
    """
    CREATE TABLE IF NOT EXISTS customer_receipts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      note TEXT NOT NULL DEFAULT '',
      paid_at TEXT NOT NULL,
      paid_date TEXT NOT NULL
    )""",
    """
    CREATE TABLE IF NOT EXISTS payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
      receipt_id INTEGER REFERENCES customer_receipts (id) ON DELETE SET NULL,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      paid_at TEXT NOT NULL,
      paid_date TEXT NOT NULL
    )""",
    "CREATE INDEX IF NOT EXISTS idx_payments_date ON payments (paid_date)",
    "CREATE INDEX IF NOT EXISTS idx_payments_invoice ON payments (invoice_id)",
    """
    CREATE TABLE IF NOT EXISTS purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL REFERENCES customers (id) ON DELETE RESTRICT,
      customer_name TEXT NOT NULL,
      customer_phone TEXT NOT NULL DEFAULT '',
      purchase_date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
      paid_cents INTEGER NOT NULL DEFAULT 0
        CHECK (paid_cents >= 0 AND paid_cents <= total_cents),
      notes TEXT NOT NULL DEFAULT ''
    )""",
    "CREATE INDEX IF NOT EXISTS idx_purchases_date ON purchases (purchase_date)",
    "CREATE INDEX IF NOT EXISTS idx_purchases_customer ON purchases (customer_id)",
    """
    CREATE TABLE IF NOT EXISTS purchase_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      purchase_id INTEGER NOT NULL REFERENCES purchases (id) ON DELETE CASCADE,
      item_id INTEGER REFERENCES items (id) ON DELETE SET NULL,
      item_name TEXT NOT NULL,
      category TEXT NOT NULL,
      sku TEXT NOT NULL,
      unit TEXT NOT NULL,
      quantity INTEGER NOT NULL CHECK (quantity > 0),
      unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
      previous_quantity INTEGER NOT NULL DEFAULT 0
        CHECK (previous_quantity >= 0),
      previous_cost_cents INTEGER NOT NULL DEFAULT 0
        CHECK (previous_cost_cents >= 0)
    )""",
    "CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase "
    "ON purchase_items (purchase_id)",
    """
    CREATE TABLE IF NOT EXISTS customer_payouts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      note TEXT NOT NULL DEFAULT '',
      paid_at TEXT NOT NULL,
      paid_date TEXT NOT NULL
    )""",
    "CREATE INDEX IF NOT EXISTS idx_customer_payouts_customer "
    "ON customer_payouts (customer_id)",
    "CREATE INDEX IF NOT EXISTS idx_customer_payouts_date "
    "ON customer_payouts (paid_date)",
    """
    CREATE TABLE IF NOT EXISTS purchase_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      purchase_id INTEGER NOT NULL REFERENCES purchases (id) ON DELETE CASCADE,
      payout_id INTEGER REFERENCES customer_payouts (id) ON DELETE SET NULL,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      paid_at TEXT NOT NULL,
      paid_date TEXT NOT NULL
    )""",
    "CREATE INDEX IF NOT EXISTS idx_purchase_payments_purchase "
    "ON purchase_payments (purchase_id)",
    "CREATE INDEX IF NOT EXISTS idx_purchase_payments_date "
    "ON purchase_payments (paid_date)",
    # جدول خاص بهذا البرنامج فقط: يمنع تسجيل الفاتورة نفسها مرتين.
    """
    CREATE TABLE IF NOT EXISTS sync_log (
      uid TEXT PRIMARY KEY,
      invoice_id INTEGER NOT NULL,
      device TEXT NOT NULL DEFAULT '',
      received_at TEXT NOT NULL
    )""",
]

INSERT_INVOICE = """
INSERT INTO invoices (
  customer_id, customer_name, customer_phone, payment_method, invoice_date,
  created_at, total_cents, paid_cents, profit_cents, notes
) VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?)
"""

INSERT_LINE = """
INSERT INTO invoice_items (
  invoice_id, item_id, item_name, category, sku, unit, quantity,
  unit_cost_cents, unit_price_cents
) VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?)
"""


def as_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def timestamp():
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


class BridgeState:
    """قاعدة البيانات والعمليات التي يقوم بها البرنامج."""

    def __init__(self, db_path, backups_dir, token):
        self.db_path = os.path.abspath(db_path)
        self.backups_dir = os.path.abspath(backups_dir)
        self.token = token
        self.lock = threading.Lock()
        os.makedirs(os.path.dirname(self.db_path) or ".", exist_ok=True)
        self.db = sqlite3.connect(self.db_path, check_same_thread=False)
        self.db.execute("PRAGMA foreign_keys = ON")
        self._ensure_schema()

    def _ensure_schema(self):
        self.db.executescript(";\n".join(SCHEMA) + ";")
        # التطبيق يرفض النسخة الأقدم من مخططه، ويرحّل نسخة 1 تلقائياً.
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version < 2:
            self.db.execute("PRAGMA user_version = 2")
        self.db.commit()

    def _count(self, table):
        return self.db.execute("SELECT COUNT(*) FROM %s" % table).fetchone()[0]

    def info(self):
        with self.lock:
            return {
                "app": "bkdash-bridge",
                "version": VERSION,
                "database": self.db_path,
                "items": self._count("items"),
                "customers": self._count("customers"),
                "invoices": self._count("invoices"),
            }

    def store_invoice(self, payload):
        uid = str(payload.get("uid") or "").strip()
        if not uid:
            raise ValueError("الطلب لا يحمل معرّف الفاتورة (uid).")
        invoice = payload.get("invoice") or {}
        lines = payload.get("lines") or []

        customer = str(invoice.get("customer") or "زبون نقدي")
        phone = str(invoice.get("phone") or "")
        method = str(invoice.get("payment_method") or "cash")
        invoice_date = str(invoice.get("date") or datetime.now().strftime("%Y-%m-%d"))
        created_at = str(invoice.get("created_at") or timestamp())
        total = max(as_int(invoice.get("total_cents")), 0)
        paid = min(max(as_int(invoice.get("paid_cents")), 0), total)
        profit = as_int(invoice.get("profit_cents"))
        notes = str(invoice.get("notes") or "")

        with self.lock:
            known = self.db.execute(
                "SELECT invoice_id FROM sync_log WHERE uid = ?", (uid,)
            ).fetchone()
            if known:
                return {"stored": False, "duplicate": True, "invoice_id": known[0]}
            try:
                cursor = self.db.execute(
                    INSERT_INVOICE,
                    (customer, phone, method, invoice_date, created_at,
                     total, paid, profit, notes),
                )
                invoice_id = cursor.lastrowid
                for line in lines:
                    self.db.execute(
                        INSERT_LINE,
                        (
                            invoice_id,
                            str(line.get("name") or ""),
                            str(line.get("category") or ""),
                            str(line.get("sku") or ""),
                            str(line.get("unit") or "قطعة"),
                            max(as_int(line.get("quantity"), 1), 1),
                            max(as_int(line.get("unit_cost_cents")), 0),
                            max(as_int(line.get("unit_price_cents")), 0),
                        ),
                    )
                if paid > 0:
                    self.db.execute(
                        "INSERT INTO payments "
                        "(invoice_id, receipt_id, amount_cents, paid_at, paid_date) "
                        "VALUES (?, NULL, ?, ?, ?)",
                        (invoice_id, paid, created_at, invoice_date),
                    )
                self.db.execute(
                    "INSERT INTO sync_log (uid, invoice_id, device, received_at) "
                    "VALUES (?, ?, ?, ?)",
                    (uid, invoice_id, str(payload.get("device") or ""), timestamp()),
                )
                self.db.commit()
            except Exception:
                self.db.rollback()
                raise
            return {"stored": True, "duplicate": False, "invoice_id": invoice_id}

    def save_backup(self, data):
        os.makedirs(self.backups_dir, exist_ok=True)
        name = "phone_backup_%s.db" % time.strftime("%Y%m%d_%H%M%S")
        path = os.path.join(self.backups_dir, name)
        index = 2
        while os.path.exists(path):
            path = os.path.join(
                self.backups_dir,
                "phone_backup_%s_%d.db" % (time.strftime("%Y%m%d_%H%M%S"), index),
            )
            index += 1
        with open(path, "wb") as handle:
            handle.write(data)
        return path

    def database_bytes(self):
        with self.lock:
            try:
                self.db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            except sqlite3.DatabaseError:
                pass
            self.db.commit()
            with open(self.db_path, "rb") as handle:
                return handle.read()

    def close(self):
        with self.lock:
            self.db.close()


class BridgeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "BkdashBridge/" + VERSION

    @property
    def state(self):
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, fmt, *args):
        sys.stdout.write("[%s] %s\n" % (time.strftime("%H:%M:%S"), fmt % args))
        sys.stdout.flush()

    # ------------------------------------------------------------------ أدوات
    def _authorized(self):
        supplied = (self.headers.get("X-Bkdash-Token") or "").strip()
        if not supplied:
            query = parse_qs(urlparse(self.path).query)
            supplied = (query.get("token") or [""])[0].strip()
        return hmac.compare_digest(supplied, self.state.token)

    def _send(self, code, data, content_type):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, code, payload):
        self._send(
            code,
            json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            "application/json; charset=utf-8",
        )

    def _read_body(self):
        length = as_int(self.headers.get("Content-Length"), 0)
        if length <= 0:
            return b""
        if length > MAX_BODY_BYTES:
            raise ValueError("حجم الطلب أكبر من المسموح.")
        chunks = []
        remaining = length
        while remaining > 0:
            chunk = self.rfile.read(min(remaining, 1024 * 1024))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    # -------------------------------------------------------------------- GET
    def do_GET(self):
        path = urlparse(self.path).path.rstrip("/") or "/"
        if not self._authorized():
            self._json(401, {"error": "رمز الربط غير صحيح."})
            return
        try:
            if path == "/api/ping":
                self._json(200, self.state.info())
            elif path == "/api/database":
                self._send(
                    200,
                    self.state.database_bytes(),
                    "application/vnd.sqlite3",
                )
            else:
                self._json(404, {"error": "مسار غير معروف."})
        except Exception as error:  # noqa: BLE001 - الخطأ يُرسل للهاتف
            self._json(500, {"error": str(error)})

    # ------------------------------------------------------------------- POST
    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/")
        if not self._authorized():
            self._json(401, {"error": "رمز الربط غير صحيح."})
            return
        try:
            body = self._read_body()
        except ValueError as error:
            self._json(400, {"error": str(error)})
            return
        try:
            if path == "/api/invoices":
                try:
                    payload = json.loads(body.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    self._json(400, {"error": "البيانات ليست JSON صالحاً."})
                    return
                if not isinstance(payload, dict):
                    self._json(400, {"error": "بنية الطلب غير صحيحة."})
                    return
                try:
                    result = self.state.store_invoice(payload)
                except ValueError as error:
                    self._json(400, {"error": str(error)})
                    return
                self._json(200, result)
            elif path == "/api/backup":
                if len(body) < 512 or not body.startswith(b"SQLite format 3"):
                    self._json(400, {"error": "الملف ليس قاعدة بيانات SQLite."})
                    return
                saved = self.state.save_backup(body)
                self.log_message("حُفظت نسخة الهاتف: %s", saved)
                self._json(200, {"saved": saved, "bytes": len(body)})
            else:
                self._json(404, {"error": "مسار غير معروف."})
        except Exception as error:  # noqa: BLE001
            self._json(500, {"error": str(error)})


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, state):
        self.state = state
        super().__init__(address, BridgeHandler)


def lan_addresses():
    """عناوين هذا الجهاز داخل الشبكة المحلية."""
    found = []
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.settimeout(0.3)
        probe.connect(("8.8.8.8", 80))
        found.append(probe.getsockname()[0])
        probe.close()
    except OSError:
        pass
    try:
        for item in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = item[4][0]
            if not address.startswith("127.") and address not in found:
                found.append(address)
    except OSError:
        pass
    return found


def read_or_create_token(path):
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as handle:
            token = handle.read().strip()
        if token:
            return token
    token = secrets.token_hex(8)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(token + "\n")
    return token


def main():
    parser = argparse.ArgumentParser(description="Bkdash desktop bridge")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8756)
    parser.add_argument(
        "--database", default=os.path.join(HERE, "data", "bkdash_sanitary_ware.db")
    )
    parser.add_argument("--backups", default=os.path.join(HERE, "backups"))
    parser.add_argument("--token", default="")
    args = parser.parse_args()

    token = args.token.strip() or read_or_create_token(
        os.path.join(HERE, "token.txt")
    )
    state = BridgeState(args.database, args.backups, token)
    server = BridgeServer((args.host, args.port), state)

    print("=" * 62)
    print("  بكداش - برنامج ربط الكمبيوتر (Bridge)")
    print("=" * 62)
    print("  المنفذ        : %d" % args.port)
    print("  قاعدة البيانات: %s" % state.db_path)
    print("  نسخ الهاتف    : %s" % state.backups_dir)
    print("  رمز الربط      : %s" % token)
    addresses = lan_addresses() or ["127.0.0.1"]
    print("  أدخل هذا العنوان في التطبيق (الإعدادات ← الربط مع الكمبيوتر):")
    for address in addresses:
        print("      %s" % address)
    print("-" * 62)
    print("  اترك هذه النافذة مفتوحة أثناء العمل. للإيقاف: Ctrl+C")
    print("=" * 62)
    sys.stdout.flush()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nإيقاف البرنامج...")
    finally:
        server.server_close()
        state.close()


if __name__ == "__main__":
    main()
