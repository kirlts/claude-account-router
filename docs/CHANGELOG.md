# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

*Nothing pending.*

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
