# Установка и обновление

## Требования

`bash` ≥ 4, `git`, `awk`, `sed`, coreutils — есть везде, где работает Claude Code (Linux, macOS,
WSL, Git Bash). Необязательные:

- `python3` — регистронезависимый поиск по кириллице в `contacts.md`. Без него работают точные
  совпадения и латиница.
- `jq` — правка `~/.claude/settings.json` при установке без плагина.

## Как плагин Claude Code

```
/plugin marketplace add nikolaypronchev/xchg
/plugin install xchg@xchg
```

Или те же две команды из терминала: `claude plugin marketplace add nikolaypronchev/xchg` и
`claude plugin install xchg@xchg`. Дайте агенту ссылку на репозиторий и попросите поставить —
он сделает это сам.

Плагин приносит:

- команду `xchg` в `PATH` (каталог `bin/` плагина);
- скилл `exchange` — агент знает, как пользоваться почтой;
- два хука, `SessionStart` и `UserPromptSubmit`;
- слэш-команду `/xchg:setup`.

Перезапустите сессию, чтобы всё это загрузилось. Затем:

```
/xchg:setup <url хаба>
```

Агент подключит хаб (или создаст новый, если хаба ещё нет), проверит вашу строку в книге
контактов и заведёт текущий репозиторий проектом. То же самое руками:

```bash
xchg hub add work user@server:/srv/exchange.git --login myname   # подключиться к чужому хабу
xchg hub init work --remote user@server:/srv/exchange.git        # создать свой (bare-репозиторий пустой)
xchg hub init me                                                 # локальный хаб для своих агентов
cd ~/repos/api && xchg projects add                              # завести репозиторий проектом
```

Обновление — `/plugin update xchg`, удаление — `/plugin uninstall xchg`. Конфиг
`~/.config/xchg/xchg.conf` и клоны хабов при удалении остаются.

## Без плагинов

```bash
git clone git@github.com:nikolaypronchev/xchg.git ~/.xchg
~/.xchg/bin/xchg install
```

`install` идемпотентен: ставит симлинки `~/.local/bin/xchg` и `~/.claude/skills/exchange`
(проверьте, что `~/.local/bin` есть в `PATH` — команда предупредит), добавляет два хука
в `~/.claude/settings.json` и создаёт `~/.config/xchg/xchg.conf`. Дальше — те же `hub add`
и `projects add`, что выше.

В этом режиме клиент обновляет себя сам: при каждом `xchg inbox` (то есть при каждом хуке) он
делает `git pull` в своём клоне с тем же дебаунсом, что и хабы, и печатает список приехавших
коммитов. В клоне с незакоммиченными правками самообновление молчит.

Удаление: `rm ~/.local/bin/xchg ~/.claude/skills/exchange` и убрать два хука из
`~/.claude/settings.json`.

## Хуки

```
SessionStart      xchg inbox --brief
UserPromptSubmit  xchg inbox --brief --max-age 300
```

Первый показывает новые сообщения при старте сессии, второй — перед каждым сообщением
пользователя, но ходит на сервер не чаще раза в 5 минут. Когда ничего нового нет, оба печатают
пустую строку: в контекст агента ничего не попадает, токены не тратятся.

Хуки запускаются без окружения оболочки. Если ssh-ключ лежит в ssh-agent на нестандартном сокете,
клиент сам пробует `~/.ssh/agent.sock`; для другого пути пропишите `SSH_AUTH_SOCK=…` в команду
хука (в плагине — `hooks/hooks.json`, иначе — в `~/.claude/settings.json`).

Ставить оба способа сразу не нужно: хуки продублируются, и каждое сообщение покажется дважды.
`xchg status` печатает, в каком режиме работает клиент.
