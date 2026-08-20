# REPOMAP: claude-account-router

> Generated: 2026-08-03 (documented with Kairós v4.0.0 templates)  
> Purpose: Routing matrix. Defines when the AI is authorized to read each directory or file.

## Authoring Constraints (Read Before Populating)

- **Scope:** This repository documents itself with the Kairós template set but does not vendor the framework, so there is no `.agents/` governance layer to map. Operational rules for agents live in `docs/RULES.md`, referenced from MASTER-SPEC §8, and appear below as a Domain Axiom.
- **Abstraction level:** Source is mapped at directory level. Only documentation and specification files earn individual rows.
- **Anti-recency bias:** File modification dates play no part. Prominence follows the architectural role stated in MASTER-SPEC.
- **MECE:** Every row is mutually exclusive and the set is collectively exhaustive.
- **Language:** English, regardless of the host project's language.

## Routing Matrix

| Directory / File | Nature | When to Consult |
|---|---|---|
| `docs/MASTER-SPEC.md` | **[Domain Axiom]** Identity, architecture, stack, constraints, trade-offs, module specs. | **MANDATORY before any code change.** Constraints §4 and trade-offs §5 decide questions that the code alone cannot answer, in particular why the wrapper is global and why identity resolution lives in one place. |
| `docs/RULES.md` | **[Domain Axiom]** Operational rules for agents editing this repository. | **MANDATORY before editing `bin/`, `lib/`, or `install.sh`.** Contains the banned patterns that already caused defects here. |
| `lib/` | Shared bash library. Config parsing, profile resolution, account identity, glob matching. | Whenever behavior involves which profile owns a folder or which account is logged in. Constraint §4.4 forbids reimplementing anything found here. |
| `bin/` | The three executables: the wrapper the editor invokes, the account console (status, login, logout, markers, isolation), the verifier. | When changing what the router decides, what the console operates on, or what the verifier measures. Read `lib/` first. The console is the only component that moves user data, so read MASTER-SPEC §4.10 and §4.11 before touching `cmd_isolate`. |
| `tests/` | End to end assertions against a throwaway `HOME`, covering routing and every fail closed path. | Before claiming any change to `bin/` or `lib/` works, per RULES rule 1. Also the place to read what the guarantees actually are, stated executably. |
| `examples/` | The annotated example config shipped to users, and the seed for a fresh install. | When the config format changes. A new directive that does not appear here is undiscoverable. |
| `install.sh` | Installer. Symlinks the commands, seeds config, prints the editor setting, supports `--uninstall`. | When adding or renaming a command, or changing where config lives. |
| `README.md` | User facing entry point: problem, mechanism, install, config, verification, known limits. | When user visible behavior changes, and when a limitation is discovered or closed. The known limits section is the honest boundary of the guarantee. |
| `docs/TODO.md`, `docs/MEMORY.md`, `docs/USER-DECISIONS.md`, `docs/CHANGELOG.md`, `docs/VERIFICATION.md` | Remaining documentary axis: task traceability, transferable heuristics, the record of human decisions, released history, and the pending derived checklist. | At the close of any work session. `USER-DECISIONS.md` before proposing a design change, since it records what was already decided and why. `MEMORY.md` before repeating a pattern that failed here. |
| `LICENSE`, `.gitignore` | Distribution and hygiene metadata. | Only when licensing or ignore rules change. Carries no behavior. |
