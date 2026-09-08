---
tags: [memory/repo, architecture]
---
# Архитектура `bin/xchg`

Один файл, секции сверху вниз:

1. **Утилиты** — `die/udie/warn`, `meta` (frontmatter), `title`, `body_of`, `file_epoch` (last_updated → дата коммита → mtime), `rel_time`.
2. **Конфиг** — `parse_conf` (awk печатает `G/H/S/E` строки с TAB, bash раскладывает в `HUBS[]`, `HUB_PATH/REMOTE/LOGIN/AGENTS`), `load_conf` (нет `xchg.conf` + `~/exchange/.git` → `CONF_MODE=legacy`, хаб `work`), правки конфига `conf_set_global/conf_set_hub/conf_rm_hub/conf_add_hub` (awk → tmp → mv), `ensure_conf` (создаёт из legacy).
3. **Синхронизация** — `hub_sync` (pull одного хаба; стампы в `.git/xchg-last-sync`, `.git/xchg-unavail`), `sync_hubs` (параллельно, общий дедлайн 20 с), `self_update` (pull репо клиента), `hub_push` (commit + pull --rebase + push ×3).
4. **Адресация** — `resolve_in_hub` (people/ → contacts.md, python3 casefold или awk), `resolve_rcpt` → `R_HUB/R_TO/R_DEST` (§4.3), `locate` → `L_HUB/L_REL` (файл по `hub:`, абсолютному пути или единственному совпадению).
5. **Агент/host** — `agent_repo_info` (git-common-dir → главный репо даже из worktree), `normalize_url`, `register_agent` (`agents.conf`, коллизия → exit 3), `agent_name`, `host_of_file` (тег host = второй компонент имени), `hub_hosts`, `cmd_host/cmd_hosts`.
6. **store** — `mirror_dir` (копия с удалениями и защитой чужих/своих файлов по тегу), `shared_conflicts`, `cmd_store`, `store_resolve_conflict`.
7. **Доска** — `board_rows` (свежайший `SESSION.<host>.md` на агента), `cmd_board`, `board_brief` (печатает только при изменении, сигнатура в `.git/xchg-board-shown`).
8. **Почта** — `list_dir/hub_inbox/cmd_inbox`, `cmd_read`, `write_msg`, `cmd_send`, `cmd_done`, `cmd_forward`, `cmd_who`, `cmd_projects`, `cmd_log`, `cmd_sync`.
9. **Хабы** — `cmd_hubs`, `cmd_hub add|rm|remote`, `init_hub_repo` (локальный хаб из `hub/README.md`).
10. **install/status/version/help**, диспетчер.

## Потоки

- **Хук** `xchg inbox --brief [--max-age 300]`: `sync_hubs` всех хабов → список писем → `board_brief`. Пусто → 0 байт.
- **send**: `sync_hubs` всех (нужны свежие contacts) → `resolve_rcpt` → `check_writable` → `write_msg` → `hub_push`.
- **store push**: проверка общих файлов → `mirror_dir push` (без предварительного pull!) → commit → `pull --rebase` (конфликт → `store_resolve_conflict`) → push.
- **store pull**: `hub_sync` → `mirror_dir pull`.

## Состояние на диске

- `~/.config/xchg/xchg.conf`, `agents.conf` — реестр хабов и имён агентов (не в git).
- `<clone>/.git/xchg-*` — стампы синка, недоступности, показанной доски. Всё пересчитываемое.
- `git config xchg.agent` в клоне рабочего репо — алиас агента; `git config xchg.me` в клоне хаба — login (v1).
