"""Test d'intégration : lance le vrai worker sur de vrais WAV.

Lent (~30 s : chargement du modèle). Lancer avec :
    .venv/bin/python -m pytest worker/tests/test_integration.py -q -m lent
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def worker():
    p = subprocess.Popen(
        [sys.executable, str(RACINE / "transcribe.py")],
        cwd=RACINE,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert json.loads(p.stdout.readline())["ready"] is True
    yield p
    p.stdin.close()
    p.terminate()


def demander(worker, chemin):
    worker.stdin.write(f"{chemin}\n")
    worker.stdin.flush()
    return json.loads(worker.stdout.readline())


@pytest.mark.lent
def test_la_parole_est_transcrite(worker, wav_parole):
    r = demander(worker, wav_parole)
    assert "bonjour" in r["text"].lower()
    assert r["sec"] < 15


@pytest.mark.lent
def test_le_silence_ne_produit_aucun_texte(worker, wav_silence):
    assert demander(worker, wav_silence)["text"] == ""
