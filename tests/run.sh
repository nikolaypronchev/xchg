#!/usr/bin/env bash
# e2e-тесты xchg в песочнице: HOME подменяется, хабы — локальные bare-репо. Запуск: tests/run.sh [-v]
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

mk_hub() {  # <bare path> <login...>: bare-хаб по эталону
  local bare="$1"; shift; local w="$SB/tmp-$(basename "$bare")"
  git init -q --bare "$bare"; git clone -q "$bare" "$w" 2>/dev/null
  cp "$ROOT/hub/README.md" "$w/"; { echo "# Контакты"; echo; echo "| login | имя | алиасы | проекты | контакт |"; echo "|---|---|---|---|---|"; } > "$w/contacts.md"
  for l in "$@"; do mkdir -p "$w/people/$l/inbox"; touch "$w/people/$l/inbox/.gitkeep"; done
  mkdir -p "$w/people/all/inbox" "$w/projects/demo/inbox"; touch "$w/people/all/inbox/.gitkeep" "$w/projects/demo/inbox/.gitkeep"
  git -C "$w" add -A; git -C "$w" commit -q -m init; git -C "$w" push -q; rm -rf "$w"
}
# --- два хаба: work (pronchev, atanova=оля) и hobby (kolya, olya=оля)
mk_hub "$SB/bare-work" pronchev atanova ostrovskiy
mk_hub "$SB/bare-hobby" kolya olya vasya
H1="$SB/home1"; mkdir -p "$H1"; export HOME="$H1"
git clone -q "$SB/bare-work" "$H1/exchange"
printf '| pronchev | Николай Прончев | коля, николай | trends | |\n| atanova | Ольга Атанова | оля, ольга | trends | |\n| ostrovskiy | Иван | | trends | |\n' >> "$H1/exchange/contacts.md"
git -C "$H1/exchange" commit -qam contacts; git -C "$H1/exchange" push -q
git -C "$H1/exchange" config xchg.me pronchev

t "v1-режим без xchg.conf"
run "$X" inbox; assert_eq "$RC" 0 "inbox rc"; assert_contains "$OUT" "inbox пуст"
run "$X" send оля hello --project trends <<< $'# Привет\nтело'; assert_eq "$RC" 0 "send rc"; assert_contains "$OUT" "отправлено: work:people/atanova/inbox/"
F1=$(ls "$H1/exchange/people/atanova/inbox/"*.md); assert_eq "$(sed -n 's/^from: //p' "$F1")" pronchev "from = login"
run "$X" inbox --brief; assert_eq "$OUT" "" "brief пуст для чужого ящика (0 байт)"

t "install: миграция ~/exchange → ~/exchange/work, conf, host, личный хаб"
run "$X" install </dev/null; assert_eq "$RC" 0 "install rc"; assert_contains "$OUT" "перенесён"; assert_contains "$OUT" "личный хаб me создан"
[ -d "$H1/exchange/work/.git" ] && ok "work в ~/exchange/work" || fail "нет ~/exchange/work"
[ -d "$H1/exchange/me/.git" ] && ok "me создан" || fail "нет ~/exchange/me"
assert_contains "$(cat "$H1/.config/xchg/xchg.conf")" "[hub work]"
"$X" host set nb-wsl >/dev/null; assert_eq "$("$X" host)" nb-wsl "host set/get"
assert_contains "$(jq -r '.hooks.SessionStart[].hooks[].command' "$H1/.claude/settings.json")" "xchg inbox --brief"
run "$X" install </dev/null; assert_contains "$OUT" "хук SessionStart уже есть"
run "$X" hub add hobby "$SB/bare-hobby" --login kolya; assert_eq "$RC" 0 "hub add rc"
printf '| kolya | Коля | николай | | |\n| olya | Оля | оля | | |\n| vasya | Вася | | | |\n' >> "$H1/exchange/hobby/contacts.md"
git -C "$H1/exchange/hobby" commit -qam contacts; git -C "$H1/exchange/hobby" push -q
run "$X" hubs; assert_contains "$OUT" "work*"; assert_contains "$OUT" "hobby"; assert_contains "$OUT" "me"

t "адресация по нескольким хабам"
run "$X" send оля x <<< "# x"; assert_eq "$RC" 1 "неоднозначный «оля» — ошибка"; assert_contains "$OUT" "есть в хабах: work:atanova hobby:olya"
run "$X" send hobby:оля hi <<< "# hi hobby"; assert_eq "$RC" 0 "hobby:оля"; assert_contains "$OUT" "отправлено: hobby:people/olya/inbox/"
run "$X" send вася hi <<< "# hi vasya"; assert_eq "$RC" 0 "уникальный «вася» → hobby"; assert_contains "$OUT" "hobby:people/vasya"
run "$X" send @demo task <<< "# task"; assert_eq "$RC" 0 "@demo → default (work)"; assert_contains "$OUT" "work:projects/demo/inbox"
run "$X" send hobby:@demo task2 <<< "# task2"; assert_contains "$OUT" "hobby:projects/demo/inbox"
run "$X" send nobody x <<< "# x"; assert_eq "$RC" 1 "неизвестный адресат"; assert_contains "$OUT" "xchg who"
run "$X" send work:atanova/agent1 x <<< "# x"; assert_eq "$RC" 1 "login/agent в общем хабе"; assert_contains "$OUT" "агентские ящики выключены"
run "$X" who оля; assert_contains "$OUT" "work  | atanova"; assert_contains "$OUT" "hobby  | olya"

t "inbox по хабам, read, done"
# письмо себе в work и в hobby (от чужого имени — прямо в bare)
W2="$SB/w2"; git clone -q "$SB/bare-work" "$W2"; printf -- '---\nfrom: atanova\nto: pronchev\ndate: 2026-09-08T10:00:00Z\n---\n# Вопрос по nav\nтекст\n' > "$W2/people/pronchev/inbox/20260908-100000_atanova_nav.md"
git -C "$W2" add -A; git -C "$W2" commit -qm m; git -C "$W2" push -q
run "$X" inbox; assert_contains "$OUT" "work     me        people/pronchev/inbox/20260908-100000_atanova_nav.md"; assert_contains "$OUT" "Вопрос по nav"
assert_contains "$OUT" "hobby    @demo"; assert_contains "$OUT" "work     @demo"
run "$X" inbox --brief; assert_contains "$OUT" "xchg: 3 новых сообщений"
run "$X" inbox --hub hobby; assert_not_contains "$OUT" "work "
run "$X" read people/pronchev/inbox/20260908-100000_atanova_nav.md; assert_contains "$OUT" "from: atanova"
run "$X" read projects/demo/inbox; assert_eq "$RC" 1 "неоднозначный путь"; assert_contains "$OUT" "есть в хабах"
run "$X" done "$H1/exchange/work/people/pronchev/inbox/20260908-100000_atanova_nav.md"; assert_eq "$RC" 0 "done по абсолютному пути"
[ -e "$W2/people/pronchev/inbox/20260908-100000_atanova_nav.md" ] && { git -C "$W2" pull -q; [ -e "$W2/people/pronchev/inbox/20260908-100000_atanova_nav.md" ] && fail "done не долетел до origin" || ok "done запушен"; }

t "forward между хабами"
SRC=$(ls "$H1/exchange/work/projects/demo/inbox/"*.md | head -1)
run "$X" forward "$SRC" hobby:вася --note "перекинь, пожалуйста"; assert_eq "$RC" 0 "forward rc"; assert_contains "$OUT" "переслано: hobby:people/vasya/inbox/"
FW=$(ls -t "$H1/exchange/hobby/people/vasya/inbox/"*fwd*.md | head -1)
assert_contains "$(cat "$FW")" "forwarded_from: work/projects/demo/inbox/"; assert_contains "$(cat "$FW")" "перекинь"; assert_contains "$(cat "$FW")" "# task"
assert_eq "$(sed -n 's/^from: //p' "$FW")" kolya "from = login хаба назначения"
[ -e "$SRC" ] && ok "оригинал не тронут" || fail "оригинал пропал"

t "секреты и контракт"
run "$X" send hobby:вася key <<< $'# key\nAKIAABCDEFGHIJKLMNOP'; assert_eq "$RC" 0 "секрет не блокирует"; assert_contains "$OUT" "похоже на секрет"
sed -i 's/^contract: 2/contract: 3/' "$H1/exchange/hobby/README.md"
run "$X" send hobby:вася z <<< "# z"; assert_eq "$RC" 1 "контракт новее — отказ"; assert_contains "$OUT" "контракт 3"
git -C "$H1/exchange/hobby" checkout -q README.md

t "идентичность агента"
mkdir -p "$SB/repos"; git init -q "$SB/repos/trends"; git -C "$SB/repos/trends" remote add origin ssh://git@example.com:2201/team/trends.git
git init -q "$SB/repos/other/trends"; git -C "$SB/repos/other/trends" remote add origin git@github.com:someone/trends.git
run bash -c "cd '$SB/repos/trends' && '$X' agent"; assert_eq "$OUT" "pronchev/trends" "login/agent из репо"
assert_contains "$(cat "$H1/.config/xchg/agents.conf")" "trends = example.com:2201/team/trends"
run bash -c "cd '$SB/repos/other/trends' && '$X' agent"; assert_eq "$RC" 3 "коллизия → код 3"; assert_contains "$OUT" "xchg agent set"
run bash -c "cd '$SB/repos/other/trends' && '$X' agent set trends-gh && '$X' agent"; assert_contains "$OUT" "pronchev/trends-gh"
git -C "$SB/repos/trends" worktree add -q "$SB/repos/trends-wt" -b wt 2>/dev/null || { git -C "$SB/repos/trends" commit -q --allow-empty -m i; git -C "$SB/repos/trends" worktree add -q "$SB/repos/trends-wt" -b wt; }
run bash -c "cd '$SB/repos/trends-wt' && '$X' agent"; assert_eq "$OUT" "pronchev/trends" "worktree → тот же агент"
run bash -c "cd / && '$X' agent"; assert_eq "$OUT" "pronchev/shell" "вне git → shell"
run bash -c "cd / && XCHG_AGENT=custom '$X' agent"; assert_eq "$OUT" "pronchev/custom" "XCHG_AGENT"

t "store: два host без конфликтов, доска"
export XCHG_AGENT=trends   # store/board вызываются из cwd тестов, а не из репо
git init -q --bare "$SB/bare-me"; run "$X" hub remote me "$SB/bare-me"; assert_eq "$RC" 0 "hub remote me"
M1="$SB/mem1"; mkdir -p "$M1"; printf -- '---\nlast_updated: %s\n---\n# Goal\nСделать matcher\n\n# State\n- branch: main\n- last action: написал парсер\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$M1/SESSION.nb-wsl.md"
run bash -c "cd '$SB/repos/trends' && '$X' store push '$M1' --as memory"; assert_eq "$RC" 0 "store push host1"; assert_contains "$OUT" "store: $M1 → me:agents/pronchev/trends/memory"
[ -f "$H1/exchange/me/agents/pronchev/trends/memory/SESSION.nb-wsl.md" ] && ok "файл в хабе" || fail "файла нет в хабе"
# второй host — другая установка (HOME2), тот же bare
H2="$SB/home2"; mkdir -p "$H2/.config/xchg"; git clone -q "$SB/bare-me" "$H2/exchange/me"
printf 'host = desk-win\ndefault = me\n[hub me]\nremote = %s\npath = ~/exchange/me\nlogin = pronchev\nagents = true\n' "$SB/bare-me" > "$H2/.config/xchg/xchg.conf"
M2="$SB/mem2"; mkdir -p "$M2"
run bash -c "cd '$SB/repos/trends' && HOME='$H2' '$X' store pull '$M2' --as memory"; assert_eq "$RC" 0 "store pull host2"
[ -f "$M2/SESSION.nb-wsl.md" ] && ok "host2 видит SESSION.nb-wsl.md" || fail "pull не принёс файл host1"
printf -- '---\nlast_updated: %s\n---\n# Goal\nСделать matcher (с desk-win)\n\n# State\n- last action: тесты\n' "$(date -u -d '+5 sec' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)" > "$M2/SESSION.desk-win.md"
# параллельные push обоих host: оба должны пройти без конфликта
printf -- '---\nlast_updated: %s\n---\n# Goal\nСделать matcher\n\n# State\n- last action: правка 2\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$M1/SESSION.nb-wsl.md"
( cd "$SB/repos/trends" && "$X" store push "$M1" --as memory >/dev/null 2>&1; echo $? > "$SB/rc1" ) &
( cd "$SB/repos/trends" && HOME="$H2" "$X" store push "$M2" --as memory >/dev/null 2>&1; echo $? > "$SB/rc2" ) &
wait; assert_eq "$(cat "$SB/rc1")$(cat "$SB/rc2")" "00" "параллельные push обоих host прошли"
CHK="$SB/chk"; git clone -q "$SB/bare-me" "$CHK"; assert_eq "$(ls "$CHK/agents/pronchev/trends/memory/" | sort | tr '\n' ' ')" "SESSION.desk-win.md SESSION.nb-wsl.md " "оба файла в origin"
run "$X" store pull "$M1" --as memory; [ -f "$M1/SESSION.desk-win.md" ] && ok "host1 получил файл host2" || fail "host1 без файла host2"
run bash -c "cd '$SB/repos/trends' && '$X' board"; assert_eq "$RC" 0 "board rc"; assert_contains "$OUT" "desk-win"; assert_contains "$OUT" "активен"; assert_contains "$OUT" "Сделать matcher (с desk-win)"
run "$X" hosts; assert_contains "$OUT" "nb-wsl"; assert_contains "$OUT" "desk-win"; assert_contains "$OUT" "(этот)"
run "$X" host set desk-win; assert_eq "$RC" 1 "занятый host не даёт выбрать"
run "$X" inbox --brief; assert_contains "$OUT" "доска (me):"; assert_contains "$OUT" "trends@desk-win"
run "$X" inbox --brief; assert_not_contains "$OUT" "доска"; ok "доска не повторяется без изменений"
# общий файл без тега → отказ; с --force-shared и конфликт → .conflict.<host>
echo a > "$M1/notes.md"; echo b > "$M1/notes.desk-win.md"
run "$X" store push "$M1" --as memory; assert_eq "$RC" 1 "общий файл рядом с файлом другого host — отказ"; assert_contains "$OUT" "notes.md ↔ notes.desk-win.md"
rm "$M1/notes.desk-win.md"; echo "v1" > "$M1/shared.md"; run "$X" store push "$M1" --as memory --force-shared; assert_eq "$RC" 0 "force-shared"
run bash -c "HOME='$H2' '$X' store pull '$M2' --as memory"; echo "host1" > "$M1/shared.md"; echo "host2" > "$M2/shared.md"
run "$X" store push "$M1" --as memory --force-shared; assert_eq "$RC" 0 "push host1"
run bash -c "HOME='$H2' '$X' store push '$M2' --as memory --force-shared"; assert_eq "$RC" 0 "push host2 при конфликте не падает"; assert_contains "$OUT" "конфликт в agents/pronchev/trends/memory/shared.md"
[ -f "$H2/exchange/me/agents/pronchev/trends/memory/shared.md.conflict.desk-win" ] && ok ".conflict.desk-win сохранён" || fail "нет .conflict файла" "$(ls "$H2/exchange/me/agents/pronchev/trends/memory/")"
assert_eq "$(cat "$M2/shared.md")" host1 "чужая версия принята локально"
[ -z "$(git -C "$H2/exchange/me" status --porcelain)" ] && ok "клон host2 чист" || fail "клон host2 грязный" "$(git -C "$H2/exchange/me" status --short)"
run "$X" host rename nb-wsl nb-linux; assert_eq "$RC" 0 "host rename"; assert_eq "$("$X" host)" nb-linux "conf обновлён"
[ -f "$H1/exchange/me/agents/pronchev/trends/memory/SESSION.nb-linux.md" ] && ok "файл переименован" || fail "файл не переименован"

t "недоступный хаб"
mv "$SB/bare-hobby" "$SB/bare-hobby.off"
run "$X" inbox --brief; assert_eq "$RC" 0 "rc 0"; assert_contains "$OUT" "хаб hobby недоступен"
run "$X" inbox --brief; assert_not_contains "$OUT" "недоступен"; ok "повтор молчит (раз в час)"
mv "$SB/bare-hobby.off" "$SB/bare-hobby"
run "$X" status; assert_eq "$RC" 0 "status"; assert_contains "$OUT" "host: nb-linux"
sed -i '/^contract: 2/d' "$H1/exchange/work/README.md"   # хаб v1 без contract: — режим совместимости
run "$X" send work:оля compat <<< "# compat"; assert_eq "$RC" 0 "хаб без contract: пишется как v1"; git -C "$H1/exchange/work" checkout -q README.md
run "$X" hub rm hobby; assert_eq "$RC" 0 "hub rm"; run "$X" hubs; assert_not_contains "$OUT" "hobby"

t "ошибки конфига"
printf 'host = x\n[hub a]\npath = /tmp/a\nbogus line\n' > "$H1/.config/xchg/xchg.conf"; run "$X" hubs; assert_eq "$RC" 1 "плохая строка — ошибка"; assert_contains "$OUT" "xchg.conf:4: не разобрал"

echo; echo "passed: $PASS, failed: $FAIL"; [ "$FAIL" = 0 ]
