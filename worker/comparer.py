"""Compare un même WAV local (mono, PCM 16 bits, 16 kHz), sans le modifier."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from moteur import MODELES


def comparer(audio, modele, repetitions=2, timeout=240):
    commandes = ''.join(json.dumps({'id': str(i), 'cmd': 'transcribe', 'path': str(audio)}) + '\n'
                         for i in range(repetitions))
    process = subprocess.run(
        [sys.executable, str(Path(__file__).with_name('transcribe.py'))],
        input=commandes, capture_output=True, text=True, timeout=timeout,
        env={**os.environ, 'DICTEE_MODEL': modele, 'HF_HUB_OFFLINE': '1'})
    lignes = [json.loads(l) for l in process.stdout.splitlines() if l.strip()]
    fatal = next((l['fatal'] for l in lignes if 'fatal' in l), None)
    if process.returncode or fatal:
        raise RuntimeError(fatal or process.stderr[-1500:] or f'worker arrêté : {process.returncode}')
    pret = next((l for l in lignes if l.get('ready')), None)
    resultats = [l for l in lignes if 'id' in l]
    if pret is None or [l['id'] for l in resultats] != [str(i) for i in range(repetitions)]:
        raise RuntimeError('réponses du worker incomplètes')
    if any('error' in l for l in resultats):
        raise RuntimeError(next(l['error'] for l in resultats if 'error' in l))
    return {'modele': modele, 'demarrage': pret.get('metrics', {}), 'transcriptions': resultats}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('audio', type=Path)
    parser.add_argument('--modeles', nargs='+', choices=list(MODELES), default=['parakeet', 'cohere'])
    parser.add_argument('--repetitions', type=int, choices=range(1, 11), default=2)
    args = parser.parse_args()
    if not args.audio.is_file():
        parser.error('fichier audio introuvable')
    succes = True
    for modele in args.modeles:
        print(f'Comparaison : {modele}', file=sys.stderr, flush=True)
        try:
            resultat = comparer(args.audio.resolve(), modele, args.repetitions)
        except (RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
            resultat = {'modele': modele, 'erreur': str(exc)}
            succes = False
        print(json.dumps(resultat, ensure_ascii=False), flush=True)
    return 0 if succes else 1


if __name__ == '__main__':
    sys.exit(main())
