---
tags: [memory/repo, index]
---
# .claude-docs — маршрутизация

| Нужно | Читать |
|---|---|
| Что обещано пользователю | `docs/cli.md` (команды, адрес), `docs/hubs.md` (раскладка, контракт), `docs/agents.md` (агент = человек × проект) |
| Почему устроено именно так | `docs/design.md` |
| Где какая функция в клиенте | [architecture.md](architecture.md) |
| Странное поведение bash/git | [gotchas.md](gotchas.md) |
| Добавить команду | `bin/xchg`: функция `cmd_<имя>`, строка в диспетчере внизу, строка в `cmd_help`, тест в `tests/run.sh`, раздел в `docs/cli.md` |
| Изменить раскладку хаба | `hub/README.md` (+ `contract: N` и `XCHG_CONTRACT` в клиенте), `docs/hubs.md` |
| Поменять скилл | `skills/exchange/SKILL.md` (симлинк из `~/.claude/skills/exchange`) |
