# suspendctl — Unified Account & Maintenance Suspend/Unsuspend CLI (`v2.0.0`)

![suspendctl cover](suspendctl-cover.webp)

A modern, standalone Bash + Python 3 CLI that unifies **suspending and unsuspending** both **cPanel/Linux user accounts** and **host maintenance mode** into one reversible, auditable tool with `table` / `json` / `csv` outputs.

## Historical Modernization

Inspired by the legacy **`unsuspend.linux.sh`** script (2010–2023), which only handled one-way recovery of a hardcoded server suspension (`chattr -ia /etc/motd`, `/etc/rc.d/rc.local`, SysVinit `/etc/init.d/httpd` + `firewall`, `ipcs -s` semaphore cleanup, and `/root/.bash_history` filtering).

In `v2.0.0`, it was rebuilt from scratch as **`suspendctl.sh`** (**Bash + Python 3.6+ stdlib**) to unify both **suspend** and **unsuspend** workflows cleanly and safely:
- **Unified Lifecycle (`suspend` / `unsuspend` / `status`)**: Supports cPanel (`whmapi1 suspendacct` / `unsuspendacct`) and standalone Linux accounts (`usermod -L/-U` + `/usr/sbin/nologin` with `chmod 600` JSON state backup to restore the exact original shell).
- **Reversible Host Maintenance (`maintenance on|off|status`)**: Replaces hardcoded SysVinit and `.motd` renames with `systemd` service control, `/etc/nologin`, and reversible `/etc/motd` snapshots.
- **Forensic Integrity**: Completely removes legacy `.bash_history` tampering, adds `--dry-run`, blocks `UID 0` suspension, and outputs `table`, `json`, or `csv`.

## Real Output Example

```text
$ ./suspendctl.sh maintenance on --reason "Kernel upgrade" --etc-root /tmp/susp-e2e/etc --state-dir /tmp/susp-e2e/state --no-color
=== suspendctl.sh v2.0.0 | Account & Maintenance Control ===
ACTION             TARGET           BACKEND      STATUS          REASON
----------------------------------------------------------------------------------
maintenance_on     host             systemd/etc  MAINTENANCE_ON  Kernel upgrade
```

## License

Apache-2.0 — see [LICENSE](LICENSE).
