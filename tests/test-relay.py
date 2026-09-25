#!/usr/bin/env python3
"""Tests for bin/claude-account-relay.

Every test runs against a throwaway HOME and a throwaway git repository. No real account is
ever touched: the HTTP call to api.anthropic.com is replaced by an injected function, and
where a real `claude` process would be launched, a stub script stands in for it. The only real
external tool exercised is `tmux` and `git`, both against names/paths made up for the test and
cleaned up afterwards.

    python3 tests/test-relay.py -v
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_loader = importlib.machinery.SourceFileLoader("car_relay", str(ROOT / "bin" / "claude-account-relay"))
spec = importlib.util.spec_from_file_location("car_relay", ROOT / "bin" / "claude-account-relay", loader=_loader)
car_relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(car_relay)

HAVE_TMUX = shutil.which("tmux") is not None


def run(cmd, cwd=None, **kw):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, **kw)


def make_repo(path):
    path.mkdir(parents=True, exist_ok=True)
    run(["git", "init", "-q"], cwd=path)
    run(["git", "config", "user.email", "t@t"], cwd=path)
    run(["git", "config", "user.name", "t"], cwd=path)
    (path / "README").write_text("x\n")
    run(["git", "add", "-A"], cwd=path)
    run(["git", "commit", "-q", "-m", "init"], cwd=path)


def make_profile(dirpath, email, token):
    dirpath.mkdir(parents=True, exist_ok=True)
    (dirpath / ".claude.json").write_text(json.dumps({"oauthAccount": {"emailAddress": email}}))
    (dirpath / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {"accessToken": token}}))


class Fixture:
    """One throwaway HOME, one throwaway repo, two profiles ('default' healthy-ish and 'alt'),
    a routes.conf routing the repo to 'alt' first."""

    def __init__(self):
        self.home = Path(tempfile.mkdtemp(prefix="car-relay-home-"))
        self.repo = Path(tempfile.mkdtemp(prefix="car-relay-repo-"))
        make_repo(self.repo)
        self.config_home = self.home / ".config" / "claude-account-router"
        self.config_home.mkdir(parents=True)
        self.default_dir = self.home / ".claude"
        self.alt_dir = self.home / ".claude-alt"
        make_profile(self.default_dir, "me@default.test", "tok-default")
        make_profile(self.alt_dir, "me@alt.test", "tok-alt")
        (self.config_home / "routes.conf").write_text(textwrap.dedent(f"""\
            profile default {self.default_dir}
            profile alt     {self.alt_dir}
            route   {self.repo}  alt
        """))

    def relay(self, fetch_usage=None, claude_bin=None):
        return car_relay.Relay(self.repo, config_home=self.config_home, home=self.home,
                                fetch_usage=fetch_usage, claude_bin=claude_bin)

    def cleanup(self):
        shutil.rmtree(self.home, ignore_errors=True)
        shutil.rmtree(self.repo, ignore_errors=True)


def usage_by_token(mapping):
    """mapping: token -> utilization (0..1). Returns a fetch_usage(token) function, injected in
    place of the real HTTP call, so tests never touch the network or a real account."""
    def fetch(token):
        u = mapping.get(token, 0.0)
        return {"five_hour": {"utilization": u, "resets_at": "2026-12-01T00:00:00+00:00"},
                "seven_day": {"utilization": 0.1, "resets_at": "2026-12-01T00:00:00+00:00"},
                "limits": []}
    return fetch


class TestProfilesAndRoutes(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.cleanup()

    def test_perfiles_declarados(self):
        r = self.fx.relay()
        perfiles = r.perfiles_declarados()
        self.assertEqual(set(perfiles), {"default", "alt"})
        self.assertEqual(perfiles["alt"], self.fx.alt_dir)

    def test_perfil_de_esta_ruta(self):
        r = self.fx.relay()
        self.assertEqual(r.perfil_de_esta_ruta(), "alt")

    def test_orden_por_defecto_pone_primero_la_ruta_declarada(self):
        r = self.fx.relay()
        orden = r.orden_por_defecto()
        self.assertEqual(orden[0], "alt")
        self.assertIn("default", orden)

    def test_repo_sin_ruta_declarada_no_falla(self):
        otro = Path(tempfile.mkdtemp(prefix="car-relay-norte-"))
        try:
            make_repo(otro)
            r = car_relay.Relay(otro, config_home=self.fx.config_home, home=self.fx.home)
            self.assertIsNone(r.perfil_de_esta_ruta())
            self.assertIn("default", r.orden_por_defecto())
        finally:
            shutil.rmtree(otro, ignore_errors=True)


class TestUsage(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.cleanup()

    def test_ventana_al_100_bloquea(self):
        r = self.fx.relay(fetch_usage=usage_by_token({"tok-alt": 1.0}))
        u = r.uso_de(self.fx.alt_dir)
        self.assertTrue(u["bloqueada"])
        self.assertIsNone(u["error"])

    def test_ventana_baja_no_bloquea(self):
        r = self.fx.relay(fetch_usage=usage_by_token({"tok-alt": 0.42}))
        u = r.uso_de(self.fx.alt_dir)
        self.assertFalse(u["bloqueada"])

    def test_sin_credencial_no_lanza_y_marca_error(self):
        vacio = self.fx.home / ".claude-vacio"
        vacio.mkdir()
        r = self.fx.relay(fetch_usage=usage_by_token({}))
        u = r.uso_de(vacio)
        self.assertIsNone(u["bloqueada"])
        self.assertEqual(u["error"], "sin credencial")

    def test_resumen_de_uso_dice_blocked_o_headroom(self):
        r = self.fx.relay()
        self.assertTrue(r.resumen_de_uso({"error": None, "bloqueada": True, "ventanas": []}).startswith("BLOCKED"))
        self.assertTrue(r.resumen_de_uso({"error": None, "bloqueada": False, "ventanas": []}).startswith("has headroom"))


class TestWip(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.cleanup()

    def test_repo_limpio_no_tiene_nada_que_guardar(self):
        r = self.fx.relay()
        self.assertEqual(r.worktrees_con_cambios(), [])
        self.assertEqual(r.guardar_wip("motivo de prueba"), [])

    def test_cambios_sin_commitear_se_guardan_como_wip(self):
        (self.fx.repo / "nuevo.txt").write_text("contenido de prueba\n")
        r = self.fx.relay()
        antes = r.worktrees_con_cambios()
        self.assertEqual(len(antes), 1)
        guardados = r.guardar_wip("motivo de prueba")
        self.assertEqual(len(guardados), 1)
        self.assertIn("->", guardados[0])
        # El árbol queda limpio, y el archivo sigue estando: se commiteó, no se perdió.
        self.assertEqual(r.worktrees_con_cambios(), [])
        log = run(["git", "log", "-1", "--pretty=%s"], cwd=self.fx.repo).stdout
        self.assertIn("WIP", log)
        self.assertTrue((self.fx.repo / "nuevo.txt").exists())


@unittest.skipUnless(HAVE_TMUX, "tmux no está instalado en esta máquina")
class TestRelieveEndToEnd(unittest.TestCase):
    """El camino completo: cuenta bloqueada -> WIP -> tmux con --resume --fork-session -> cierre
    de la ventana relevada. Usa un `claude` de mentira (un script que anota sus argumentos) para
    no tocar ninguna cuenta real."""

    def setUp(self):
        self.fx = Fixture()
        self.sid = str(uuid.uuid4())
        # Sesión "de editor" de mentira: escribe la transcripción que sesion_de_editor()/sesion_mas_nueva()
        # necesitan, directamente en la carpeta del perfil actual (alt), simulando que ya existía.
        self.relay = self.fx.relay(fetch_usage=usage_by_token({"tok-alt": 1.0, "tok-default": 0.05}))
        proj_dir = self.fx.alt_dir / "projects" / self.relay.slug
        proj_dir.mkdir(parents=True)
        transcript = proj_dir / f"{self.sid}.jsonl"
        transcript.write_text(json.dumps({
            "type": "assistant", "timestamp": "2026-09-25T10:00:00Z",
            "message": {"content": [{"type": "text", "text": "trabajando en algo"}]},
        }) + "\n")

        # Estado: cree que esa sesión "de editor" (sin tmux propio todavía) es la que trabaja.
        # Se logra escribiendo el estado sin 'relevo', y monkeypatcheando sesion_de_editor para
        # devolver esa sesión de mentira sin depender de /proc de verdad.
        self.relay.sesion_de_editor = lambda: {
            "origen": "editor", "pid": os.getpid(), "carpeta": str(self.fx.alt_dir), "sesion": self.sid}

        # El destino de la captura va escrito LITERAL adentro del script de mentira, nunca por una
        # variable de entorno: medido en esta misma sesión que `tmux new-session`, contra un
        # servidor de tmux que ya estaba corriendo (como en cualquier máquina con otras ventanas
        # abiertas), NO hereda una variable recién exportada en el proceso que lo invoca — el hijo
        # la ve vacía. Es la razón real por la que esta prueba fallaba en su primera versión.
        self.capture = self.fx.home / "captured-args.txt"
        self.stub = self.fx.home / "claude-stub.sh"
        self.stub.write_text(textwrap.dedent(f"""\
            #!/usr/bin/env bash
            echo "$@" > {self.capture}
            printf '\\xe2\\x9d\\xafready\\n'
            sleep 30
        """))
        self.stub.chmod(0o755)
        self.relay._claude_bin = str(self.stub)

    def tearDown(self):
        for s in self.relay.tmux("list-sessions", "-F", "#S").stdout.split():
            if s.startswith(self.relay.tmux_name):
                self.relay.tmux("kill-session", "-t", "=" + s)
        self.fx.cleanup()

    def test_dry_run_no_lanza_nada(self):
        (self.fx.repo / "sin-commitear.txt").write_text("x\n")
        self.relay.pasada(["alt", "default"], sin_lanzar=True)
        self.assertFalse(self.capture.exists())
        # El dry-run no debe haber tocado el árbol: sigue sucio.
        self.assertEqual(len(self.relay.worktrees_con_cambios()), 1)

    def test_cuenta_bloqueada_releva_de_verdad(self):
        (self.fx.repo / "sin-commitear.txt").write_text("x\n")
        self.relay.pasada(["alt", "default"], sin_lanzar=False, espera_arranque=5)
        self.assertTrue(self.capture.exists(), "el `claude` de mentira debería haber corrido")
        args = self.capture.read_text()
        self.assertIn(f"--resume {self.sid}", args)
        self.assertIn("--fork-session", args)
        # El WIP se guardó: el árbol queda limpio.
        self.assertEqual(self.relay.worktrees_con_cambios(), [])
        # Y el estado registra el relevo, hacia la cuenta con cupo.
        estado = self.relay.leer_estado()
        self.assertEqual(estado["relevo"]["perfil"], "default")
        self.assertTrue(self.relay.hay_tmux(self.relay.tmux_name))

    def test_ninguna_cuenta_con_cupo_no_lanza_y_lo_dice(self):
        self.relay._fetch_usage = usage_by_token({"tok-alt": 1.0, "tok-default": 1.0})
        self.relay.pasada(["alt", "default"], sin_lanzar=False, espera_arranque=1)
        self.assertFalse(self.capture.exists())
        estado = self.relay.leer_estado()
        self.assertIn("esperar_hasta", estado)


if __name__ == "__main__":
    unittest.main()
