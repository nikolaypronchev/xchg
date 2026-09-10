#!/usr/bin/env bash
# e2e-тесты xchg в песочнице: HOME подменяется, хабы — локальные bare-репозитории.
# Запуск: tests/run.sh [-v]. Имена вымышленные: alice/bob/carol, проекты api и web.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V=0; [ "${1:-}" = -v ] && V=1
SB="${XCHG_TEST_SANDBOX:-$(mktemp -d)}"; mkdir -p "$SB"; [ -n "${XCHG_TEST_SANDBOX:-}" ] || trap 'rm -rf "$SB"' EXIT
export XCHG_NO_SELFUPDATE=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL="$SB/gitconfig"; git config --global init.defaultBranch main; git config --global pull.rebase true
X="$ROOT/bin/xchg"; PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); [ $V = 0 ] || echo "  ok: $1"; return 0; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/      /'; return 0; }
t()    { echo "== $1"; }
assert_contains() { grep -qF -- "$2" <<< "$1" && ok "содержит «$2»" || fail "нет «$2»" "$1"; }
assert_not_contains() { grep -qF -- "$2" <<< "$1" && fail "не должно быть «$2»" "$1" || ok "нет «$2»"; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || fail "$3: «$1» != «$2»"; }
run() { set +e; OUT=$("$@" 2>&1); RC=$?; set -e; }

H="$SB/home"; mkdir -p "$H"; export HOME="$H"
mkdir -p "$SB/repos/api" "$SB/repos/web" "$SB/repos/tool"
for r in api web tool; do git init -q "$SB/repos/$r"; done
in_api() { ( cd "$SB/repos/api" && "$@" ); }
in_web() { ( cd "$SB/repos/web" && "$@" ); }

t "install и создание хаба"
run "$X" install </dev/null; assert_eq "$RC" 0 "install rc"; assert_contains "$OUT" "хук SessionStart добавлен"
run "$X" inbox --brief; assert_eq "$OUT" "" "без хабов хук молчит (0 байт)"
git init -q --bare "$SB/bare-work"
git config --global init.defaultBranch master   # ветка хаба не должна зависеть от локального дефолта
run "$X" hub init work --remote "$SB/bare-work" --login alice; assert_eq "$RC" 0 "hub init"; assert_contains "$OUT" "хаб work создан"
assert_eq "$(git -C "$H/exchange/work" branch --show-current)" main "хаб всегда на ветке main"
git config --global init.defaultBranch main
assert_contains "$(cat "$H/exchange/work/README.md")" "contract: 6"
run "$X" hubs; assert_contains "$OUT" "work*"; assert_contains "$OUT" "alice"

t "манифесты плагина"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json commands/setup.md; do
  [ -f "$ROOT/$f" ] && ok "есть $f" || fail "нет $f"
done
assert_contains "$(cat "$ROOT/hooks/hooks.json")" '${CLAUDE_PLUGIN_ROOT}/bin/xchg'
assert_contains "$(cat "$ROOT/.claude-plugin/marketplace.json")" '"source": "./"'
assert_not_contains "$(cat "$ROOT/.claude-plugin/plugin.json")" '"hooks"'
ok "манифест не ссылается на hooks/hooks.json: он подхватывается сам, ссылка — дубль"
if command -v claude >/dev/null 2>&1; then
  run claude plugin validate "$ROOT"; assert_eq "$RC" 0 "claude plugin validate"
  # validate не ловит ошибки загрузки — проверяем настоящей установкой в отдельный HOME
  PH="$SB/plugin-home"; mkdir -p "$PH"
  run env HOME="$PH" claude plugin marketplace add "$ROOT"; assert_eq "$RC" 0 "маркетплейс добавляется"
  run env HOME="$PH" claude plugin install xchg@xchg -y; assert_eq "$RC" 0 "плагин ставится"
  run env HOME="$PH" claude plugin list; assert_contains "$OUT" "xchg@xchg"; assert_not_contains "$OUT" "failed to load"
else ok "claude CLI нет — валидацию и установку плагина пропускаем"; fi

t "совместимость с bash 3.2 (статически; живой прогон — tests/bash32.sh)"
assert_eq "$(grep -c 'declare -A' "$X" || true)" 0 "нет ассоциативных массивов"
BAD=$(LC_ALL=C awk '/\$[A-Za-z_][A-Za-z0-9_]*[\200-\377]/ {print FNR": "$0}' "$X")
assert_eq "$BAD" "" "за именем переменной сразу нет не-ASCII (под set -u байт уходит в имя)"

t "регистрация: книга контактов и паспорта"
assert_contains "$(cat "$H/exchange/work/contacts.md")" "| alice |"; ok "создатель хаба записан в книгу контактов"
[ -d "$H/exchange/work/people/alice" ] && ok "каталог человека заведён" || fail "нет people/alice"

t "проекты и идентичность агента"
run in_api "$X" projects add api --repo "git@example.com:team/api.git"; assert_eq "$RC" 0 "projects add"
assert_contains "$OUT" "проект заведён: work:projects/api"; assert_contains "$OUT" "агент зарегистрирован: work:@api:alice"
assert_contains "$(cat "$H/exchange/work/projects/api/alice/README.md")" "Человек: alice"
assert_contains "$(cat "$H/exchange/work/projects/api/README.md")" "Репозиторий: git@example.com:team/api.git"
run in_api "$X" projects add api; assert_eq "$RC" 0 "повторный projects add не падает"; assert_contains "$OUT" "уже есть"
run in_web "$X" projects add --repo "git@example.com:team/web.git"; assert_eq "$RC" 0 "projects add без имени, но с флагом"
assert_contains "$OUT" "projects/web"; ok "имя проекта взято из репозитория"
run in_api "$X" agent; assert_eq "$OUT" "work:@api:alice" "агент = человек × проект"
run in_web "$X" agent; assert_eq "$OUT" "work:@web:alice" "в другом репозитории — другой агент"
run bash -c "cd '$SB/repos/tool' && '$X' agent"; assert_contains "$OUT" "не заведён проектом"
run bash -c "cd / && '$X' agent"; assert_eq "$RC" 1 "вне репозитория агента нет"
run in_api "$X" projects; assert_contains "$OUT" "api              здесь"; assert_contains "$OUT" "git@example.com:team/api.git"

t "адрес: порядок частей не важен, все уровни"
printf '| bob | Борис Петров | боря | bob@example.com |\n| carol | Кэрол | | carol@example.com |\n' >> "$H/exchange/work/contacts.md"
mkdir -p "$H/exchange/work/people/bob" "$H/exchange/work/people/carol"
( cd "$H/exchange/work" && git add -A && git commit -qm contacts && git push -q )
run in_api "$X" send @api:bob task1 <<< '# Задача агенту Бориса'; assert_eq "$RC" 0 "@api:bob"
assert_contains "$OUT" "отправлено: work:projects/api/bob/"
run in_api "$X" send bob:@api task2 <<< '# То же место, другой порядок'; assert_contains "$OUT" "work:projects/api/bob/"
ok "user:project и project:user — один адрес"
run in_api "$X" send боря task3 <<< '# Человеку по алиасу'; assert_contains "$OUT" "отправлено: work:people/bob/"
run in_api "$X" send @web task4 <<< '# Всем на проекте web'; assert_contains "$OUT" "отправлено: work:projects/web/"
run in_api "$X" post all news --ref "api/CHANGELOG.md" <<< '# Релиз 2.3'; assert_contains "$OUT" "отправлено: work:all/"
run in_api "$X" send @nope x <<< '# x'; assert_eq "$RC" 1 "нет такого проекта"; assert_contains "$OUT" "xchg projects add nope"
run in_api "$X" send nobody x <<< '# x'; assert_eq "$RC" 1 "нет такого человека"; assert_contains "$OUT" "xchg who"
M=$(ls "$H/exchange/work/projects/api/bob/"*task1.md)
assert_eq "$(sed -n 's/^from: //p' "$M")" "alice/api" "from = человек/проект"
assert_eq "$(sed -n 's/^to: //p' "$M")" "@api:bob" "to = канонический адрес"
assert_eq "$(sed -n 's/^kind: //p' "$M")" "task" "send создаёт задачу"
assert_eq "$(sed -n 's/^kind: //p' "$(ls "$H/exchange/work/all/"*news.md)")" "note" "post создаёт заметку"

t "inbox показывает только адреса этой сессии"
# письма для alice кладём в хаб от имени других
W2="$SB/w2"; git clone -q "$SB/bare-work" "$W2"
mkdir -p "$W2/projects/api/alice" "$W2/projects/web/alice" "$W2/people/alice"
printf -- '---\nfrom: bob/api\nto: @api:alice\nkind: task\ndate: 2026-09-09T10:00:00Z\n---\n# Поправь схему\n' > "$W2/projects/api/alice/20260909-100000_bob_schema.md"
printf -- '---\nfrom: carol/web\nto: @web:alice\nkind: task\ndate: 2026-09-09T10:05:00Z\n---\n# Поправь шапку\n' > "$W2/projects/web/alice/20260909-100500_carol_head.md"
printf -- '---\nfrom: bob/api\nto: alice\nkind: task\ndate: 2026-09-09T10:10:00Z\n---\n# Личная просьба\n' > "$W2/people/alice/20260909-101000_bob_personal.md"
printf -- '---\nfrom: carol/web\nto: @api\nkind: task\ndate: 2026-09-09T10:15:00Z\n---\n# Задача в очередь api\n' > "$W2/projects/api/20260909-101500_carol_queue.md"
printf -- '---\nfrom: carol/web\nto: all\nkind: note\ndate: 2026-09-09T10:20:00Z\nref: web/README.md\n---\n# Пятница короткий день\n' > "$W2/all/20260909-102000_carol_friday.md"
( cd "$W2" && git add -A && git commit -qm msgs && git push -q )
run in_api "$X" inbox
assert_contains "$OUT" "Поправь схему"; assert_contains "$OUT" "Личная просьба"
assert_contains "$OUT" "Задача в очередь api"; assert_contains "$OUT" "Пятница короткий день"
assert_not_contains "$OUT" "Поправь шапку"
assert_contains "$OUT" "в других проектах (xchg inbox --all)"
run in_web "$X" inbox; assert_contains "$OUT" "Поправь шапку"; assert_not_contains "$OUT" "Поправь схему"
run in_api "$X" inbox --all; assert_contains "$OUT" "Поправь шапку"; ok "--all снимает фильтр по проекту"
run in_api "$X" inbox; assert_contains "$OUT" "@api:me"; assert_contains "$OUT" "задача"; assert_contains "$OUT" "заметка"

t "заметки читаются курсором, задачи остаются"
run in_api "$X" seen all; assert_contains "$OUT" "прочитано: work:all"
run in_api "$X" inbox; assert_not_contains "$OUT" "Пятница короткий день"; ok "прочитанная заметка не мозолит глаза"
run in_api "$X" inbox --history; assert_contains "$OUT" "Пятница короткий день"
assert_contains "$(in_api "$X" inbox)" "Задача в очередь api"; ok "задача остаётся видимой"
run in_web "$X" inbox; assert_contains "$OUT" "Пятница короткий день"; ok "курсор у каждого адреса свой, у web заметка ещё не прочитана"

t "claim и done"
Q=$(ls "$H/exchange/work/projects/api/"*queue.md)
run in_api "$X" claim "$Q"; assert_eq "$RC" 0 "claim rc"; assert_contains "$OUT" "взято: work:projects/api/alice/"
[ -f "$H/exchange/work/projects/api/alice/$(basename "$Q")" ] && ok "задача переехала в мой адрес" || fail "claim не переложил"
run in_api "$X" claim "$H/exchange/work/projects/api/alice/$(basename "$Q")"; assert_eq "$RC" 1 "повторный claim"; assert_contains "$OUT" "уже у агента"
# гонку выигрывает тот, кто первым запушил
git -C "$W2" pull -q; printf -- '---\nfrom: carol/web\nto: @api\nkind: task\ndate: 2026-09-09T11:00:00Z\n---\n# Вторая задача\n' > "$W2/projects/api/20260909-110000_carol_second.md"
( cd "$W2" && git add -A && git commit -qm t && git push -q ); "$X" sync >/dev/null
git -C "$W2" mv projects/api/20260909-110000_carol_second.md projects/api/bob/ 2>/dev/null || { mkdir -p "$W2/projects/api/bob"; git -C "$W2" mv projects/api/20260909-110000_carol_second.md projects/api/bob/; }
( cd "$W2" && git commit -qm claim && git push -q )
run in_api "$X" claim "$H/exchange/work/projects/api/20260909-110000_carol_second.md"
assert_eq "$RC" 1 "проигранная гонка"; assert_contains "$OUT" "уже взял bob"
[ -z "$(git -C "$H/exchange/work" status --porcelain)" ] && ok "клон чист после проигрыша" || fail "клон грязный" "$(git -C "$H/exchange/work" status --short)"
D=$(ls "$H/exchange/work/projects/api/alice/"*queue.md)
run in_api "$X" done "$D"; assert_eq "$RC" 0 "done rc"; assert_contains "$OUT" "projects/api/alice/done/"
run in_api "$X" inbox; assert_not_contains "$OUT" "Задача в очередь api"; ok "закрытая задача уходит из inbox"
N=$(ls "$H/exchange/work/all/"*friday.md)
run in_api "$X" done "$N"; assert_eq "$RC" 1 "заметку нельзя закрыть"; assert_contains "$OUT" "xchg seen"
run in_api "$X" claim "$N"; assert_eq "$RC" 1 "заметку нельзя взять"

t "reply и thread"
P=$(ls "$H/exchange/work/people/alice/"*personal.md)
run in_api "$X" reply "$P" ok <<< '# Сделал'; assert_eq "$RC" 0 "reply rc"
assert_contains "$OUT" "отправлено: work:projects/api/bob/"; ok "ответ уходит агенту отправителя, а не человеку"
R=$(ls -t "$H/exchange/work/projects/api/bob/"*ok.md | head -1)
assert_contains "$(cat "$R")" "re: $(basename "$P")"
run in_api "$X" thread "$R"; assert_contains "$OUT" "Личная просьба"; assert_contains "$OUT" "Сделал"; assert_contains "$OUT" "открыто"
run in_api "$X" done "$P" ; run in_api "$X" thread "$R"; assert_contains "$OUT" "закрыто"; ok "закрытая задача читается из истории"
run in_api "$X" sent; assert_contains "$OUT" "projects/api/bob/"; assert_contains "$OUT" "Сделал"

t "wait: ожидание без человека"
git -C "$W2" pull -q
run in_api "$X" inbox; assert_eq "$RC" 0 "inbox перед ожиданием"
run in_api "$X" wait --timeout 2 --interval 1; assert_eq "$RC" 3 "уже показанное не будит"; assert_contains "$OUT" "новых сообщений нет"
( sleep 2; git -C "$W2" pull -q
  printf -- '---\nfrom: bob/api\nto: @api:alice\nkind: task\ndate: 2026-09-10T09:00:00Z\n---\n# Проснись\n' > "$W2/projects/api/alice/20260910-090000_bob_wake.md"
  ( cd "$W2" && git add -A && git commit -qm wake && git push -q ) ) &
BG=$!
run in_api "$X" wait --timeout 30 --interval 1; wait "$BG" 2>/dev/null || true
assert_eq "$RC" 0 "новое письмо будит"; assert_contains "$OUT" "Проснись"; assert_contains "$OUT" "xchg: 1 новое сообщение"
run in_api "$X" wait --timeout 2 --interval 1; assert_eq "$RC" 3 "то же письмо повторно не будит"
run in_api "$X" send @api:alice note-to-self <<< '# Записка себе'
run in_api "$X" wait --timeout 2 --interval 1; assert_eq "$RC" 3 "своё письмо не будит"
git -C "$W2" pull -q
printf -- '---\nfrom: carol/web\nto: @api\nkind: task\ndate: 2026-09-10T09:10:00Z\n---\n# Очередь для claim\n' > "$W2/projects/api/20260910-091000_carol_q2.md"
( cd "$W2" && git add -A && git commit -qm q2 && git push -q )
run in_api "$X" inbox; assert_contains "$OUT" "Очередь для claim"
run in_api "$X" claim "$H/exchange/work/projects/api/20260910-091000_carol_q2.md"; assert_eq "$RC" 0 "claim показанной задачи"
run in_api "$X" wait --timeout 2 --interval 1; assert_eq "$RC" 3 "взятая задача переехала, но повторно не будит"
run in_api "$X" wait --timeout abc; assert_eq "$RC" 2 "неверный таймаут — ошибка вызова"

t "mute и хуки: чужое письмо не будит и не повторяется"
hook() { local ev="$1"; shift; printf '{"session_id":"t","hook_event_name":"%s"}' "$ev" | "$@"; }
git -C "$W2" pull -q
printf -- '---\nfrom: carol/web\nto: alice\nkind: task\ndate: 2026-09-10T10:00:00Z\n---\n# Не для агента api\n' > "$W2/people/alice/20260910-100000_carol_notmine.md"
( cd "$W2" && git add -A && git commit -qm notmine && git push -q )
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_contains "$OUT" "Не для агента api"; ok "новое письмо хук показывает"
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_eq "$OUT" "" "повторный хук на то же молчит (0 байт)"
run in_api hook SessionStart "$X" inbox --brief; assert_contains "$OUT" "xchg: в ящике"; assert_contains "$OUT" "Не для агента api"
ok "старт сессии показывает открытое заново"
NM="$H/exchange/work/people/alice/20260910-100000_carol_notmine.md"
run in_api "$X" mute; assert_eq "$RC" 2 "mute без файла — ошибка вызова"
run in_api "$X" mute "$NM"; assert_eq "$RC" 0 "mute"; assert_contains "$OUT" "заглушено для агента @api"
run in_api "$X" inbox; assert_not_contains "$OUT" "Не для агента api"; ok "в inbox этого агента не видно"
run in_api "$X" inbox --history; assert_contains "$OUT" "Не для агента api"
run in_api hook SessionStart "$X" inbox --brief; assert_not_contains "$OUT" "Не для агента api"; ok "и при старте сессии тоже"
run in_web "$X" inbox; assert_contains "$OUT" "Не для агента api"; ok "другой агент того же человека письмо видит"
[ -f "$NM" ] && ok "в хабе письмо не тронуто" || fail "mute изменил хаб"
git -C "$W2" pull -q
printf -- '---\nfrom: carol/web\nto: @web\nkind: task\ndate: 2026-09-10T10:05:00Z\n---\n# Задача web\n' > "$W2/projects/web/20260910-100500_carol_webtask.md"
( cd "$W2" && git add -A && git commit -qm webtask && git push -q )
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_contains "$OUT" "ещё 1 сообщение в других проектах"
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_not_contains "$OUT" "в других проектах"; ok "счётчик другого проекта не повторяется"
git -C "$W2" pull -q
printf -- '---\nfrom: carol/web\nto: @api\nkind: task\ndate: 2026-09-10T10:10:00Z\n---\n# Сначала заглушу, потом возьму\n' > "$W2/projects/api/20260910-101000_carol_later.md"
( cd "$W2" && git add -A && git commit -qm later && git push -q ); "$X" sync >/dev/null
LT="$H/exchange/work/projects/api/20260910-101000_carol_later.md"
run in_api "$X" mute "$LT"; assert_eq "$RC" 0 "mute задачи из очереди"
run in_api "$X" claim "$LT"; assert_eq "$RC" 0 "claim заглушённой задачи"
run in_api "$X" inbox; assert_contains "$OUT" "Сначала заглушу, потом возьму"; ok "взятая себе задача снова видна"

t "второй хаб: свои агенты между собой"
run "$X" hub init me --login alice; assert_eq "$RC" 0 "личный хаб"
run in_api "$X" projects add api --hub me; assert_eq "$RC" 0 "проект api в личном хабе"
run in_web "$X" projects add web --hub me; assert_eq "$RC" 0 "проект web в личном хабе"
run in_api "$X" send me:@web:alice handoff <<< '# Продолжи миграцию'; assert_eq "$RC" 0 "агент пишет своему же агенту"
assert_contains "$OUT" "отправлено: me:projects/web/alice/"
run in_web "$X" inbox; assert_contains "$OUT" "Продолжи миграцию"; assert_contains "$OUT" "me"
run in_api "$X" inbox; assert_not_contains "$OUT" "Продолжи миграцию"; ok "чужой адрес в этой сессии не показывается"
run in_api "$X" send @api:alice self <<< '# Записка себе'; assert_contains "$OUT" "есть в хабах: work me"
ok "одинаковый адрес в двух хабах — ошибка с перечнем"
run in_api "$X" send me:@api:alice self <<< '# Записка себе'; assert_eq "$RC" 0 "префикс хаба снимает неоднозначность"

t "forward между хабами"
S=$(ls "$H/exchange/work/projects/api/alice/"*schema.md)
run in_api "$X" forward "$S" me:@api:alice --note "перенесу к себе"; assert_eq "$RC" 0 "forward rc"
FW=$(ls -t "$H/exchange/me/projects/api/alice/"*fwd*.md | head -1)
assert_contains "$(cat "$FW")" "forwarded_from: work/projects/api/alice/"; assert_contains "$(cat "$FW")" "перенесу к себе"
[ -e "$S" ] && ok "оригинал не тронут" || fail "оригинал пропал"

t "контакты, секреты, контракт, недоступный хаб"
run "$X" contact --name "Алиса Иванова" --aliases "аля"; assert_contains "$OUT" "| alice | Алиса Иванова | аля |"
run "$X" who аля; assert_contains "$OUT" "work  | alice"
run "$X" who; assert_contains "$OUT" "проекты: api, web"; ok "участие выводится из каталогов агентов"
run in_api "$X" send bob key <<< $'# ключ\nAKIAABCDEFGHIJKLMNOP'; assert_eq "$RC" 0 "секрет не блокирует"; assert_contains "$OUT" "похоже на секрет"
run in_api "$X" post work:@api nofref <<< '# без ссылки'; assert_contains "$OUT" "без --ref"
sed -i 's/^contract: 6/contract: 7/' "$H/exchange/work/README.md"
run in_api "$X" send bob z <<< '# z'; assert_eq "$RC" 1 "чужой контракт — отказ"; assert_contains "$OUT" "контракт 7"
git -C "$H/exchange/work" checkout -q README.md
mv "$SB/bare-work" "$SB/bare-work.off"
run in_api "$X" inbox --brief; assert_eq "$RC" 0 "недоступный хаб не валит inbox"; assert_contains "$OUT" "хаб work недоступен"
run in_api "$X" inbox --brief; assert_not_contains "$OUT" "недоступен"; ok "повтор молчит (раз в час)"
mv "$SB/bare-work.off" "$SB/bare-work"
run "$X" status; assert_contains "$OUT" "контракт 6"
run "$X" hub rm me; assert_eq "$RC" 0 "hub rm"; run "$X" hubs; assert_not_contains "$OUT" "me "

t "имя репозитория вне [a-z0-9._-]"
mkdir -p "$SB/repos/TRENDS-Frontend"; git init -q "$SB/repos/TRENDS-Frontend"
in_tf() { ( cd "$SB/repos/TRENDS-Frontend" && "$@" ); }
run in_tf "$X" agent; assert_contains "$OUT" "xchg projects add trends-frontend"
run in_tf "$X" projects add; assert_eq "$RC" 2 "без имени — отказ с подсказкой"
assert_contains "$OUT" "xchg projects add trends-frontend"; assert_contains "$OUT" "git config xchg.project"
run in_tf "$X" projects add trends-frontend; assert_eq "$RC" 0 "с нормализованным именем"
assert_contains "$OUT" "теперь проект «trends-frontend»"
assert_eq "$(git -C "$SB/repos/TRENDS-Frontend" config xchg.project)" trends-frontend "имя запомнено в репозитории"
run in_tf "$X" agent; assert_eq "$OUT" "work:@trends-frontend:alice" "агент адресуем под новым именем"

t "ошибки конфига"
printf 'default = a\n[hub a]\npath = /tmp/a\nbogus line\n' > "$H/.config/xchg/xchg.conf"
run "$X" hubs; assert_eq "$RC" 1 "плохая строка — ошибка"; assert_contains "$OUT" "xchg.conf:4: не разобрал"
run "$X" help; assert_eq "$RC" 0 "help работает и со сломанным конфигом"

echo; echo "passed: $PASS, failed: $FAIL"; [ "$FAIL" = 0 ]
