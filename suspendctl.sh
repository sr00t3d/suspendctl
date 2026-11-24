#!/usr/bin/env bash
# ==============================================================================
# suspendctl.sh — Unified Account & Maintenance Suspend/Unsuspend CLI (v2.0.0)
# Modernized clean-room implementation inspired by legacy unsuspend.linux.sh.
# Copyright (c) 2026 Percio Castelo — Apache-2.0 License
# ==============================================================================
set -euo pipefail

VERSION="2.0.0"

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required (3.6+)." >&2
    exit 1
fi

read -r -d '' PY_SCRIPT << 'EOF' || true
import argparse
import csv
import datetime
import io
import json
import os
import pwd
import shutil
import subprocess
import sys

VERSION = "2.0.0"


class Colors:
    def __init__(self, enabled=True):
        self.RESET = "\033[0m" if enabled else ""
        self.BOLD = "\033[1m" if enabled else ""
        self.CYAN = "\033[36m" if enabled else ""
        self.GREEN = "\033[32m" if enabled else ""
        self.YELLOW = "\033[33m" if enabled else ""
        self.RED = "\033[31m" if enabled else ""


def save_state(state_dir, name, data):
    os.makedirs(state_dir, exist_ok=True)
    path = os.path.join(state_dir, f"{name}.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.chmod(path, 0o600)
    return path


def load_state(state_dir, name):
    path = os.path.join(state_dir, f"{name}.json")
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def remove_state(state_dir, name):
    path = os.path.join(state_dir, f"{name}.json")
    if os.path.isfile(path):
        os.unlink(path)


def has_cpanel_user(username, cpanel_root):
    return os.path.isfile(os.path.join(cpanel_root, "users", username))


def is_cpanel_suspended(username, cpanel_root):
    return os.path.isfile(os.path.join(cpanel_root, "suspended", username))


def run_cmd(cmd):
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)
    return res.returncode == 0, res.stdout.strip()


def cmd_suspend(args):
    user = args.user
    reason = args.reason or "Administrative suspension"
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if has_cpanel_user(user, args.cpanel_root):
        backend = "cpanel"
        whm = shutil.which("whmapi1")
        if args.dry_run:
            return [{"action": "suspend", "target": user, "backend": backend, "status": "DRY_RUN", "reason": reason}]
        if not whm:
            return [{"action": "suspend", "target": user, "backend": backend, "status": "ERROR", "reason": "whmapi1 not found"}]
        ok, out = run_cmd([whm, "suspendacct", f"user={user}", f"reason={reason}"])
        save_state(args.state_dir, f"acct-{user}", {"user": user, "backend": "cpanel", "reason": reason, "suspended_at": ts})
        return [{"action": "suspend", "target": user, "backend": backend, "status": "SUSPENDED" if ok else "ERROR", "reason": reason if ok else out}]

    # Standalone Linux account
    try:
        pw = pwd.getpwnam(user)
    except KeyError:
        return [{"action": "suspend", "target": user, "backend": "linux", "status": "ERROR", "reason": f"User '{user}' not found"}]

    if pw.pw_uid == 0:
        return [{"action": "suspend", "target": user, "backend": "linux", "status": "ERROR", "reason": "Refusing to suspend UID 0 (root)"}]

    if args.dry_run:
        return [{"action": "suspend", "target": user, "backend": "linux", "status": "DRY_RUN", "reason": reason}]

    save_state(args.state_dir, f"acct-{user}", {
        "user": user,
        "backend": "linux",
        "original_shell": pw.pw_shell,
        "reason": reason,
        "suspended_at": ts,
    })

    usermod = shutil.which("usermod")
    nologin = "/usr/sbin/nologin" if os.path.exists("/usr/sbin/nologin") else "/sbin/nologin"
    if usermod:
        ok, out = run_cmd([usermod, "-L", "-s", nologin, user])
        if not ok:
            return [{"action": "suspend", "target": user, "backend": "linux", "status": "ERROR", "reason": out}]
    if args.kill_procs:
        pkill = shutil.which("pkill")
        if pkill:
            run_cmd([pkill, "-u", user])

    return [{"action": "suspend", "target": user, "backend": "linux", "status": "SUSPENDED", "reason": reason}]


def cmd_unsuspend(args):
    user = args.user
    state = load_state(args.state_dir, f"acct-{user}")

    if has_cpanel_user(user, args.cpanel_root):
        backend = "cpanel"
        whm = shutil.which("whmapi1")
        if args.dry_run:
            return [{"action": "unsuspend", "target": user, "backend": backend, "status": "DRY_RUN", "reason": "-"}]
        if not whm:
            return [{"action": "unsuspend", "target": user, "backend": backend, "status": "ERROR", "reason": "whmapi1 not found"}]
        ok, out = run_cmd([whm, "unsuspendacct", f"user={user}"])
        if ok:
            remove_state(args.state_dir, f"acct-{user}")
        return [{"action": "unsuspend", "target": user, "backend": backend, "status": "ACTIVE" if ok else "ERROR", "reason": "-" if ok else out}]

    try:
        pwd.getpwnam(user)
    except KeyError:
        return [{"action": "unsuspend", "target": user, "backend": "linux", "status": "ERROR", "reason": f"User '{user}' not found"}]

    orig_shell = (state or {}).get("original_shell") or "/bin/bash"
    if args.dry_run:
        return [{"action": "unsuspend", "target": user, "backend": "linux", "status": "DRY_RUN", "reason": f"restore shell {orig_shell}"}]

    usermod = shutil.which("usermod")
    if usermod:
        ok, out = run_cmd([usermod, "-U", "-s", orig_shell, user])
        if not ok:
            return [{"action": "unsuspend", "target": user, "backend": "linux", "status": "ERROR", "reason": out}]
    remove_state(args.state_dir, f"acct-{user}")
    return [{"action": "unsuspend", "target": user, "backend": "linux", "status": "ACTIVE", "reason": f"shell restored ({orig_shell})"}]


def cmd_status(args):
    rows = []
    if args.user:
        u = args.user
        st = load_state(args.state_dir, f"acct-{u}")
        cp_susp = is_cpanel_suspended(u, args.cpanel_root)
        status = "SUSPENDED" if (cp_susp or st) else "ACTIVE"
        rows.append({
            "action": "status",
            "target": u,
            "backend": "cpanel" if has_cpanel_user(u, args.cpanel_root) else "linux",
            "status": status,
            "reason": (st or {}).get("reason", "-"),
        })
        return rows

    if os.path.isdir(args.state_dir):
        for fn in sorted(os.listdir(args.state_dir)):
            if fn.startswith("acct-") and fn.endswith(".json"):
                st = load_state(args.state_dir, fn[:-5])
                if st:
                    rows.append({
                        "action": "status",
                        "target": st.get("user", "-"),
                        "backend": st.get("backend", "-"),
                        "status": "SUSPENDED",
                        "reason": st.get("reason", "-"),
                    })
    return rows


def cmd_maintenance(args):
    motd_path = os.path.join(args.etc_root, "motd")
    nologin_path = os.path.join(args.etc_root, "nologin")
    services = [s.strip() for s in (args.services or "").split(",") if s.strip()]
    systemctl = shutil.which("systemctl")

    if args.m_action == "status":
        st = load_state(args.state_dir, "maintenance")
        active = bool(st) or os.path.isfile(nologin_path)
        return [{
            "action": "maintenance_status",
            "target": "host",
            "backend": "systemd/etc",
            "status": "MAINTENANCE_ON" if active else "ONLINE",
            "reason": (st or {}).get("reason", "-"),
        }]

    if args.m_action == "on":
        reason = args.reason or "Scheduled server maintenance"
        if args.dry_run:
            return [{"action": "maintenance_on", "target": "host", "backend": "systemd/etc", "status": "DRY_RUN", "reason": reason}]
        orig_motd = ""
        if os.path.isfile(motd_path):
            with open(motd_path, "r", encoding="utf-8", errors="replace") as fh:
                orig_motd = fh.read()
        save_state(args.state_dir, "maintenance", {
            "reason": reason,
            "original_motd": orig_motd,
            "services": services,
            "enabled_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        })
        os.makedirs(args.etc_root, exist_ok=True)
        with open(motd_path, "w", encoding="utf-8") as fh:
            fh.write(f"*** MAINTENANCE MODE: {reason} ***\n")
        with open(nologin_path, "w", encoding="utf-8") as fh:
            fh.write(f"System is in maintenance mode: {reason}\n")
        if systemctl and services:
            for svc in services:
                run_cmd([systemctl, "stop", svc])
        return [{"action": "maintenance_on", "target": "host", "backend": "systemd/etc", "status": "MAINTENANCE_ON", "reason": reason}]

    # maintenance off
    st = load_state(args.state_dir, "maintenance")
    if args.dry_run:
        return [{"action": "maintenance_off", "target": "host", "backend": "systemd/etc", "status": "DRY_RUN", "reason": "restore motd & services"}]
    if st is not None:
        with open(motd_path, "w", encoding="utf-8") as fh:
            fh.write(st.get("original_motd", ""))
    if os.path.isfile(nologin_path):
        os.unlink(nologin_path)
    svc_list = services or (st or {}).get("services", [])
    if systemctl and svc_list:
        for svc in svc_list:
            run_cmd([systemctl, "start", svc])
    remove_state(args.state_dir, "maintenance")
    return [{"action": "maintenance_off", "target": "host", "backend": "systemd/etc", "status": "ONLINE", "reason": "restored"}]


def render_output(rows, fmt, c):
    if fmt == "json":
        print(json.dumps(rows, indent=2))
        return
    if fmt == "csv":
        buf = io.StringIO()
        w = csv.DictWriter(buf, fieldnames=["action", "target", "backend", "status", "reason"])
        w.writeheader()
        for r in rows:
            w.writerow(r)
        sys.stdout.write(buf.getvalue())
        return

    print(f"{c.BOLD}{c.CYAN}=== suspendctl.sh v{VERSION} | Account & Maintenance Control ==={c.RESET}")
    if not rows:
        print("  (no suspended accounts or state entries)")
        return
    print(f"{c.BOLD}{'ACTION':<18} {'TARGET':<16} {'BACKEND':<12} {'STATUS':<15} REASON{c.RESET}")
    print("-" * 82)
    for r in rows:
        st = r["status"]
        col = c.RED if st in ("SUSPENDED", "ERROR", "MAINTENANCE_ON") else (c.YELLOW if st == "DRY_RUN" else c.GREEN)
        print(f"{r['action']:<18} {r['target']:<16} {r['backend']:<12} {col}{st:<15}{c.RESET} {r['reason']}")


def main():
    parser = argparse.ArgumentParser(
        prog="suspendctl.sh",
        description="Unified Account & Maintenance Suspend/Unsuspend CLI (v2.0.0)",
    )
    parser.add_argument("-v", "--version", action="version", version=f"suspendctl.sh {VERSION}")
    sub = parser.add_subparsers(dest="subcommand", required=True)

    def add_common(p):
        p.add_argument("--dry-run", action="store_true", help="Preview changes without modifying state")
        p.add_argument("--etc-root", default="/etc", help="Custom /etc root")
        p.add_argument("--cpanel-root", default="/var/cpanel", help="Custom /var/cpanel root")
        p.add_argument("--state-dir", default="/var/lib/suspendctl", help="State directory (chmod 600 JSON)")
        p.add_argument("-o", "--output", choices=["table", "json", "csv"], default="table")
        p.add_argument("--no-color", action="store_true")

    ps = sub.add_parser("suspend", help="Suspend a cPanel or Linux account")
    ps.add_argument("user", help="Username to suspend")
    ps.add_argument("--reason", help="Suspension reason")
    ps.add_argument("--kill-procs", action="store_true", help="Terminate active user processes")
    add_common(ps)

    pu = sub.add_parser("unsuspend", help="Unsuspend a cPanel or Linux account")
    pu.add_argument("user", help="Username to unsuspend")
    add_common(pu)

    pst = sub.add_parser("status", help="Show suspension status for user or all tracked accounts")
    pst.add_argument("user", nargs="?", help="Optional username")
    add_common(pst)

    pm = sub.add_parser("maintenance", help="Enable, disable, or inspect host maintenance mode")
    pm.add_argument("m_action", choices=["on", "off", "status"], help="Maintenance action")
    pm.add_argument("--reason", help="Maintenance banner message")
    pm.add_argument("--services", help="Comma-separated systemd services to stop/start")
    add_common(pm)

    args = parser.parse_args()
    handlers = {
        "suspend": cmd_suspend,
        "unsuspend": cmd_unsuspend,
        "status": cmd_status,
        "maintenance": cmd_maintenance,
    }
    rows = handlers[args.subcommand](args)
    use_color = sys.stdout.isatty() and not args.no_color
    render_output(rows, args.output, Colors(enabled=use_color))
    if any(r["status"] == "ERROR" for r in rows):
        sys.exit(1)


if __name__ == "__main__":
    main()
EOF

python3 -c "$PY_SCRIPT" "$@"
