"""Transcripteur résident : charge mlx-whisper une fois, transcrit à la demande.

Un chemin .wav par ligne sur stdin → une ligne JSON sur stdout.
Le modèle reste en mémoire : une dictée de 30 s revient en ~2 s au lieu de ~20 s
s'il fallait relancer le process à chaque fois.
"""
import json
import os
import sys
import time

import mlx_whisper
import numpy as np

from audio import charger_wav
from filtres import nettoyer, vocabulaire

MODELE = "mlx-community/whisper-large-v3-turbo"
LANGUE = "fr"
CHEMIN_VOCABULAIRE = os.path.expanduser("~/.config/dictee/vocabulaire.txt")


def journal(message):
    print(message, file=sys.stderr, flush=True)


prompt, avertissement = vocabulaire(CHEMIN_VOCABULAIRE)
if avertissement:
    journal(avertissement)

# Premier appel = téléchargement et compilation. On le paie au démarrage,
# pas sur la première dictée.
mlx_whisper.transcribe(
    np.zeros(16_000, dtype=np.float32),
    path_or_hf_repo=MODELE,
    language=LANGUE,
    verbose=False,
)
print(json.dumps({"ready": True}), flush=True)

for ligne in sys.stdin:
    chemin = ligne.strip()
    if not chemin:
        continue
    debut = time.time()
    try:
        resultat = mlx_whisper.transcribe(
            charger_wav(chemin),
            path_or_hf_repo=MODELE,
            language=LANGUE,
            initial_prompt=prompt or None,
            condition_on_previous_text=False,
            verbose=False,
        )
        texte = nettoyer(s["text"] for s in resultat["segments"])
        print(json.dumps({"text": texte, "sec": round(time.time() - debut, 1)}), flush=True)
    except Exception as e:  # noqa: BLE001 — l'erreur doit remonter à l'appelant
        print(json.dumps({"error": str(e)[:300]}), flush=True)
