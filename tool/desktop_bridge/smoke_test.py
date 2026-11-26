#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Quick smoke test for the desktop bridge with no extra packages.

Starts `bridge.py` on a free port with a temporary database, then checks the
protocol the phone uses:

    python tool/desktop_bridge/smoke_test.py

Exits with 0 on success and non-zero on any failure. Used in CI and locally
before shipping a new build.
"""

from __future__ import annotations

import json
import os
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "bridge.py")
TOKEN = "smoke-token"
INVOICE = {
    "uid": "smoke-device:1",
    "device": "smoke-device",
    "sent_at": "2026-11-14T10:00:00",
    "invoice": {
        "number": 1,
        "customer": "Smoke Test",
        "phone": "0999999999",
        "payment_method": "cash",
        "date": "2026-11-14",
        "created_at": "2026-11-14T10:00:00",
        "total_cents": 4500,
        "paid_cents": 4500,
        "profit_cents": 1000,
        "notes": "",
    },
    "lines": [
        {
            "name": "Pipe 1/2",
            "category": "Pipes",
            "sku": "P-1",
            "unit": "pc",
            "quantity": 4,
            "unit_cost_cents": 150,
            "unit_price_cents": 250,
        },
        {
            "name": "Mixer",
            "category": "Mixers",
            "sku": "M-1",
            "unit": "pc",
            "quantity": 5,
            "unit_cost_cents": 200,
            "unit_price_cents": 700,
        },
    ],
}
REQUIRED_TABLES = {
    "items",
    "customers",
    "invoices",
    "invoice_items",
    "payments",
    "customer_receipts",
    "purchases",
    "purchase_items",
    "customer_payouts",
    "purchase_payments",
}

failures = []


def check(name, condition, detail=""):
    print(("PASS  " if condition else "FAIL  ") + name + (("  [" + detail + "]") if detail else ""))
    if not condition:
        failures.append(name)


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def request(base, method, path, body=None, token=TOKEN, content_type="application/json"):
    req = urllib.request.Request(base + path, data=body, method=method)
    if token:
        req.add_header("X-Bkdash-Token", token)
    if body is not None:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def wait_until_ready(base, process, log_path):
    for _ in range(60):
        if process.poll() is not None:
            break
        try:
            status, _ = request(base, "GET", "/api/ping")
            if status == 200:
                return True
        except OSError:
            pass
        time.sleep(0.5)
    with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
        print(handle.read())
    return False


def main():
    port = free_port()
    base = "http://127.0.0.1:%d" % port

    with tempfile.TemporaryDirectory() as work:
        database = os.path.join(work, "bkdash.db")
        backups = os.path.join(work, "backups")
        log_path = os.path.join(work, "bridge.log")
        with open(log_path, "w", encoding="utf-8") as log:
            process = subprocess.Popen(
                [
                    sys.executable,
                    BRIDGE,
                    "--port",
                    str(port),
                    "--host",
                    "127.0.0.1",
                    "--database",
                    database,
                    "--backups",
                    backups,
                    "--token",
                    TOKEN,
                ],
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        try:
            if not wait_until_ready(base, process, log_path):
                print("FAIL  the bridge did not start")
                return 1

            status, _ = request(base, "GET", "/api/ping", token=None)
            check("the bridge refuses requests without the token", status == 401, str(status))

            status, body = request(base, "GET", "/api/ping")
            info = json.loads(body) if status == 200 else {}
            check("ping answers with the database counts", status == 200 and info.get("invoices") == 0, body.decode())

            status, body = request(base, "POST", "/api/invoices", json.dumps(INVOICE).encode())
            stored = json.loads(body) if status == 200 else {}
            check("a new invoice is stored", stored.get("stored") is True, body.decode())

            status, body = request(base, "POST", "/api/invoices", json.dumps(INVOICE).encode())
            again = json.loads(body) if status == 200 else {}
            check("the same invoice is not stored twice", again.get("duplicate") is True, body.decode())

            status, database_bytes = request(base, "GET", "/api/database")
            check("the phone can pull the database", status == 200 and database_bytes.startswith(b"SQLite format 3"), str(status))

            pulled = os.path.join(work, "pulled.db")
            with open(pulled, "wb") as handle:
                handle.write(database_bytes)
            connection = sqlite3.connect(pulled)
            try:
                version = connection.execute("PRAGMA user_version").fetchone()[0]
                check("the database version is the one the app accepts", version == 3, str(version))
                tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
                check("every app table exists", REQUIRED_TABLES <= tables, ", ".join(sorted(tables)))
                check("the database passes SQLite's integrity check", connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok")
                check("the invoice keeps its amounts", connection.execute("SELECT total_cents, paid_cents FROM invoices").fetchall() == [(4500, 4500)])
                check("both product lines are stored", connection.execute("SELECT COUNT(*) FROM invoice_items").fetchone()[0] == 2)
                check("the payment is recorded", connection.execute("SELECT amount_cents FROM payments").fetchall() == [(4500,)])
            finally:
                connection.close()

            status, body = request(base, "POST", "/api/backup", database_bytes, content_type="application/vnd.sqlite3")
            saved = json.loads(body).get("saved", "") if status == 200 else ""
            check("the phone backup is saved on the computer", status == 200 and os.path.exists(saved), str(status))

            status, _ = request(base, "POST", "/api/backup", b"not a database")
            check("a file that is not a database is refused", status == 400, str(status))
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()

    if failures:
        print("\n%d check(s) failed: %s" % (len(failures), ", ".join(failures)))
        return 1
    print("\nAll bridge checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
