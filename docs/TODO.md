# TODO: claude-account-router v1.0.0

> Direct traceability: each task references checks from `VERIFICATION.md`.

## Kairós Symbol Legend

| Symbol | Meaning |
|---|---|
| 🤖 | Check verifiable by AI/automated tool |
| 🧑 | Check requiring human verification |
| 🤖🧑 | Check pre-verifiable by AI, final human validation |
| ⏳ | In progress |
| 🔲 | Pending |
| 🚨 | Critical block |

---

## [EPIC-001] Route Claude Code accounts by folder in the VS Code extension

> Ref: MASTER-SPEC §1, §2

### [TASK-001] Establish that the extension can be routed at all

> Ref: MASTER-SPEC §3

**Covered checks:** Transversal governance

- [x] Inspect the installed extension manifest for settings and commands it declares `2026-08-03 11:05:00`
- [x] Confirm the bundle resolves its config dir from `CLAUDE_CONFIG_DIR` `2026-08-03 11:06:00`
- [x] Establish that `claudeProcessWrapper` and `environmentVariables` carry `machine` scope, ruling out workspace settings `2026-08-03 11:07:00`
- [x] [TASK-001]; 2026-08-03 11:07 [🤖 Verified by tool]

### [TASK-002] Wrapper that resolves a profile per folder

> Ref: MASTER-SPEC §2, §7.2

**Covered checks:** Transversal governance

- [x] Resolve by path prefix `2026-08-03 11:12:00`
- [x] Resolve by git common dir, so worktrees follow their repository wherever they live `2026-08-03 11:29:00`
- [x] Export `CLAUDE_CONFIG_DIR` for non default profiles, leave it unset for the default `2026-08-03 11:12:00`
- [x] [TASK-002]; 2026-08-03 11:29 [🤖 Verified by tool]

### [TASK-003] Fail closed identity verification

> Ref: MASTER-SPEC §4.1, §4.4

**Covered checks:** Transversal governance

- [x] Read the account email from the identity file Claude Code maintains `2026-08-03 11:20:00`
- [x] Block when the account does not match the profile glob `2026-08-03 11:20:00`
- [x] Block when an account claimed by another profile appears in this one `2026-08-03 11:21:00`
- [x] Fix the identity path: the default profile keeps it in `$HOME`, not inside `~/.claude`, so the check was passing while verifying nothing `2026-08-03 11:38:00`
- [x] Allow a launch when the profile has no session, otherwise a first login is impossible `2026-08-03 11:22:00`
- [x] [TASK-003]; 2026-08-03 11:38 [🤖 Verified by tool]

### [TASK-004] Verification command over effective state

> Ref: MASTER-SPEC §4.7, §7.4

**Covered checks:** Transversal governance

- [x] Verify editor wiring by comparing the setting against the installed router `2026-08-03 11:31:00`
- [x] Verify routing by running the router in every declared route `2026-08-03 11:31:00`
- [x] Verify account identity per profile, including cross profile leaks `2026-08-03 11:40:00`
- [x] Report evidence that the editor itself went through the router, so a wrapper that stops being honored is observable `2026-08-03 11:47:00`
- [x] Stop using `printenv` for the probe, since its exit code conflates unset with failure `2026-08-03 11:39:00`
- [x] [TASK-004]; 2026-08-03 11:47 [🤖 Verified by tool]

### [TASK-005] Account console for everyday operation

> Ref: MASTER-SPEC §7.3

**Covered checks:** Transversal governance

- [x] Status view of which account sits in which profile, marking foreign accounts `2026-08-03 11:44:00`
- [x] `logout` with a timestamped backup, clearing the stored identity as well `2026-08-03 11:44:00`
- [x] `login` per profile, refusing when a session already exists `2026-08-03 11:44:00`
- [x] Return a status instead of calling `exit` inside a command substitution `2026-08-03 11:46:00`
- [x] [TASK-005]; 2026-08-03 11:46 [🤖 Verified by tool]

---

## [EPIC-002] Make it a reusable public tool

> Ref: MASTER-SPEC §4.5, §4.6

### [TASK-006] Replace hardcoded values with a config model

> Ref: MASTER-SPEC §4.6

**Covered checks:** Transversal governance

- [x] Define the `profile` and `route` directives `2026-08-03 12:02:00`
- [x] Move routing, identity, and glob logic into `lib/common.sh` so the identity resolution exists once `2026-08-03 12:05:00`
- [x] Support any number of profiles, not two `2026-08-03 12:05:00`
- [x] [TASK-006]; 2026-08-03 12:05 [🤖 Verified by tool]

### [TASK-007] Tests against a throwaway HOME

> Ref: MASTER-SPEC §7.5

**Covered checks:** Transversal governance

- [x] Routing cases: path, subfolder, out of tree worktree, fallback to default `2026-08-03 12:12:00`
- [x] Fail closed cases: wrong account, cross profile leak, unreadable identity, missing config dir, missing config file `2026-08-03 12:12:00`
- [x] First login case, asserting a profile with no session still starts `2026-08-03 12:12:00`
- [x] [TASK-007]; 2026-08-03 12:12 [🤖 Verified by tool]

### [TASK-008] Installer and documentation axis

> Ref: MASTER-SPEC §6, §8

**Covered checks:** Transversal governance

- [x] `install.sh` linking commands, seeding config, printing next steps, with `--uninstall` `2026-08-03 12:08:00`
- [x] README covering the problem, the mechanism, configuration, verification, and known limits `2026-08-03 12:20:00`
- [x] Documentary axis: MASTER-SPEC, TODO, MEMORY, USER-DECISIONS, CHANGELOG, RULES, REPOMAP `2026-08-03 12:30:00`
- [x] [TASK-008]; 2026-08-03 12:30 [🤖 Verified by tool]

---

## [EPIC-003] Open work

> Ref: MASTER-SPEC §4, README known limits

### [TASK-009] Close the panel logout asymmetry

> Ref: MASTER-SPEC §5, README known limits

**Covered checks:** Transversal governance

The extension's own logout path does not go through the wrapper, so `Claude Code: Logout` can act on the default config dir instead of the profile in use. Today this is handled by documentation and by `claude-account logout`, which is a convention rather than a mechanism.

- [ ] Determine whether a `SessionStart` hook inside a routed profile can assert the expected account independently of the wrapper
- [ ] If viable, ship it as an optional hardening step with its own verification block

### [TASK-010] Verify behavior beyond Linux and VS Code

> Ref: MASTER-SPEC §3, README known limits

**Covered checks:** Transversal governance

- [ ] Confirm identity resolution when credentials live in a macOS keychain rather than a file
- [ ] Confirm the wrapper setting is honored by other editors that bundle the extension

### [TASK-011] Detect an extension update that drops the wrapper setting

> Ref: MASTER-SPEC §4.7

**Covered checks:** Transversal governance

Block 6 of the verifier infers this from log staleness, which requires the user to run the check. A stronger signal would read the installed extension manifest and report when `claudeCode.claudeProcessWrapper` is no longer declared.

- [ ] Locate the installed extension manifest portably
- [ ] Add a verification block that fails when the setting is gone from it

---

## Overall Coverage Summary

| Epic | Tasks | Status | 🤖 .LLM | 🧑 .HUM | 🤖🧑 .MIX | Total Checks |
| --- | --- | --- | --- | --- | --- | --- |
| EPIC-001 | TASK-001 to 005 | ☑ Complete | 0 | 0 | 0 | 0 |
| EPIC-002 | TASK-006 to 008 | ☑ Complete | 0 | 0 | 0 | 0 |
| EPIC-003 | TASK-009 to 011 | ☐ Open | 0 | 0 | 0 | 0 |

> Check counts are zero because `VERIFICATION.md` has not been generated by `/derive` yet. Every task above therefore carries `Transversal governance` as its covered check, and the assertions that do exist live in `tests/test-routing.sh`.
