# RULES: claude-account-router

> Operational rules for AI agents working in this repository.
> Referenced from MASTER-SPEC §8.

---

## Scope

Every change to `bin/`, `lib/`, or `install.sh`. Documentation only changes are exempt from rule 1 and rule 2, and bound by all the others.

---

## Rules

1. **Run the tests before claiming a change works.** `./tests/test-routing.sh` must end with zero failures. A change to routing or to the identity check without a test covering the new behavior is incomplete.

2. **A new code path may never end in a launch on an unverified account.** When adding a branch, answer explicitly: what happens when the identity cannot be read here? The only acceptable answers are "it blocks" or "there is no session yet, so the launch is a first login". Anything else violates MASTER-SPEC §4.1.

3. **Never add a second implementation of the identity resolution.** Call `car_account_email`. If it needs to change, it changes in `lib/common.sh` and nowhere else. This rule exists because a duplicate that read the wrong path made the account check pass while checking nothing.

4. **No hardcoded folders, domains, emails, or account names.** Everything comes from `routes.conf`. The repository ships `examples/routes.conf.example` with placeholder values only.

5. **No credentials in code, tests, or fixtures.** Test fixtures write an identity email and a placeholder file, never a token shaped string. Nothing in this project may read, print, or copy a token.

6. **`printenv VAR` is banned for detecting a value.** It exits 1 when the variable is unset, which is indistinguishable from a command failing. Use `sh -c 'printf "%s" "${VAR-}"'`, whose exit code reflects only the wrapped command.

7. **Do not use `exit` inside a command substitution to abort the caller.** It ends the subshell only, and the caller continues with an empty variable. Return a status and let the caller decide.

8. **The verifier reports what it measured, not what it assumes.** A block that cannot distinguish "just installed" from "broken" says so and asks for the action that settles it, rather than picking the reassuring interpretation. Never let the summary reach the all clear state on an unmeasured claim.

9. **English, everywhere, including comments.** The project is a public tool.

10. **No em dashes.** Use a comma, a colon, or a new sentence.

11. **Comments explain why, never what.** A comment restating the line above it is noise. A comment recording a trap already paid for is the reason the file is trustworthy.
