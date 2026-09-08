# CLAUDE.md — xchg

Клиент обмена сообщениями между агентами Claude Code через git-хабы. Один bash-скрипт `bin/xchg`.
ТЗ — [docs/SPEC.md](docs/SPEC.md) (источник истины по поведению). Глубже — [`.claude-docs/`](.claude-docs/index.md).

## Documentation index
- [.claude-docs/index.md](.claude-docs/index.md) — что читать под какую задачу
- [.claude-docs/gotchas.md](.claude-docs/gotchas.md) — неочевидные ловушки (bash `set -e`, `local`, git rebase ours/theirs, store)
- [.claude-docs/architecture.md](.claude-docs/architecture.md) — устройство `bin/xchg`, потоки данных, store/board

## Commands
- `tests/run.sh [-v]` — e2e в песочнице (HOME подменяется, хабы — локальные bare). Обязателен перед коммитом в `bin/xchg`.
- `bash -n bin/xchg` — синтаксис.
- `XCHG_NO_SELFUPDATE=1 bin/xchg <cmd>` — прогнать клиент из репо против реальных хабов пользователя без самообновления.

## Boundaries
### MUST
- Клиент — чистый bash ≥ 4 + git/awk/sed/coreutils. python3 и jq только как необязательные ускорители (есть fallback).
- Любое изменение поведения — сначала правка `docs/SPEC.md`, затем код, затем тест в `tests/run.sh`.
- Ошибки на stderr, по-русски, с подсказкой следующей команды; код ≠ 0 (2 — usage, 3 — коллизия агента).
- Пустой ящик по всем хабам в `inbox --brief` → вывод 0 байт (хуки не должны тратить токены).
### MUST NOT
- Не добавлять реле между хабами, БД, HTTP, MCP — см. SPEC §3.
- Не запускать `bin/xchg install` в реальном HOME при разработке — только в песочнице (`tests/run.sh`).
- Не коммитить `~/.config/xchg/*` и содержимое хабов.

## Workflow
- Ветка `main`, коммиты однострочные, без Co-Authored-By. Remote: `ssh://git@source.pronchev.ru:2201/pronchev/xchg.git`.
