# MEMORY: Transferable Heuristics

> Repository of patterns and lessons that are useful in any project, regardless of the domain.
> Append-Only file. The system prevents reducing, deleting, or synthesizing prior content.

| Symbol | Meaning |
|---|---|
| 🧠 | Transferable heuristic learned |

---

## [HEU-001] Verify a capability against the installed artifact, not against documentation or a summary of it

**Date:** 2026-08-03
**Origin:** Determining whether the Claude Code VS Code extension honors `CLAUDE_CONFIG_DIR`. An assistant consulted first reported that the variable only relocated an internal lock file and that no per folder solution existed. A public issue reported that the extension reads a fixed `~/.claude-code-gui/` directory.
**Pattern:** Both claims were wrong for the artifact actually installed. Reading the extension bundle showed it resolving its config dir from `process.env.CLAUDE_CONFIG_DIR`, and exposing two settings, `claudeProcessWrapper` and `environmentVariables`, that no source mentioned. The installed version kept its config in `~/.claude/`, not the directory the issue named. Documentation lags, issue threads describe other versions, and a model's summary compounds both.
**Lesson:** Before concluding that a tool cannot do something, inspect what is installed: the package manifest for the settings and commands it really declares, and a grep of the bundle for the symbol in doubt. The manifest is a contract, a forum post is a snapshot of somebody else's version.
**Source:** https://github.com/anthropics/claude-code/issues/55621

---

## [HEU-002] A verifier that checks for the presence of files verifies nothing

**Date:** 2026-08-03
**Origin:** A setup check for per folder account routing reported every item green while one of the two protections was dead: the function reading the account identity looked in the wrong path, always returned an empty string, and the guard that compared it therefore never fired.
**Pattern:** Checks written as "does the expected file exist" pass as soon as installation looks complete, which is the state that needs no verification. The failure worth catching is a component present and not working, and presence checks are blind to it precisely there.
**Lesson:** Verify effective state by exercising the thing: run the component and assert its decision, read the value the protection compares, and assert the negative cases too. If a check cannot fail while the system is broken, it is documentation formatted as a test.
**Source:** [Confirmed by user - no external source]

---

## [HEU-003] A check that cannot distinguish "new" from "broken" must say so instead of choosing

**Date:** 2026-08-03
**Origin:** A verification block asserting that the editor had really used the wrapper. Right after installation there was no evidence yet, and the block reported a hard failure, which read as "the system is broken" when nothing was.
**Pattern:** Given an ambiguous signal, a check tends to be written toward one interpretation: alarming, which produces false alarms and trains the reader to ignore it, or reassuring, which produces the silent failure the check existed to catch.
**Lesson:** When a signal is genuinely ambiguous, report the ambiguity, name the single action that resolves it, and withhold the all clear until it is resolved. An intermediate state costs one line and preserves the meaning of both other states.
**Source:** [Confirmed by user - no external source]

---

## [HEU-004] `printenv VAR` cannot distinguish an unset variable from a failure

**Date:** 2026-08-03
**Origin:** A test probing which config dir a wrapper selected used `printenv CLAUDE_CONFIG_DIR` and reported folders as blocked when the wrapper had deliberately left the variable unset.
**Pattern:** `printenv` exits 1 when the requested variable does not exist. Any probe using the exit code to mean something else, such as "the wrapped program refused to run", conflates the two and reports a false failure for the legitimate empty case.
**Lesson:** To read an optional variable through a wrapper, use `sh -c 'printf "%s" "${VAR-}"'`, which always exits 0, so the exit code carries only the wrapper's decision. More generally, before reading a status code, confirm what the invoked program uses it for.
**Source:** https://www.gnu.org/software/coreutils/manual/html_node/printenv-invocation.html

---

## [HEU-005] `exit` inside a command substitution aborts only the subshell

**Date:** 2026-08-03
**Origin:** A helper resolving a name to a directory called `exit 1` on invalid input while being invoked as `dir="$(resolve "$1")"`. Invalid input printed the error and the caller proceeded with an empty variable.
**Pattern:** A command substitution runs in a subshell, so `exit` ends the subshell, not the script. Validation written inside a substitution reliably fails to stop the caller.
**Lesson:** A validating function returns a status and communicates its result through a variable, leaving the abort decision to the caller. In review, treat every `exit` inside `$(...)` as a bug.
**Source:** https://www.gnu.org/software/bash/manual/bash.html#Command-Substitution

---

## [HEU-006] A static marker may only assert static facts, with the guarantee supplied elsewhere

**Date:** 2026-08-03
**Origin:** Coloring an editor title bar to show which account a folder uses. The marker is a settings file read at window load, and it cannot observe the session it appears to describe.
**Pattern:** Indicators drift from what they claim to show, and the dangerous case is the marker that survives the death of the mechanism it advertises. The instinct is to make the marker smarter, which is usually impossible in the medium it lives in.
**Lesson:** Split the claim from the guarantee. Let the marker assert only what is statically true, and make the system fail closed so the state it implies cannot exist without it holding. Then add a command that reports whether the enforcing mechanism has actually run recently, so the death of the mechanism is observable rather than silent.
**Source:** [Confirmed by user - no external source]

---

## [HEU-007] When a user reports a mechanism broken, check first whether only its indicator is missing

**Date:** 2026-08-03
**Origin:** A report that per folder account routing did not work for subfolders. Routing already worked there, verified in the tool's own log against real editor sessions, including a subfolder the user had opened himself. What was absent in a subfolder was the colored title bar, because the editor reads folder settings only from the folder opened and never from a parent.
**Pattern:** Users report the symptom they can see. When a mechanism is invisible and its indicator is not, a missing indicator gets reported as a broken mechanism. Acting on the report as stated leads to rebuilding something that already works, while the real gap stays open.
**Lesson:** Reproduce the claim against the mechanism's own evidence before changing the mechanism. If it holds, the defect is in the indicator, and saying so with the evidence is part of the fix. A tool whose guarantee is invisible needs a cheap way to show itself in every context the user actually opens, or the guarantee will be doubted on schedule.
**Source:** [Confirmed by user - no external source]

---

## [HEU-008] Editor folder settings do not inherit from parent directories

**Date:** 2026-08-03
**Origin:** Marking work folders with a colored title bar through `.vscode/settings.json`. The color appeared at the repository root and nowhere below it.
**Pattern:** VS Code resolves workspace settings from the folder or workspace that was opened. There is no walk up the tree, so a subfolder opened directly inherits nothing from its parent. This is the opposite of the config resolution used by most linters and formatters, which does walk up, and the mismatch is what makes the behavior surprising.
**Lesson:** Any per folder editor convention has to be written into every folder that will be opened, or generated by a command. Do not design an editor level signal on an assumption of inheritance, and when a signal has to cover a tree, ship the generator rather than the instructions.
**Source:** https://code.visualstudio.com/docs/configure/settings
