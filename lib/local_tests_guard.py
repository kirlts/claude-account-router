"""Refuses test runs on this machine for repositories whose tests run in the cloud.

The rule was written down ("no test of the chain runs on the notebook", Devalis, 2026-10-26) and on
2026-10-27 at 12:28 the notebook was at load 57 with `node --test` batteries and headless browsers
from two agents, the same load that had cut the deploy chain's SSH at 11:45. A rule an agent has to
remember is not a path; the refusal runs before the command, in every session of every profile.

Which repositories, and what to use instead, is the table below. A repository enters the table only
once its cloud path exists, so the refusal never leaves work without a way to test.

Judged from the command text, never by running anything.
"""
import os
import re
import shlex

HOME = os.path.expanduser("~")

# repository root -> the command that runs its tests in the cloud
CLOUD_TESTS = {
    os.path.join(HOME, "devalis"):
        "push the branch and run `infra/servidor-de-despliegue/probar.sh <branch>` from the repository: "
        "it tests the branch against `desarrollo` on a harness machine of devalis-ci-runners",
}

SHELL_WORDS = {"sudo", "doas", "env", "nohup", "setsid", "exec", "command", "time", "timeout", "nice",
               "ionice", "xargs", "systemd-run", "npx", "bunx"}
OPERATORS = {"&&", "||", ";", "|", "&", "\n", "(", ")", "|&", ";;"}

MESSAGE = (
    "Blocked: tests of {repo} do not run on this machine ({why}).\n"
    "Instead: {how}.\n"
    "Editing, `node --check`, type checks and builds stay local; test batteries, test files and browser tests go to the cloud."
)


def _tokens(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        return list(lexer)
    except ValueError:
        return command.split()


def _segments(command):
    segs, cur = [], []
    for tok in _tokens(command):
        if tok in OPERATORS or set(tok) <= set(";&|()"):
            if cur:
                segs.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        segs.append(cur)
    return segs


def _strip(words):
    while words:
        w = words[0]
        if w in SHELL_WORDS or re.fullmatch(r"[A-Za-z_]\w*=.*", w):
            words = words[1:]
        elif w.startswith("-") and w != "-":
            # options of the wrapper (`systemd-run --user --scope -p X`, `timeout -s KILL 5`)
            words = words[1:]
            if words and (re.fullmatch(r"\d+(\.\d+)?[smhd]?", words[0]) or "=" in words[0] and not words[0].startswith("-")):
                words = words[1:]
        elif re.fullmatch(r"\d+(\.\d+)?[smhd]?", w):
            words = words[1:]
        elif w == "--":
            words = words[1:]
        else:
            break
    return words


TEST_FILE = re.compile(r"(\.test\.[cm]?[jt]sx?|\.spec\.[cm]?[jt]sx?|(^|/)test-[\w-]+\.[cm]?js)$")


def runs_tests(words):
    """The reason a simple command runs tests, or None."""
    words = _strip(words)
    if not words:
        return None
    name = os.path.basename(words[0])
    rest = words[1:]
    if name in ("npm", "pnpm", "yarn", "bun"):
        verbs, skip = [], False
        for w in rest:
            if skip:
                skip = False
            elif w in ("--prefix", "-C", "--cwd", "--dir", "-w", "--workspace", "--filter"):
                skip = True
            elif not w.startswith("-"):
                verbs.append(w)
        if verbs and (verbs[0] in ("test", "t", "tst") or verbs[0] in ("run", "run-script") and len(verbs) > 1
                      and re.match(r"test(:|$)", verbs[1])):
            return f"`{name} {' '.join(verbs[:2])}`"
        if verbs and verbs[0] in ("exec", "x", "dlx") and len(verbs) > 1:
            return runs_tests(verbs[1:])
        return None
    if name in ("vitest", "jest", "mocha", "ava", "tap"):
        if name == "vitest" and rest[:1] and rest[0] in ("--version", "-v"):
            return None
        return f"`{name}`"
    if name == "playwright" and "test" in rest:
        return "`playwright test`"
    if name == "deno" and rest[:1] == ["test"]:
        return "`deno test`"
    if name == "node" or name.startswith("node") and re.fullmatch(r"node[\d.]*", name):
        if "--check" in rest or "-c" in rest:
            return None  # a syntax check executes nothing
        if any(w == "--test" or w.startswith("--test=") or w.startswith("--test-") for w in rest):
            return "`node --test`"
        files = [w for w in rest if not w.startswith("-")]
        if files and TEST_FILE.search(files[0]):
            return f"`node {files[0]}`"
        if files and files[0].endswith("pila-propia.mjs") and "--correr" in rest:
            return "`pila-propia.mjs --correr`"
    return None


def _repo_of(path, cwd):
    if not path:
        return None
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        path = os.path.join(cwd or os.getcwd(), path)
    path = os.path.normpath(path)
    for root in CLOUD_TESTS:
        if path == root or path.startswith(root + os.sep):
            return root
    return None


def judge(event):
    """None when allowed, or (repository, reason)."""
    if (event.get("tool_name") or "") != "Bash":
        return None
    command = (event.get("tool_input") or {}).get("command") or ""
    cwd = event.get("cwd") or ""
    where = _repo_of(cwd, cwd)
    for words in _segments(command):
        stripped = _strip(words)
        if stripped and os.path.basename(stripped[0]) in ("cd", "pushd") and len(stripped) > 1:
            where = _repo_of(stripped[1], cwd) or where
            cwd = os.path.expanduser(stripped[1]) if os.path.isabs(os.path.expanduser(stripped[1])) else cwd
            continue
        reason = runs_tests(words)
        if not reason:
            continue
        # npm --prefix X, git -C style -C X, or any path argument inside a guarded repository
        target = where
        for w in words:
            target = target or _repo_of(w, cwd) if ("/" in w or w.startswith("~")) else target
        if target:
            return target, reason
    return None


def refuse(event):
    """(exit status, message): (2, text) to block, (0, "") to allow."""
    found = judge(event)
    if not found:
        return 0, ""
    root, why = found
    return 2, MESSAGE.format(repo=os.path.basename(root), why=why, how=CLOUD_TESTS[root])
