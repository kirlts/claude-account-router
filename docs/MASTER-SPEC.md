# MASTER-SPEC: claude-account-router v1.0.0

> Routes Claude Code to a different account per folder in the VS Code extension, and refuses to start when the account does not match.

---

## §1. Project Identity

**Purpose:** Let one machine hold several Claude Code accounts and have the right one selected by the folder you open, with no manual switching, inside the VS Code extension rather than only the terminal CLI. The account separation must be verifiable at any moment, so that a marker in the editor cannot claim one thing while the session does another.

**Name:** claude-account-router

**Domain:** Developer tooling, identity and credential routing.

**Problem it solves:** The Claude Code CLI supports multiple accounts through `CLAUDE_CONFIG_DIR`. The VS Code extension offers no account picker and no per-workspace override: it uses the last account logged in. Anyone holding a personal account and a work account on one machine has to log out and log back in when moving between projects, and has no reliable way to tell which account a session is using. A wrong guess sends work activity to a personal subscription, or personal activity to an employer's account.

**Direct beneficiary:** A developer who uses the Claude Code extension for VS Code across projects belonging to different accounts, for example a personal account and an employer account, or several client accounts.

**Indirect beneficiary:** The organizations owning those accounts, whose usage and audit trail stop being mixed with unrelated activity.

**What it IS NOT:**
- Not a credential manager. It never mints, stores, or transmits tokens. It selects which directory Claude Code reads and lets Claude Code own the login.
- Not a VS Code extension. It is a wrapper executable plus companion commands. It changes no editor code.
- Not an account switcher driven by a menu. Switching by hand is the problem it removes.
- Not a way to bypass account limits, quotas, or terms. Each profile logs in normally.

---

## §2. Architecture

**Type:** Process wrapper (shim) with a config file, plus two read only companion commands.

**Component Diagram:**

```
VS Code extension
  (claudeCode.claudeProcessWrapper setting)
        |
        v
bin/claude-account-router  ---->  lib/common.sh  <----  bin/claude-account
  reads routes.conf                (routing +           (status, login, logout)
  resolves profile                  identity)
  verifies account                       ^
  sets CLAUDE_CONFIG_DIR                 |
  exec <real claude process>      bin/claude-account-check
                                   (verifies effective state)
```

**Main Data Flow:**

1. The extension launches the wrapper with the real Claude command as arguments, in the workspace folder.
2. The wrapper loads `routes.conf` and resolves which profile owns the current directory, first by path prefix, then by comparing the git common dir so worktrees follow their repository.
3. The wrapper reads the account email of that profile's config dir from the identity file Claude Code maintains.
4. The wrapper blocks when the account contradicts the profile, in either direction: an account outside the profile's declared glob, or an account claimed by a different profile.
5. The wrapper exports `CLAUDE_CONFIG_DIR` for non default profiles, unsets it for the default profile, appends a log line marking who invoked it, and execs the real command.

---

## §3. Technical Stack

| Layer | Technology | Justification |
| --- | --- | --- |
| Wrapper and commands | Bash 4+ | The wrapper sits in the startup path of every Claude launch. A shell script has no runtime to install, no build step, and can be read in full by the person trusting it with account selection. |
| JSON reading | python3 (stdlib) | The identity file is JSON. `jq` is not present on every machine, while python3 is, and stdlib `json` avoids adding a dependency for a single field read. |
| Repository identity | git | `git rev-parse --git-common-dir` is the only correct way to tell that a worktree in an unrelated directory belongs to a routed repository. |
| Editor integration | `claudeCode.claudeProcessWrapper` | A documented setting of the official extension. No patching, no injection, no forked extension. |
| Distribution | git clone plus symlinks | `install.sh` links rather than copies, so `git pull` updates the installed commands with no reinstall. |

---

## §4. Constraints (Inviolable Boundaries)

> These constraints override any other decision.

1. **Fail closed.** When the wrapper cannot prove the active account matches the folder, it does not start Claude. Falling back to another account silently is forbidden, because that is precisely the failure the project exists to prevent.
2. **Never handle credentials.** No component reads, copies, prints, or transmits a token. `logout` moves the credentials file to a backup and clears the identity fields; nothing else touches it. The project reads exactly one field, an email address, to verify identity.
3. **The default profile stays at `~/.claude`, with the variable unset.** Claude Code derives its keychain service name from the config dir, so exporting `CLAUDE_CONFIG_DIR` for the default location would strand the existing session.
4. **Identity resolution exists in exactly one place.** `car_account_email` in `lib/common.sh` is the single implementation. Claude Code resolves the identity file as `<config-dir>/.config.json` when present, otherwise `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`, which means the default profile keeps it in `$HOME`, not inside `~/.claude`. A copy of this logic that gets the path wrong returns empty and makes the account check pass while verifying nothing.
5. **No installation data in the repository.** Config, credentials, backups, and logs live under `${XDG_CONFIG_HOME:-~/.config}/claude-account-router/`. The repository ships an example config and nothing else.
6. **No hardcoded paths, domains, or account names in the code.** Every folder, config dir, and expected account comes from the config file.
7. **The verifier checks effective state.** Asserting that files exist is not verification. Every claim it makes is produced by running the router or by reading real identity.

---

## §5. Agreed Trade-offs

| Trade-off | In favor of | Against | Justification |
| --- | --- | --- | --- |
| Global wrapper setting instead of per workspace settings | Working at all | Per project configuration | `claudeCode.claudeProcessWrapper` and `claudeCode.environmentVariables` both carry `machine` scope, so a workspace `.vscode/settings.json` is ignored for them. One global wrapper reading a config file is the only route to per folder behavior. |
| Shared library instead of a self contained wrapper | One implementation of the identity logic | One more file the wrapper depends on | A duplicated copy of the identity path resolution already produced a bug where the check silently verified nothing. A missing library blocks the launch, which is the safe direction, so centralizing costs nothing in safety. |
| python3 for one JSON field | Correctness on any machine with python3 | A second language in the stack | Parsing JSON with shell text tools breaks on formatting variation, and the field being read is what the entire guarantee rests on. |
| Blocking on an unreadable identity | Never running on an unverified account | Convenience when the format changes | If a future Claude Code version moves the identity field, this project stops working loudly instead of routing blindly. |
| Symlinks over copies at install | Updates through `git pull` | Repository must stay in place | Moving or deleting the clone breaks the commands, which the missing library check reports clearly. |
| Reading the account email | A verifiable identity check | Reading one field of a Claude Code internal file | Without an identity read there is no guarantee, only a convention. The field is not a secret and never leaves the machine. |

---

## §6. UI and User Experience

**Reference atmosphere:** A preflight check, not a dashboard. Output is a flat list of `PASS`, `FAIL`, `TODO`, and `info` lines under numbered headings, readable in a terminal at a glance, with the failure text naming the exact command that fixes it. When the router blocks a launch, the message states which folder, which profile, which account was found, which was expected, and the one command that resolves it.

**Main user flow:**

1. Clone, run `./install.sh`, set `claudeCode.claudeProcessWrapper` in editor user settings.
2. Declare profiles and routes in `routes.conf`.
3. `claude-account login <profile>` for each account, or open a routed folder and log in from the panel.
4. Open folders and work. No further interaction.
5. `claude-account-check` after an extension update, or whenever the setup deserves doubt.

**Interface components:**

| Component | Function | File |
| --- | --- | --- |
| Router | Resolves the profile, verifies the account, blocks or execs | `bin/claude-account-router` |
| Account console | Status, routes, login, logout | `bin/claude-account` |
| Verifier | Six block verification of effective state | `bin/claude-account-check` |
| Installer | Symlinks commands, seeds config, prints next steps | `install.sh` |

---

## §7. Module Specifications

### 7.1. lib/common.sh

**Purpose:** Holds every piece of logic used by more than one command, above all the identity resolution that constraint 4 requires to exist once.

**Interface:**

```
car_load_config()                  -> populates CAR_PROFILE_DIR, CAR_PROFILE_GLOB, CAR_ROUTE_*
car_profile_for_dir <dir>          -> profile name owning that dir
car_account_email <config-dir>     -> email of the logged in account, or empty
car_identity_file <config-dir>     -> path of the json holding the identity
car_has_session <config-dir>       -> exit 0 when credentials are present
car_glob_match <value> <pattern>   -> exit 0 on match, usable in a conditional
car_profile_names                  -> declared profiles, default first
car_expand_path <path>             -> expands a leading ~, strips a trailing /
car_git_common_dir <dir>           -> absolute git common dir, or exit 1
car_log <message>                  -> appends a timestamped line to the router log
```

**Dependencies:** bash, python3, git, coreutils.

### 7.2. bin/claude-account-router

**Purpose:** The wrapper the editor invokes. Decides the account, enforces the match, execs the real command.

**Interface:**

```
claude-account-router <command> [args...]   # normal use, invoked by the editor
claude-account-router --init                # write a starter config
claude-account-router --version | --help
```

**Dependencies:** `lib/common.sh`. A missing library exits non zero without launching Claude.

### 7.3. bin/claude-account

**Purpose:** Everyday operation: see which account sits in which profile, and move sessions in and out without touching the panel's logout path, which does not respect the wrapper.

**Interface:**

```
claude-account [status] | routes | check | login <profile> | logout <profile>
```

**Dependencies:** `lib/common.sh`, the `claude` executable for `login`.

### 7.4. bin/claude-account-check

**Purpose:** Verification. Six blocks: editor wiring, configuration, routing by running the router, account identity, the optional window marker, and evidence that the editor itself went through the router.

**Interface:**

```
claude-account-check     # exit 0 when nothing fails, 1 when something would break separation
```

**Dependencies:** `lib/common.sh`, `bin/claude-account-router`.

### 7.5. tests/test-routing.sh

**Purpose:** End to end assertions of routing and of every fail closed path, against a throwaway `HOME` so no real installation is involved.

**Interface:**

```
./tests/test-routing.sh   # exit 0 when all cases pass
```

**Dependencies:** bash, git, python3, `mktemp`.

---

## §8. Operational Rules

> How an AI agent operates within this repository.

**Rules location:** `docs/RULES.md`

**Scope:** Every change to `bin/`, `lib/`, or `install.sh`. Documentation only changes are exempt from the test requirement but not from the language and content rules.
