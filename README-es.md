# suspendctl — CLI Unificada de Suspensión y Reactivación (`v2.0.0`)

![suspendctl cover](suspendctl-cover.webp)

Una CLI moderna e independiente en Bash + Python 3 que unifica en una sola herramienta **suspender y reactivar** tanto **cuentas cPanel/Linux** como el **modo de mantenimiento del servidor**, con estado reversible `chmod 600` y salidas `table` / `json` / `csv`.

## Modernización Histórica

Inspirado en el script legado **`unsuspend.linux.sh`**, que únicamente revertía una suspensión rígida del servidor (SysVinit, `chattr`, `ipcs -s` y filtrado de `.bash_history`).

En `v2.0.0`, fue reescrito como **`suspendctl.sh`** (**Bash + Python 3.6+ stdlib**) unificando `suspend`, `unsuspend`, `status` y `maintenance on|off|status` con `--dry-run`, bloqueo de `UID 0` y sin alterar historiales del sistema.

## Ejemplo de Salida Real

```text
$ ./suspendctl.sh maintenance on --reason "Kernel upgrade" --etc-root /tmp/susp-e2e/etc --state-dir /tmp/susp-e2e/state --no-color
=== suspendctl.sh v2.0.0 | Account & Maintenance Control ===
ACTION             TARGET           BACKEND      STATUS          REASON
----------------------------------------------------------------------------------
maintenance_on     host             systemd/etc  MAINTENANCE_ON  Kernel upgrade
```

## Licencia

Apache-2.0 — ver [LICENSE](LICENSE).
