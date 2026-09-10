"""Worker local résident. Une commande JSON identifiée par ligne, une réponse.

Le modèle doit déjà être présent : aucun téléchargement au runtime.
"""
import time
DEBUT = time.perf_counter()
import json
import os
import sys
import signal


def terminer(_signal, _frame):
    raise SystemExit(0)


signal.signal(signal.SIGTERM, terminer)

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
import mlx.core as mx
import mlx_whisper
import numpy as np
from mlx_whisper.tokenizer import get_tokenizer

from audio import charger_wav, preparer_parole
from filtres import nettoyer, vocabulaire
from moteur import modele_local, transcrire_limite

LANGUE = 'fr'
VOCABULAIRE = os.path.expanduser('~/.config/dictee/vocabulaire.txt')


def repondre(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def memoire():
    mx.synchronize()
    return {key: round(fn() / 2**20, 1) for key, fn in (
        ('active_mib', mx.get_active_memory), ('cache_mib', mx.get_cache_memory),
        ('peak_mib', mx.get_peak_memory))}


def prompt_actuel():
    prompt, avertissement = vocabulaire(VOCABULAIRE, encoder=tokenizer.encode)
    if avertissement:
        print(avertissement, file=sys.stderr, flush=True)
    return prompt


def options():
    return dict(path_or_hf_repo=model, language=LANGUE, initial_prompt=prompt_actuel() or None,
                condition_on_previous_text=False, verbose=None)


def chauffer():
    debut = time.perf_counter()
    mlx_whisper.transcribe(np.zeros(16000, dtype=np.float32), **options(), temperature=0.0)
    return round(time.perf_counter() - debut, 3)


def main():
    global model, tokenizer
    try:
        imports_sec = time.perf_counter() - DEBUT
        model = modele_local()
        tokenizer = get_tokenizer(True, num_languages=100, language=LANGUE, task='transcribe')
        mx.set_cache_limit(int(os.environ.get('DICTEE_CACHE_MB', '512')) * 2**20)
        warmup_sec = chauffer()
        repondre({'ready': True, 'metrics': {'imports_sec': round(imports_sec, 3),
                  'warmup_sec': warmup_sec, 'startup_sec': round(time.perf_counter()-DEBUT, 3),
                  **memoire()}})
    except Exception as e:
        repondre({'fatal': str(e)[:300]})
        return 1

    for ligne in sys.stdin:
        demande = {}
        try:
            demande = json.loads(ligne)
            identifiant = demande['id']
            commande = demande['cmd']
            debut = time.perf_counter()
            if commande == 'warmup':
                sec = chauffer()
                repondre({'id': identifiant, 'done': commande,
                          'metrics': {'warmup_sec': sec, **memoire()}})
            elif commande == 'purge':
                mx.clear_cache()
                repondre({'id': identifiant, 'done': commande, 'metrics': memoire()})
            elif commande == 'transcribe':
                mx.reset_peak_memory()
                audio, stats = preparer_parole(charger_wav(demande['path']))
                preparation_sec = time.perf_counter() - debut
                texte, tentatives, inference_sec = '', 0, 0.0
                if len(audio):
                    t = time.perf_counter()
                    resultat, tentatives = transcrire_limite(mlx_whisper.transcribe, audio, options())
                    inference_sec = time.perf_counter() - t
                    texte = nettoyer(s['text'] for s in resultat['segments'])
                    del resultat
                del audio
                repondre({'id': identifiant, 'text': texte,
                          'sec': round(time.perf_counter() - debut, 3),
                          'metrics': {**stats, 'preparation_sec': round(preparation_sec, 3),
                                      'inference_sec': round(inference_sec, 3),
                                      'attempts': tentatives, **memoire()}})
            else:
                raise ValueError('commande inconnue')
        except Exception as e:
            repondre({'id': demande.get('id') if isinstance(demande, dict) else None,
                      'error': str(e)[:300]})
    return 0


if __name__ == '__main__':
    sys.exit(main())
