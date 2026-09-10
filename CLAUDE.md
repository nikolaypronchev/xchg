# CLAUDE.md — xchg

Клиент обмена сообщениями между агентами Claude Code через git-хабы. Один bash-скрипт `bin/xchg`;
репозиторий заодно является плагином Claude Code и маркетплейсом для него.
Пользовательская документация — [`docs/`](docs/), внутренняя — [`.claude-docs/`](.claude-docs/index.md).

## Documentation index
- [.claude-docs/index.md](.claude-docs/index.md) — что читать под какую задачу
- [.claude-docs/architecture.md](.claude-docs/architecture.md) — устройство `bin/xchg`, потоки данных
- [.claude-docs/gotchas.md](.claude-docs/gotchas.md) — ловушки bash и git, на которых уже спотыкались
- [docs/hubs.md](docs/hubs.md), [docs/cli.md](docs/cli.md), [docs/agents.md](docs/agents.md), [docs/autonomous.md](docs/autonomous.md) — поведение, обещанное пользователю

## Commands
- `tests/run.sh [-v]` — e2e в песочнице (HOME подменяется, хабы — локальные bare). Обязателен перед коммитом в `bin/xchg`.
- `tests/bash32.sh [-v]` — тот же прогон под bash 3.2 в docker. Обязателен перед коммитом в `bin/xchg`.
- `bash -n bin/xchg` — синтаксис.
- `claude plugin validate .` — манифесты плагина и маркетплейса.
- `XCHG_NO_SELFUPDATE=1 bin/xchg <cmd>` — прогнать клиент из репозитория против настоящих хабов.

## Boundaries
### MUST
- Клиент — чистый bash ≥ 3.2 (системный bash macOS) + git/awk/sed/coreutils: без ассоциативных массивов, пустые массивы разворачивать как `${a[@]+"${a[@]}"}`, перед не-ASCII писать `${var}`. `python3` и `jq` только как необязательные ускорители (есть fallback).
- Изменение поведения — код, тест в `tests/run.sh` и правка соответствующего файла в `docs/` в одном коммите.
- Документация и тесты не привязаны к окружению автора: примеры — `alice`/`bob`, `example.com`, проекты `api`/`web`. Исключение — адрес самого репозитория xchg в инструкциях по установке.
- Документация описывает текущее устройство. Никаких «раньше было», версий и истории решений.
- `README.en.md` — перевод `README.md`; правишь один — правь оба.
- Ошибки на stderr, по-русски, с подсказкой следующей команды; код ≠ 0 (2 — неверный вызов, 3 — `wait` не дождался письма).
- `inbox --brief` при отсутствии нового печатает 0 байт: хуки не должны тратить токены. «Новое» — то, что этому агенту ещё не показывали; всё открытое показывает только `SessionStart`.
### MUST NOT
- Не добавлять реле между хабами, БД, HTTP, MCP, хранение состояния агентов — см. [docs/design.md](docs/design.md).
- Не запускать `bin/xchg install` в реальном HOME при разработке — только в песочнице (`tests/run.sh`).
- Не коммитить `~/.config/xchg/*` и содержимое хабов.

## Workflow
- Ветка `main`, коммиты однострочные.
