# claude-account-router

Use a different Claude Code account per folder, in the VS Code extension, without logging in and out.

Open a folder, click the Claude icon, work. Folders you declare as work use the work account. Everything else uses your personal account. Both sessions stay logged in at the same time.

If the account does not match the folder, Claude does not start. That is the point: an indicator you can trust, because a running panel proves the account is the expected one.

## The problem

The Claude Code CLI supports several accounts through `CLAUDE_CONFIG_DIR`. The VS Code extension has no account picker and no per-workspace setting: it uses whatever account you logged in with last. Switching means logout, login, and remembering which account you are on ([anthropics/claude-code#55621](https://github.com/anthropics/claude-code/issues/55621)).

Workarounds exist for switching by hand. This project routes automatically, by folder, and verifies the result.

## How it works

The extension exposes a setting called `claudeCode.claudeProcessWrapper`: an executable it runs instead of the Claude binary. This project installs a small wrapper there. On every launch the wrapper:

1. Reads the folder the editor opened.
2. Finds the profile that owns it, by path or by git repository, so worktrees route with their repo wherever they live on disk.
3. Reads the email of the account currently logged into that profile.
4. Blocks the launch if the account does not match what the profile declares, in either direction.
5. Sets `CLAUDE_CONFIG_DIR` and execs the real Claude process.

Step 4 is what makes the rest trustworthy. Nothing falls back to another account quietly.

## Install

```bash
git clone https://github.com/kirlts/claude-account-router.git
cd claude-account-router
./install.sh
```

Requires bash, git, python3, and `~/.local/bin` on your PATH.

Then point the editor at the router, in VS Code **user** settings (JSON):

```json
"claudeCode.claudeProcessWrapper": "/home/YOU/.local/bin/claude-account-router"
```

This setting has `machine` scope, so a workspace `.vscode/settings.json` cannot hold it. One global setting plus one config file is why routing is decided by the wrapper rather than by per-project settings.

## Configure

`~/.config/claude-account-router/routes.conf`:

```
profile default ~/.claude
profile work    ~/.claude-work  *@example.com

route ~/code/work-project  work
route ~/code/work-notes    work
```

| Directive | Meaning |
|---|---|
| `profile <name> <config-dir> [email-glob] [color]` | An account. `config-dir` is what Claude Code reads through `CLAUDE_CONFIG_DIR`. The optional glob is the account allowed to live there. The optional hex color is used by `claude-account mark`. Fields are positional, so a color needs a glob before it. |
| `route <path> <profile>` | That path and everything under it uses the profile: every subfolder, at any depth, and paths reached through a symlink. Every git worktree of the same repository routes the same way, wherever it lives. |

One route per repository is enough. Opening `~/code/work-project/src/deep/folder` uses the work account without declaring anything else.

**Order matters: the first matching route wins.** To carve an exception out of a broader route, put the narrower path above it:

```
route ~/code/work-project/scratch  default    # exception, must come first
route ~/code/work-project          work
```

A route on a subfolder routes that subfolder and everything under it, and deliberately does not claim its repository's identity, so the repository's own worktrees keep following the repository's route.

Keep the `default` profile at `~/.claude`. Claude Code runs with the variable unset there, and the router preserves that, because the keychain service name is derived from the config dir and exporting it would strand your existing session.

Folders no route claims use `default`.

## Log in

```bash
claude-account login work        # opens Claude, type /login
claude-account                   # which account is in each profile
```

Or leave the profile empty and open that folder in the editor: the panel asks for a login and the session lands in the right place.

## Verify

```bash
claude-account-check
```

It checks effective state, not the presence of files: it runs the router for every declared route, reads the real account identity of every profile, and reports whether the editor has actually gone through the router. A setup that only looks installed fails here.

```
1. Editor wiring
  PASS router present and executable
  PASS claudeCode.claudeProcessWrapper points at the router (Code)
3. Routing (running the router for real)
  PASS /home/you/code/work-project -> profile 'work'
  PASS /home/you -> profile 'default'
4. Account identity
  PASS profile 'default': me@personal.example
  PASS profile 'work': me@example.com
```

Run it after every extension update. See "Known limits" for why.

## Mark the window

The router decides the account. It cannot color the editor. To see at a glance which account a window is on:

```bash
claude-account mark          # marks the current folder
claude-account mark <dir>    # marks another folder
claude-account unmark        # removes it
```

It colors the title bar with the profile's color and puts the profile name in the window title. It merges into an existing `.vscode/settings.json` instead of overwriting it, refuses to touch a file it cannot parse, and adds `.vscode/` to `.git/info/exclude` so a shared repository stays clean. `unmark` removes only the keys it added. Text colors are derived from the profile color, so a light color gets dark text and a dark one gets light text.

**The marker tracks the account, not a snapshot of the folder.** On every launch the router recomputes an existing marker against the profile it just resolved, and removes it when the folder now resolves to the default profile. So a marker cannot survive a routing change and keep claiming the old account: add a narrower route today and the color follows tomorrow, with no command to remember. Because the router only gets that far after the identity check passed, the profile it resolved and the live account are the same thing.

It only touches files carrying its own signature, a `window.title` starting with `[` plus its color keys. A title bar you customized by hand is never rewritten, and never synced either.

**Markers do not inherit; routing does.** VS Code reads `.vscode/settings.json` from the folder you opened and never from a parent, so opening a subfolder of a marked repository gives you the right account with no color. That is a display gap, not a routing gap: run `claude-account mark` in the subfolders you open often. If a folder is routed but unmarked and you want to be sure, `claude-account` prints the accounts and `claude-account routes` prints where folders go.

On Linux you may also need `"window.titleBarStyle": "custom"` for the color to apply.

Be precise about what this marker claims. A settings file cannot observe a session, so the color is not a live readout. What makes it trustworthy is the pair of mechanisms behind it: the router refuses to launch on a mismatched account, and it rewrites the marker to the profile it just resolved. So the color is never older than the last launch, and a launch never happens on the wrong account. Between those two, the window you are looking at is showing the account it is using.

The gap that remains: a folder whose routing changed and that you have not opened since. Its marker is still describing the previous profile, and will correct itself the moment Claude starts there. `claude-account` reads the accounts directly if you want to know without opening anything.

## Commands

| Command | What it does |
|---|---|
| `claude-account` | Which account is in each profile |
| `claude-account routes` | Which folders route where |
| `claude-account check` | Full verification |
| `claude-account login <profile>` | Start a session in one profile |
| `claude-account logout <profile>` | End a session, keeping a timestamped backup |
| `claude-account mark [dir]` | Color a folder's title bar for its profile |
| `claude-account unmark [dir]` | Remove that marker |
| `claude-account-router --init` | Write a starter config |

`logout` never deletes without a backup. Credentials move to `~/.config/claude-account-router/backups/`.

## Known limits

**The wrapper is honored by the process, not by the login UI.** The router affects the Claude process the extension launches. The extension's own logout path does not go through it, so `Claude Code: Logout` from the panel can act on the default config dir rather than the profile you are in. Use `claude-account logout <profile>`, which names the directory explicitly.

**An extension update could stop honoring `claudeProcessWrapper`.** Then routing dies while a window marker stays on, which is the failure mode worth fearing. The router logs every launch with `origin=extension`, and `claude-account-check` reports when that evidence is missing or stale. That converts a silent failure into an observable one, and is the reason to run the check after updates.

**Verification depends on a readable account email.** The router reads `oauthAccount.emailAddress` from the config dir's identity file. If a future version stores identity elsewhere, the check cannot confirm the account, and the router blocks instead of guessing.

**Tested on Linux with the VS Code extension.** The mechanism is a documented extension setting plus an environment variable, so other editors that bundle the extension should work. macOS keychain storage is not covered by the tests.

## Tests

```bash
./tests/test-routing.sh
```

Twenty two end to end cases against a throwaway `HOME`: routing by path, by subfolder, by deeply nested subfolder, through a symlink, by worktree outside the repo tree, fallback to default, the marker commands including that they preserve pre-existing settings, and five fail closed paths (wrong account for a profile, an account leaking into the default profile, unreadable identity, missing config dir, missing config file). One case asserts that a profile with no session still starts, since otherwise the first login would be impossible.

## Documentation

`docs/` holds the project axis: [MASTER-SPEC](docs/MASTER-SPEC.md) for architecture and constraints, [TODO](docs/TODO.md), [MEMORY](docs/MEMORY.md) for transferable lessons, [USER-DECISIONS](docs/USER-DECISIONS.md) for the reasoning behind the design, [CHANGELOG](docs/CHANGELOG.md), and [REPOMAP](docs/REPOMAP.md).

## License

MIT. See [LICENSE](LICENSE).
