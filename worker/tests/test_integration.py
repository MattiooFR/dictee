"""Vrai worker, vrai modèle local, réponses bornées dans le temps."""
import json
import os
import queue
import subprocess
import sys
import threading
import uuid
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parents[1]


def lire(worker, timeout=60):
    try:
        ligne = worker.reponses.get(timeout=timeout)
    except queue.Empty:
        pytest.fail('worker sans réponse dans le délai imparti')
    assert ligne, 'worker mort avant réponse'
    return json.loads(ligne)


@pytest.fixture(scope='module')
def worker():
    p = subprocess.Popen([sys.executable, str(RACINE / 'transcribe.py')], cwd=RACINE,
                         env={**os.environ, 'HF_HUB_OFFLINE': '1'},
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    p.reponses = queue.Queue()
    def drainer():
        for line in p.stdout:
            p.reponses.put(line)
        p.reponses.put('')
    threading.Thread(target=drainer, daemon=True).start()
    try:
        r = lire(p)
        assert r.get('ready') is True, r
        assert r['metrics']['active_mib'] > 100
        yield p
    finally:
        p.stdin.close()
        try:
            p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            p.kill(); p.wait(timeout=3)
        p.stdout.close()


def demander(worker, chemin=None, cmd='transcribe'):
    id_ = str(uuid.uuid4())
    worker.stdin.write(json.dumps({'id': id_, 'cmd': cmd, 'path': str(chemin)}) + '\n')
    worker.stdin.flush()
    r = lire(worker)
    assert r['id'] == id_
    return r


@pytest.mark.lent
def test_la_parole_est_transcrite(worker, wav_parole):
    r = demander(worker, wav_parole)
    assert 'bonjour' in r['text'].lower()
    assert r['sec'] < 15
    assert r['metrics']['attempts'] in (1, 2)
    assert r['metrics']['speech_sec'] > 0.4


@pytest.mark.lent
def test_le_silence_ne_produit_aucun_texte(worker, wav_silence):
    r = demander(worker, wav_silence)
    assert r['text'] == ''
    assert r['metrics']['attempts'] == 0


@pytest.mark.lent
def test_purge_reveil_et_nouvelle_dictee(worker, wav_parole):
    purge = demander(worker, cmd='purge')
    assert purge['metrics']['cache_mib'] == 0
    assert purge['metrics']['active_mib'] > 100
    warm = demander(worker, cmd='warmup')
    assert warm['done'] == 'warmup'
    assert warm['metrics']['cache_mib'] < 544  # allocations arrondies / plafond souple
    r = demander(worker, wav_parole)
    assert 'bonjour' in r['text'].lower()


@pytest.mark.lent
def test_erreur_identifiee_puis_reprise(worker, wav_parole):
    r = demander(worker, '/tmp/fichier-dictee-inexistant.wav')
    assert 'error' in r
    assert 'bonjour' in demander(worker, wav_parole)['text'].lower()
