---
tags: [memory/repo, index]
---
# .claude-docs — маршрутизация

| Нужно | Читать |
|---|---|
| Понять, как должно работать | `docs/SPEC.md` (ТЗ, разделы 4–5, 11 — приёмка) |
| Устройство скрипта, где какая функция | [architecture.md](architecture.md) |
| Странное поведение bash/git, «почему так написано» | [gotchas.md](gotchas.md) |
| Добавить команду | `bin/xchg`: функция `cmd_<name>`, строка в диспетчере внизу, строка в `cmd_help`, тест в `tests/run.sh`, пункт в SPEC §5 |
| Изменить контракт хаба | `hub/README.md` (+ `contract: N` и `XCHG_CONTRACT` в клиенте), SPEC §4.2 |
| Поменять скилл | `skills/exchange/SKILL.md` (симлинк из `~/.claude/skills/exchange`) |
