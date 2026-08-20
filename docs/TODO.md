# TODO: claude-account-router v1.4.0

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

### [TASK-012] Cover subfolders in both the routing and the marker

> Ref: MASTER-SPEC §2, §7.3

**Covered checks:** Transversal governance

Reported as "routing does not work for subfolders". Routing did work, confirmed in the router log against real editor sessions on a subfolder the user had opened. The missing piece was the marker, which VS Code cannot inherit from a parent folder.

- [x] Reproduce the claim against the router log and against every subfolder depth before changing anything `2026-08-03 12:52:00`
- [x] Compare canonical paths as well as literal ones, so a folder opened through a symlink keeps its route `2026-08-03 12:58:00`
- [x] Add `mark` and `unmark`, merging into existing settings and refusing to touch an unparseable file `2026-08-03 13:02:00`
- [x] Optional per profile color as a fourth `profile` field `2026-08-03 13:02:00`
- [x] Tests: nested depth, symlinked path, marker merge, marker refusal on the default profile `2026-08-03 13:05:00`
- [x] State plainly in the README that routing covers subfolders and markers do not inherit `2026-08-03 13:10:00`
- [x] [TASK-012]; 2026-08-03 13:10 [🤖 Verified by tool]

### [TASK-013] Make the marker track the account, not a snapshot of the folder

> Ref: MASTER-SPEC §4.8, §4.9

**Covered checks:** Transversal governance

Reported after a narrower route sent one subfolder to a different account: the amber marker stayed on while the session ran under the other account. The distinction the user drew is the right one, the color has to follow the account, not the folder.

- [x] Router recomputes an existing marker on every launch against the resolved profile `2026-08-19 22:58:00`
- [x] Remove the marker when the folder now resolves to the default profile `2026-08-19 22:58:00`
- [x] Recognize only this project's own marker by signature, leaving hand made customizations alone `2026-08-19 22:58:00`
- [x] Derive title bar text colors from the profile color by luminance, so any color stays legible `2026-08-19 23:10:00`
- [x] Unify marker generation into `car_write_marker`, ending the duplicated copies in `mark` and in the sync `2026-08-19 23:14:00`
- [x] Migrate markers written before the signature existed, so they enter the sync instead of silently opting out `2026-08-19 23:20:00`
- [x] [TASK-013]; 2026-08-19 23:20 [🤖 Verified by tool]

### [TASK-014] Stop a subfolder route from claiming its whole repository

> Ref: MASTER-SPEC §2

**Covered checks:** Transversal governance

Found by the verifier while adding a personal-account exception inside a work repository: repository wide matching made every worktree of the work repo follow the subfolder's route, handing them to the personal account. The verifier had the same wrong assumption in its worktree listing, so it reported failures against correct behavior once the library was fixed.

- [x] Restrict repository wide matching to routes that are their repository's top level `2026-08-19 22:40:00`
- [x] Apply the same rule in the verifier's worktree enumeration `2026-08-19 22:46:00`
- [x] Test the case: narrower route inside a routed repo, with the repo root and an out of tree worktree asserted `2026-08-19 23:30:00`
- [x] Fix the sandbox route order in that test, since the first matching route wins `2026-08-19 23:32:00`
- [x] [TASK-014]; 2026-08-19 23:32 [🤖 Verified by tool]

### [TASK-015] Give each profile its own memory and session history

> Ref: MASTER-SPEC §4.10, §4.11, §7.3

**Covered checks:** Transversal governance

A second profile is naturally built by symlinking the shared directories from the first, which quietly shares `projects/` too: per-project memory and full session transcripts. Every account could read every other account's.

- [x] `car_projects_dir`, `car_encoded_path`, `car_project_cwd`, `car_profile_for_project` in the shared library `2026-08-19 23:40:00`
- [x] `claude-account isolate`, dry run by default, moving each project to the profile that owns its folder `2026-08-19 23:44:00`
- [x] Classify by the `cwd` recorded inside session files, not by decoding the directory name, which is ambiguous `2026-08-19 23:40:00`
- [x] Classify history of deleted worktrees by the encoded origin inside the directory name, derived from the declared routes `2026-08-19 23:41:00`
- [x] Leave a directory alone when its owner cannot be determined, instead of defaulting it toward the least restricted account `2026-08-19 23:58:00`
- [x] Unshare before planning: while the symlink stood, everything looked correctly placed and nothing was ever planned `2026-08-19 23:54:00`
- [x] Merge rather than skip when both sides hold the same session, quarantining a differing copy without overwriting or deleting `2026-08-19 23:50:00`
- [x] Tests: cwd classification, personal stays put, deleted worktree history, symlink becomes a real dir, idempotency, undeterminable origin, conflict quarantine `2026-08-20 00:04:00`
- [x] [TASK-015]; 2026-08-20 00:04 [🤖 Verified by tool]

### [TASK-016] Make history reachable by folder, not by the account that produced it

> Ref: MASTER-SPEC §4.12, §7.1, §7.3, §7.4

**Covered checks:** Transversal governance

Reported the morning after TASK-015 shipped: the session history of every routed folder was gone from the editor's panel. Nothing was lost, and nothing was misplaced. The editor process never sees `CLAUDE_CONFIG_DIR`, so it lists a folder's sessions from the default profile whatever account that folder routes to, and isolation had moved a hundred and twenty transcripts out of the only path it reads.

- [x] Reproduce it against the installed extension before changing anything: read the handler for `list_sessions_request` and follow it to the projects directory it resolves from the process environment `2026-08-20 01:00:00`
- [x] Confirm the editor process runs without `CLAUDE_CONFIG_DIR` while the Claude process it launches has it, so the two disagree by construction `2026-08-20 01:02:00`
- [x] `car_project_slug`, reproducing Claude Code's encoding: every non-alphanumeric character, not only slashes `2026-08-20 01:05:00`
- [x] `car_link_history_view` and `car_sync_history_view`, naming a folder's history where the editor looks, pointing at the profile that owns it `2026-08-20 01:06:00`
- [x] Router writes and updates the name on every launch, beside the marker, so a folder's first session is visible too `2026-08-20 01:07:00`
- [x] Remove the name when the folder returns to the default profile, and never repoint a link the user made by hand `2026-08-20 01:07:00`
- [x] Leave a real directory holding that name alone at launch, since resolving it means comparing and quarantining files, which is `isolate`'s work `2026-08-20 01:07:00`
- [x] `isolate` writes the missing names, skips a project whose folder no longer exists, and stops treating a view link as a misplaced project `2026-08-20 01:09:00`
- [x] Verifier block 5, counting the sessions the editor can reach against the sessions the owning profile holds `2026-08-20 01:15:00`
- [x] Tests: link written and readable through, no link for a default-profile project, none for a deleted folder, idempotency with links present, a first launch links a folder with no history, no empty target directory created, link removed on a routing change, a foreign link untouched, real history untouched, and the slug encoding asserted against Claude Code's `2026-08-20 01:12:00`
- [x] [TASK-016]; 2026-08-20 01:15 [🤖 Verified by tool]

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
| EPIC-002 | TASK-006 to 008, 012 to 016 | ☑ Complete | 0 | 0 | 0 | 0 |
| EPIC-003 | TASK-009 to 011 | ☐ Open | 0 | 0 | 0 | 0 |

> Check counts are zero because `VERIFICATION.md` has not been generated by `/derive` yet. Every task above therefore carries `Transversal governance` as its covered check, and the assertions that do exist live in `tests/test-routing.sh`.
