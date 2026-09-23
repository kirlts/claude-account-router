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

**If the marker is committed, it is not a marker: it is repository content.** Git does not consult
`info/exclude` for a file that is already in the index, so adding the ignore rule changes nothing
and two things follow. The marker ships to whoever clones the repository, who inherits your title
bar and your profile name. And it lives or dies by the branch: checking out a branch that does not
carry the file deletes it from disk, silently, and the bar disappears with no error to read.
Re-marking looks like it worked until the next branch switch.

`mark` now detects that case and takes the file out of the index, leaving it on disk. It tells you
to commit that removal, because until you do, the deletion is still one checkout away.
`claude-account-check` reports it as its own failure, separate from a merely un-ignored marker,
and prints the command.

This cost an afternoon on 2026-08-30, in a repository whose marker had been committed since its
first commit. What surfaced it was renaming the project folder — the route stopped matching, and
fixing the route did not bring the bar back, because by then a branch switch had removed the file.

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
| `claude-account isolate [--apply]` | Give each profile its own memory and history, and keep each folder's history visible |
| `claude-account-router --init` | Write a starter config |

`logout` never deletes without a backup. Credentials move to `~/.config/claude-account-router/backups/`.

## Isolate memory and history

Creating a second profile usually means symlinking the shared pieces of the first, and it is easy to include `projects/` without noticing. That directory holds per-project memory and every session transcript, so sharing it lets each account read the others'.

```bash
claude-account isolate            # shows the plan
claude-account isolate --apply    # performs it
```

Each project directory moves to the profile that owns its folder. Ownership comes from the working directory recorded inside the session files, not from decoding the directory name, which is ambiguous because slashes and literal dashes both become dashes. History left behind by deleted agent worktrees is matched by the encoded origin folder inside its own name, since neither path nor git can resolve a folder that no longer exists.

Three rules it follows, each learned the hard way:

- **Nothing is deleted or overwritten.** If both profiles hold the same session, an identical copy is removed and a differing one goes to quarantine under `~/.config/claude-account-router/orphaned/`.
- **Unknown ownership means untouched.** A directory whose owner cannot be established stays where it is. Defaulting it would move history out of a restricted account into the least restricted one.
- **It unshares before planning.** While a profile's `projects/` is still a symlink, source and destination are the same directory and every project looks correctly placed, so nothing would ever be planned.

It also keeps each folder's history visible in the editor, which isolation alone breaks. The editor process never sees `CLAUDE_CONFIG_DIR`: it lists a folder's past sessions from `~/.claude/projects` whatever account that folder routes to. So a symlink named for the folder lives there, pointing at the profile that owns it. History then belongs to the folder it was produced in, which is what the panel means by "this folder's sessions", while the transcripts stay in the account that produced them. The router keeps that link current on every launch, so a folder opened for the first time is covered too, and it is removed when a folder returns to the default profile.

A project whose folder no longer exists gets no link. Its history still belongs to its account; no editor window can ask for it by folder.

Note the boundary: this isolates data at rest, and the name that makes history reachable sits in the default profile. MCP servers, skills and instructions are shared or separated by how you build each config dir.

## Hooks follow the work, not the folder

Claude Code runs a project's `.claude/settings.json` hooks only in a session opened in that project. A session opened anywhere else, for example a relief session on another account taking over when the first one ran out of quota, can edit files of a repository whose guards never run. Remembering to run them by hand is exactly what hooks exist to avoid.

```bash
claude-account-hooks install    # registers it in every profile's settings.json
claude-account-hooks check      # exit 0 if every profile has it
```

Once registered, it runs as a hook of its own on every event and applies the hooks of the repositories the session is working on:

- A tool call that touches a declared repository (a file path inside it, the call's working directory, or a `cd` or `git -C` into it) runs that repository's hooks for that call. A block passes through unchanged.
- A session that wrote into a repository, or ran a command from inside it, is marked as working there. From then on, prompts, session start, stop and every tool call also run that repository's hooks, so reminders and guards behave as if the session had been opened there. Reading a file does not mark a session.
- The repository the session was opened in is skipped, since Claude Code already runs its hooks.

Only repositories claimed by a `route` in `routes.conf` are trusted. Looking at a repository you never declared never executes its hooks. `install --replace <command>` removes an older hook entry in the same pass. It keeps a backup of each settings file it changes and does nothing when everything is already registered.

## Known limits

**The wrapper is honored by the process, not by the editor.** The router affects the Claude process the extension launches. The editor process itself runs outside it, which has two consequences. `Claude Code: Logout` from the panel can act on the default config dir rather than the profile you are in, so use `claude-account logout <profile>`, which names the directory explicitly. And the panel reads every folder's past sessions from the default config dir, which is why isolated history needs the link described above.

**An extension update could stop honoring `claudeProcessWrapper`.** Then routing dies while a window marker stays on, which is the failure mode worth fearing. The router logs every launch with `origin=extension`, and `claude-account-check` reports when that evidence is missing or stale. That converts a silent failure into an observable one, and is the reason to run the check after updates.

**Verification depends on a readable account email.** The router reads `oauthAccount.emailAddress` from the config dir's identity file. If a future version stores identity elsewhere, the check cannot confirm the account, and the router blocks instead of guessing.

**Renaming a routed folder breaks its route, and the symptom is a grey bar.** Routes match by path,
so a renamed project stops matching and falls through to the default profile: no colour, and the
wrong account. `claude-account routes` shows a route pointing at a path that no longer exists.
Editing the route in `routes.conf` is half the fix; the other half is `claude-account mark` on the
new path, because the marker lives inside the folder that changed name.

**Tested on Linux with the VS Code extension.** The mechanism is a documented extension setting plus an environment variable, so other editors that bundle the extension should work. macOS keychain storage is not covered by the tests.

## Tests

```bash
./tests/test-routing.sh
./tests/test-foreign-hooks.sh
```

Forty end to end cases against a throwaway `HOME`: routing by path, by subfolder, by deeply nested subfolder, through a symlink, by worktree outside the repo tree, fallback to default, the marker commands including that they preserve pre-existing settings, the isolation of memory and history, the links that keep it visible by folder, and five fail closed paths (wrong account for a profile, an account leaking into the default profile, unreadable identity, missing config dir, missing config file). One case asserts that a profile with no session still starts, since otherwise the first login would be impossible.

## Documentation

`docs/` holds the project axis: [MASTER-SPEC](docs/MASTER-SPEC.md) for architecture and constraints, [TODO](docs/TODO.md), [MEMORY](docs/MEMORY.md) for transferable lessons, [USER-DECISIONS](docs/USER-DECISIONS.md) for the reasoning behind the design, [CHANGELOG](docs/CHANGELOG.md), and [REPOMAP](docs/REPOMAP.md).

## License

MIT. See [LICENSE](LICENSE).
