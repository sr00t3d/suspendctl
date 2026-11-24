# suspendctl — CLI Unificada de Suspensão/Reativação de Contas e Manutenção (`v2.0.0`)

![suspendctl cover](suspendctl-cover.webp)

Uma CLI moderna e independente em Bash + Python 3 que unifica em uma única ferramenta **suspender e desuspender** tanto **contas cPanel/Linux** quanto o **modo de manutenção do servidor**, com estado reversível `chmod 600` e saídas `table` / `json` / `csv`.

## Modernização Histórica

Inspirado no script legado **`unsuspend.linux.sh`**, que realizava apenas a reversão unilateral de uma suspensão rígida de servidor (`chattr -ia /etc/motd`, `/etc/rc.d/rc.local`, SysVinit `/etc/init.d/httpd` + `firewall`, limpeza de semáforos `ipcs -s` e edição de `/root/.bash_history`).

Na versão `v2.0.0`, foi reescrito do zero como **`suspendctl.sh`** (**Bash + Python 3.6+ stdlib**) unificando **suspensão e reativação** em um ciclo único e seguro:
- **Ciclo Unificado (`suspend` / `unsuspend` / `status`)**: Suporta contas cPanel (`whmapi1 suspendacct`/`unsuspendacct`) e contas Linux (`usermod -L/-U` + backup `chmod 600` do shell original).
- **Manutenção Reversível (`maintenance on|off|status`)**: Substitui SysVinit por `systemd`, `/etc/nologin` e snapshot reversível de `/etc/motd`.
- **Integridade Forense**: Remove qualquer alteração de `.bash_history`, bloqueia suspensão do `root` (`UID 0`) e oferece `--dry-run`.

## Exemplo de Saída Real

```text
$ ./suspendctl.sh maintenance on --reason "Kernel upgrade" --etc-root /tmp/susp-e2e/etc --state-dir /tmp/susp-e2e/state --no-color
=== suspendctl.sh v2.0.0 | Account & Maintenance Control ===
ACTION             TARGET           BACKEND      STATUS          REASON
----------------------------------------------------------------------------------
maintenance_on     host             systemd/etc  MAINTENANCE_ON  Kernel upgrade
```

## Licença

Apache-2.0 — veja [LICENSE](LICENSE).
