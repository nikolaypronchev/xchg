---
tags: [memory/repo, architecture]
---
# Устройство `bin/xchg`

Один файл, секции сверху вниз:

1. **Утилиты** — `die/udie/warn`, `meta` (поле frontmatter), `title`, `body_of`, `plural`, `rel_time`.
2. **Конфиг** — `parse_conf` (awk печатает `G/H/S/E` строки с TAB, bash раскладывает в `HUBS[]`, `HUB_PATH/REMOTE/LOGIN`), `load_conf`, правки `conf_set_global/conf_set_hub/conf_rm_hub/conf_add_hub` (awk → tmp → mv), `ensure_conf`, `check_contract`.
3. **Синхронизация** — `hub_sync` (pull одного хаба; стампы в `.git/xchg-last-sync`, `.git/xchg-unavail`), `sync_hubs` (параллельно, дедлайн 20 с), `self_update`, `hub_push` (commit + pull --rebase + push ×3).
4. **Люди и проекты** — `resolve_user` (people/ → contacts.md, python3 casefold или awk), `has_project`, `user_projects` (участие выводится из каталогов агентов), `register_me` и `agent_passport` (авторегистрация при `hub add/init` и `projects add`).
5. **Адреса** — `parse_addr` → `A_HUB/A_REL/A_LABEL` (части в любом порядке, хаб выводится из содержимого), `addr_label` (обратно в короткую метку), `locate` (файл по `хаб:путь`, абсолютному пути или единственному совпадению).
6. **Агент** — `cur_project` (basename главного репозитория или `git config xchg.project`), `sender_id` (`user/project`), `my_addrs` (адреса сессии), `other_addrs` (мои адреса в других проектах), `cmd_agent`.
7. **Сообщения** — `msg_files` (без карточек и подкаталогов), `kind_of`, `cursor_file`/`is_read`/`mark_read` (курсор на пару агент+адрес, лежит в `.git/xchg-read/`), `list_addr`, `count_addr`, `write_msg`, `warn_secrets`.
8. **Команды** — `cmd_inbox` (+`others_note`, `unsent_warn`), `cmd_read`, `cmd_seen`, `cmd_sent`, `cmd_thread` (+`hist_find`/`msg_field`/`msg_title` — чтение закрытых задач из истории), `send_common`/`cmd_send`/`cmd_post`, `cmd_reply`, `cmd_claim` (+`claim_owner`), `cmd_done`, `cmd_forward`, `cmd_who`, `cmd_contact`, `cmd_projects`/`cmd_project_add`, `cmd_hubs`/`cmd_hub`/`init_hub_repo`, `cmd_log`, `cmd_sync`, `cmd_install`, `cmd_status`, `cmd_help`.
9. **Диспетчер** — `help`/`version` обрабатываются до чтения конфига.

## Потоки

- **Хук** `xchg inbox --brief [--max-age 300]`: `sync_hubs` → для каждого хаба `my_addrs` → `list_addr` → счётчик других проектов и неотправленного. Нечего показать → 0 байт.
- **send/post**: `sync_hubs` всех (нужны свежие contacts и projects) → `parse_addr` → `check_contract` → `write_msg` → `hub_push` → своё сообщение сразу помечается прочитанным.
- **claim**: sync → проверка, что задача ещё на месте и это задача → `git mv` в `projects/<p>/<me>/` → push; при проигрыше гонки локальный коммит откатывается (`reset --hard @{u}`, только если он единственный) и печатается, кто успел.
- **done**: `git mv` в `<адрес>/done/`.

## Плагин Claude Code

Репозиторий сам себе маркетплейс и плагин: `.claude-plugin/marketplace.json` (запись с `source: "./"`),
`.claude-plugin/plugin.json`, `hooks/hooks.json` (хуки зовут `"${CLAUDE_PLUGIN_ROOT}/bin/xchg"`),
`commands/setup.md` (`/xchg:setup`). Каталог `bin/` плагина Claude Code сам добавляет в PATH,
`skills/exchange` подхватывается автоматически.

Клиент понимает, что запущен из плагина (`PLUGIN_MODE`: `$XCHG_ROOT` внутри `~/.claude/plugins/`), и тогда
не делает самообновление (этим занимается `/plugin update`), а `install` только создаёт конфиг:
симлинки и хуки — дело плагина. `cmd_version` в установленном плагине берёт версию из манифеста,
потому что git-клона там нет.

## Состояние на диске

- `~/.config/xchg/xchg.conf` — реестр хабов (не в git).
- `<клон>/.git/xchg-last-sync`, `xchg-unavail` — стампы синхронизации и недоступности.
- `<клон>/.git/xchg-read/<проект>--<адрес>` — прочитанные заметки: список имён файлов, свой у каждого агента.
- `git config xchg.project` в клоне рабочего репозитория — имя проекта, если клон назван иначе.
