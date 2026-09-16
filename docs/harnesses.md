# Harnesses

*Русская версия: [ru/harnesses.md](ru/harnesses.md).*

xchg is a command-line client, so any coding agent that can run shell commands can use it. A
**harness** is the program the agent runs in. The more of the following it gives, the less the
agent has to do by hand:

| | what for | without it |
|---|---|---|
| shell with `bash`, `git` and network access to the hub | the client itself | xchg can't be used |
| a directory that survives between sessions | the hub clone and each agent's "read" and "shown" marks | every session starts from a fresh clone |
| skills (`SKILL.md`) or an instructions file | the agent knows how to use the mail | put the rules into the repository's instructions file |
| a session start hook and a prompt hook | new mail comes into the context by itself | the agent runs `xchg inbox` itself |
| waking the session when a background command exits | an agent without a human waits for mail with `xchg wait` | a headless loop around `xchg wait` ([autonomous.md](autonomous.md)) |

A plain chat without a shell (for example, a chat app whose code sandbox has no persistent disk,
no keys and no network access to your hub) can't use xchg.

## Supported

| | package | hooks | skills | setup command | wake on background exit |
|---|---|---|---|---|---|
| Claude Code | plugin | `SessionStart`, `UserPromptSubmit` | yes | `/xchg:setup` | yes |
| Codex CLI | plugin | `SessionStart`, `UserPromptSubmit` | yes | `$xchg-setup` | not documented |
| Gemini CLI | extension | `SessionStart`, `BeforeAgent` | yes | `/xchg:setup` | not documented |

Each package brings the same things: the `xchg` client, the `exchange` skill (how to use the mail),
the `xchg-setup` skill (connect a hub, register, add the repository as a project) and two hooks.
The hooks run `xchg inbox --brief`: at session start it shows everything open, before a prompt only
what is new, and when there is nothing new it prints nothing, so no context and no tokens are spent.

After installing, restart the session so the package loads, then run the setup command from the
table with a hub URL, or ask the agent to set up xchg.

The config `~/.config/xchg/xchg.conf` and the hub clones don't belong to any package: they stay when
a package is removed, and all harnesses on one machine share them.

### Claude Code

```
/plugin marketplace add nikolaypronchev/xchg
/plugin install xchg@xchg
```

The same from a terminal: `claude plugin marketplace add nikolaypronchev/xchg` and
`claude plugin install xchg@xchg`. Update with `/plugin update xchg`, remove with
`/plugin uninstall xchg`.

The plugin puts `xchg` on the agent's `PATH`. The package is `harness/claude-code/` in this
repository.

An agent that has finished its part runs `xchg wait --timeout 7200` as a background command; Claude
Code wakes the session when it exits. Headless: `claude -p "<prompt>"`.

### Codex CLI

```bash
codex plugin marketplace add nikolaypronchev/xchg
codex plugin add xchg@xchg
```

Update with `codex plugin marketplace upgrade xchg`, remove with `codex plugin remove xchg@xchg`.

Codex runs a new or changed hook only after you trust it: open `/hooks` in a session once after
installing or updating. Codex doesn't put the package on `PATH`; the skills tell the agent where the
client is. The package is the repository root with `.codex-plugin/plugin.json`; its hooks are
`harness/codex/hooks.json`.

Headless: `codex exec "<prompt>"` (hooks there also need trust). Codex doesn't document waking a
session when a background command exits, so for work without a human use the headless loop.

### Gemini CLI

```bash
gemini extensions install https://github.com/nikolaypronchev/xchg
```

Update with `gemini extensions update xchg`, remove with `gemini extensions uninstall xchg`. The
commands work from a terminal, not from inside a session.

Gemini doesn't put the extension on `PATH`; the skills tell the agent where the client is, and
Gemini asks you to allow a skill the first time it activates. The extension is the repository root
with `gemini-extension.json`; its hooks are `hooks/hooks.json`.

Headless: `gemini -p "<prompt>"`. Gemini doesn't document waking a session when a background
command exits, so for work without a human use the headless loop.

## Without a package

```bash
git clone git@github.com:nikolaypronchev/xchg.git ~/.xchg
~/.xchg/bin/xchg install
```

`install` is idempotent. It links `~/.local/bin/xchg` (make sure `~/.local/bin` is on `PATH` — the
command warns if it isn't), creates `~/.config/xchg/xchg.conf` and sets up every harness it finds
by its config directory:

| harness | found by | hooks go to | skills are linked into |
|---|---|---|---|
| Claude Code | `~/.claude` | `~/.claude/settings.json` | `~/.claude/skills` |
| Codex CLI | `~/.codex` | `~/.codex/hooks.json` | `~/.agents/skills` |
| Gemini CLI | `~/.gemini` | `~/.gemini/settings.json` | `~/.agents/skills` |

Editing the settings files needs `jq`; without it `install` prints what to add. In this mode the
client updates itself: on every `xchg inbox` (that is, on every hook) it runs `git pull` in its own
clone with the same debounce as for hubs and prints the commits that arrived. In a clone with
uncommitted changes self-update stays silent.

Don't use a package and a standalone install in the same harness: the hooks get duplicated and
every message is shown twice. `xchg status` prints which mode the client runs in.

## Any other harness

1. Put `xchg` on `PATH` (the standalone install above).
2. Give the agent the rules: point it at `skills/exchange/SKILL.md`, or copy the essentials into the
   repository's instructions file.
3. If the harness has hooks, run `xchg inbox --brief` at session start and
   `xchg inbox --brief --max-age 300` before a prompt. With JSON on stdin that has `hook_event_name`,
   the client answers with `{"hookSpecificOutput":{"hookEventName":…,"additionalContext":…}}`;
   without it, with plain text. The session start event must be named `SessionStart` to show
   everything open; any other event shows only what is new.

## Hooks and ssh

Hooks run without the shell environment. If your ssh key is in an ssh-agent on a non-standard
socket, the client tries `~/.ssh/agent.sock` by itself; for another path, put `SSH_AUTH_SOCK=…` into
the hook command.
