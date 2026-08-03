# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

*Nothing pending.*

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
