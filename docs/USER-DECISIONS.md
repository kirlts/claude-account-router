# USER-DECISIONS: Human Agency Record

> This document IS NOT A CHANGELOG. It is the register of user sovereignty.
> It captures the strategic "why" and the explicit intentions that the user communicates.

| Symbol | Meaning |
|---|---|
| 💡 | Strategic user decision |
| 🔗 | Traceable cross-reference to `.HUM` checks |

---

## [UD-001] The VS Code extension is not negotiable

**Date:** 2026-08-03
**Context:** Multi account support exists in the Claude Code terminal CLI through `CLAUDE_CONFIG_DIR`. The extension has no equivalent. The obvious advice, found in issue threads and given by an assistant consulted first, was to use the CLI for the second account.
**Decision:** The solution has to work in the extension, opening a folder and clicking the panel icon. An answer that requires moving to the terminal is not an answer to this problem.
**Discarded alternatives:**
- Terminal CLI with a shell alias per account. Rejected: it abandons the interface actually in use.
- Manual logout and login when changing project. Rejected: it is the problem, restated as a workaround.
- A third party account switcher extension. Rejected: all of them switch on command, none route by folder, so the account still depends on remembering to switch.
**Consequences:**
- The design is constrained to what the extension exposes, which turned out to be `claudeCode.claudeProcessWrapper`.
- `machine` scope on that setting rules out per workspace configuration, so routing had to move into a config file read by the wrapper.
**Reversion conditions:** If the extension ships a native per workspace account selector, the wrapper becomes unnecessary.

---

## [UD-002] The indicator must be unable to lie

**Date:** 2026-08-03
**Context:** A colored title bar per folder was proposed so the active account is visible. The user identified the dangerous failure directly: the marker showing while routing is not actually working.
**Decision:** Guarantee by design that a visible marker cannot contradict the session. The router verifies the real account identity on every launch and refuses to start Claude on a mismatch, in either direction, so a running panel proves the account.
**Discarded alternatives:**
- Trusting the marker as a status display. Rejected: a static setting cannot measure a live session.
- Making the marker dynamic. Rejected: the editor reads window settings at load, there is no honest way to drive them from the session.
**Consequences:**
- Any uncertainty resolves as a blocked launch, which is louder and less convenient than a fallback, and is the point.
- The marker's claim was narrowed in the documentation to a static fact, "this folder is declared as work", with the guarantee supplied by the block rather than by the color.
- A verification command became mandatory, since the guarantee is only as good as the evidence it can produce on demand.
**Reversion conditions:** None foreseen. Weakening this turns the tool into a convention.

---

## [UD-003] Profiles share configuration, and separate only credentials

**Date:** 2026-08-03
**Context:** A second config dir starts empty. Skills, MCP servers, global instructions, and project memory all live in the first one, and the second account would lose them in exactly the projects where they matter most.
**Decision:** Separate the credentials, share everything else by symlinking the shared files into the second config dir. One source of truth for what the tooling has learned.
**Discarded alternatives:**
- A clean second profile. Rejected: it would mean rebuilding connectors and memory, and then maintaining two divergent copies.
- Copying the shared files. Rejected: copies drift, and the drift is silent.
**Consequences:**
- The account identity file is not shared, since sharing it would cross identities between accounts.
- The project documents this as a recommended layout rather than automating it, because which files are safe to share depends on the user's setup.
**Reversion conditions:** If a shared file starts carrying account scoped state, that file stops being shared.

---

## [UD-004] Only the title bar is marked

**Date:** 2026-08-03
**Context:** The first marker colored the title bar, the activity bar, and the status bar. The result was an intense color across the whole window.
**Decision:** Mark the title bar only.
**Discarded alternatives:**
- Full window tinting. Rejected by the user on sight: too loud for something that is a background fact, not an alert.
**Consequences:** The marker is peripheral, which suits a fact that holds all session long.
**Reversion conditions:** None.

---

## [UD-005] Released as a public tool under MIT

**Date:** 2026-08-03
**Context:** The mechanism was built to solve one machine's problem, and the underlying gap is common to anyone holding a personal and an employer account.
**Decision:** Extract it into a standalone public repository, with every folder, config dir, and expected account read from a config file, and no trace of the original installation in the code or the docs.
**Discarded alternatives:**
- Keeping the scripts in a personal dotfiles directory. Rejected: it loses the work and helps nobody else.
- Publishing the scripts as found, with paths and domains inline. Rejected: not reusable, and it would leak the original context.
**Consequences:**
- Hardcoded values became `routes.conf` directives, which required the profile and route model that did not exist in the first version.
- The project needs its own tests, since it now runs on machines whose layout is unknown.
**Reversion conditions:** None.
