"""Lecture du WAV produit par l'app Swift.

Volontairement sans import mlx : testable sans charger le modèle.
"""
import wave

import numpy as np

TAUX = 16_000
CANAUX = 1
OCTETS_PAR_ECHANTILLON = 2


def charger_wav(chemin):
    """Lit un WAV PCM 16 bits mono 16 kHz et rend un Float32 dans [-1, 1].

    On évite délibérément le chargeur de mlx-whisper : il appelle `ffmpeg` en
    sous-process, ce qui ajoute une dépendance système absente du PATH d'un
    LaunchAgent, plus un spawn de process à chaque dictée. Le format est connu
    puisque c'est nous qui l'écrivons.
    """
    with wave.open(str(chemin), "rb") as w:
        canaux, largeur, taux = w.getnchannels(), w.getsampwidth(), w.getframerate()
        if (canaux, largeur, taux) != (CANAUX, OCTETS_PAR_ECHANTILLON, TAUX):
            raise ValueError(
                f"WAV inattendu : {canaux} canal/canaux, {largeur * 8} bits, "
                f"{taux} Hz — attendu {CANAUX}/{OCTETS_PAR_ECHANTILLON * 8}/{TAUX}"
            )
        brut = w.readframes(w.getnframes())
    return np.frombuffer(brut, dtype="<i2").astype(np.float32) / 32768.0
