# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

*Nothing pending.*

## [1.4.0] - 2026-08-20

### Fixed
- Every routed folder's session history vanished from the editor's panel after 1.3.0. Isolation moved the transcripts into each profile, but the editor process never sees `CLAUDE_CONFIG_DIR`: it lists a folder's sessions from the default profile whatever account that folder uses. Four folders holding a hundred and twenty sessions read as empty. History is now named where the editor looks, pointing at the profile that owns it, so it belongs to the folder it was produced in rather than to the account that happened to produce it.
- The residual leak documented in 1.3.0 is closed as a side effect. The session metadata the editor wrote outside the router used to land in the default profile as a stub next to the real transcript, which `isolate` then had to quarantine; it now lands in the same file the account owns.

### Added
- The router writes and updates that name on every launch, beside the window marker, so a folder opened for the first time has its history visible from its first session. It is removed when the folder returns to the default profile, and a link the user made by hand is never repointed.
- `claude-account isolate` writes the missing names as part of its run and reports them separately from the moves, so history that is correctly placed but invisible is not reported as nothing to do.
- Block 5 of the verifier: for every folder whose history is isolated, it counts the sessions the editor can reach and compares them against the sessions the owning profile holds.
- `car_project_slug`, which reproduces Claude Code's own project directory name. Every non-alphanumeric character becomes a dash, not only slashes, so a path holding a dot or an underscore is named the way the editor will look for it.

## [1.3.0] - 2026-08-19

### Added
- `claude-account isolate`, which gives each profile its own per-project memory and session history. Creating a second profile by symlinking `projects/` leaves every account able to read every other account's memory and transcripts; this moves each project directory to the profile that owns its folder. Dry run by default, since it moves directories that can hold gigabytes.
- Classification reads the real `cwd` recorded inside session files rather than decoding the directory name, which is ambiguous because both slashes and literal dashes become dashes.
- History of deleted agent worktrees is classified by the encoded origin folder inside its own directory name, derived from the declared routes. Without this, transcripts produced by a work account fall to the default profile, since neither path nor git can resolve a folder that no longer exists.

### Fixed
- A project directory whose owner cannot be determined is now left where it is. It used to be classified as the default profile, which moved history OUT of a restricted account INTO the least restricted one: the exact leak the command exists to close.
- Unsharing now happens before planning. While a profile's `projects/` was still a symlink to the default one, source and destination were the same directory, so every project looked correctly placed, nothing was planned, and the symlink was never removed. The state to be fixed was the state that hid the need to fix it.
- A conflicting copy of the same session on both sides is quarantined under the router's own config home instead of being skipped or overwritten. Identical copies are removed. Nothing is deleted when it holds content the other side lacks.

## [1.2.0] - 2026-08-19

### Added
- The router now keeps an existing window marker truthful on every launch. A marker written when a folder routed to one profile used to survive a routing change and keep claiming the old account while Claude ran under the new one. Since the router only reaches that point after the identity check passed, the profile it resolved and the live account are the same thing, so the marker now tracks the account rather than a snapshot of the folder.
- Title bar text colors are derived from the profile color by relative luminance, so any color stays legible. The previous fixed cream foreground was chosen for an amber bar and looked wrong on a blue one.
- Marker generation lives in one function, `car_write_marker`, shared by `claude-account mark` and the router's sync. The two had separate copies that could drift.
- Tests for the color derivation, for a narrower route inside an already routed repository, and for marker syncing. Twenty two cases total.

### Fixed
- A route on a subfolder of a repository claimed that whole repository's identity, so every worktree of the repo followed the subfolder's profile instead of the repository's own route. With a narrower personal-account exception inside a work repository, that handed every worktree of the work repo to the personal account. Repository wide matching is now restricted to routes that are their repository's top level.
- The verifier reproduced the same wrong assumption when listing worktrees, reporting failures against correct behavior.

## [1.1.0] - 2026-08-03

### Added
- `claude-account mark` and `claude-account unmark`, writing the window marker for the profile that owns a folder. Needed because VS Code reads `.vscode/settings.json` only from the folder opened and never from a parent, so a marker cannot be inherited by subfolders the way routing is. Merges into an existing file, refuses to touch an unparseable one, and adds `.vscode/` to the repository's local exclude file.
- Optional fourth field on `profile` for the title bar color used by `mark`.
- Tests for deeply nested subfolders, folders reached through a symlink, and the marker commands including preservation of pre-existing settings. Seventeen cases total.

### Changed
- Path matching now compares canonical paths as well as literal ones, so a folder opened through a symlink resolves to its route instead of falling back to the default profile.

### Fixed
- Clarified in the README that routing already covers every subfolder at any depth. The missing color in a subfolder was a display gap being read as a routing failure.

## [1.0.0] - 2026-08-03

### Added
- Per folder account routing for the Claude Code VS Code extension, through the `claudeCode.claudeProcessWrapper` setting.
- Config model with `profile` and `route` directives, supporting any number of accounts.
- Routing by git repository, so every worktree of a routed repository uses the same account wherever it lives on disk.
- Fail closed identity verification: a launch is refused when the account does not match the profile, when an account claimed by another profile appears, when the identity is unreadable, or when a profile's config dir is missing.
- `claude-account` for status, routes, login, and logout, with timestamped credential backups.
- `claude-account-check`, verifying effective state across six blocks, including evidence that the editor itself went through the router.
- `install.sh` with symlink based installation and `--uninstall`.
- `tests/test-routing.sh`, eleven end to end cases against a throwaway `HOME`.
- Documentary axis in `docs/`, plus a README covering the mechanism, configuration, verification, and known limits.
