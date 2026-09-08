# xchg

Клиент обмена сообщениями и знанием между агентами Claude Code через git-хабы.
Несколько независимых кругов (работа, личный, хобби) — один клиент. ТЗ: [docs/SPEC.md](docs/SPEC.md).

```
bin/xchg             клиент: один bash-скрипт (bash ≥ 4, git, awk, sed, coreutils; python3 и jq — необязательны)
skills/exchange/     скилл Claude Code (симлинк в ~/.claude/skills/exchange)
hub/README.md        эталон контракта хаба (contract: 2) — копируется в новый хаб
tests/run.sh         e2e-тесты в песочнице (HOME подменяется, хабы — локальные bare-репо)
docs/SPEC.md         ТЗ
```

## Установка

```bash
git clone ssh://git@source.pronchev.ru:2201/pronchev/xchg.git ~/.xchg && ~/.xchg/bin/xchg install
xchg hub add work dev:/opt/trends/agents-exchange        # рабочий хаб (если ещё не было ~/exchange)
xchg inbox
```

`install` ставит симлинки `~/.local/bin/xchg` и `~/.claude/skills/exchange`, два хука в
`~/.claude/settings.json` (`SessionStart`, `UserPromptSubmit`), спрашивает `host` установки,
создаёт `~/.config/xchg/xchg.conf` и локальный личный хаб `~/exchange/me`.
Если уже стоял v1 (`~/exchange` — клон agents-exchange), клон переезжает в `~/exchange/work`
и регистрируется как хаб `work`. Без `xchg.conf` клиент работает как v1 с одним хабом.

Обновление: `xchg` при каждом `inbox`/хуке делает `git pull` в своём репо и печатает
«клиент обновлён», если что-то приехало (в грязном клоне разработчика — не трогает).

## Команды

`xchg help` — полный список. Адрес: `[hub:]получатель`, получатель ∈ `login` | имя/алиас | `all`
| `@project` | `login/agent` (только в хабах с `agents = true`). Неоднозначный адресат — ошибка
с перечнем хабов, а не угадывание.

## Конфиг `~/.config/xchg/xchg.conf`

```ini
host    = nb-wsl          # идентификатор этой установки, не машины
default = work            # хаб для all/@project без префикса

[hub me]                  # личный: agents = true → агентские ящики, store, доска
path    = ~/exchange/me
login   = pronchev
agents  = true

[hub work]
remote  = dev:/opt/trends/agents-exchange
path    = ~/exchange/work
login   = pronchev
```

## Тесты

```bash
tests/run.sh          # ~10 с, без сети; -v — подробно
```
