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


def preparer_parole(audio):
    """VAD WebRTC, marges de 250 ms, ne retire que les longues pauses.

    Mode 1 conservateur pour conserver les débuts/fins de mots. Les pauses
    courtes restent intactes ; les blocs conservés ne sont jamais réordonnés.
    """
    import webrtcvad
    audio = np.asarray(audio, dtype=np.float32)
    taille = 320  # 20 ms à 16 kHz
    vad = webrtcvad.Vad(1)
    pcm = (np.clip(audio, -1, 1) * 32767).astype('<i2')
    voix = []
    for i in range(0, len(pcm), taille):
        frame = pcm[i:i + taille]
        if len(frame) < taille:
            frame = np.pad(frame, (0, taille - len(frame)))
        # Écarte le silence numérique, même dans le hangover du VAD.
        parlee = vad.is_speech(frame.tobytes(), TAUX)
        if parlee and np.max(np.abs(frame.astype(np.int32))) > 30:
            voix.append(i)
    stats = {'input_sec': round(len(audio) / TAUX, 3),
             'speech_sec': round(len(voix) * 0.02, 3), 'kept_sec': 0.0}
    if len(voix) < 10:  # au moins 200 ms détectées, en complément du garde Swift
        return np.empty(0, dtype=np.float32), stats
    marge = 4000
    blocs = []
    debut, fin = max(0, voix[0] - marge), min(len(audio), voix[0] + taille + marge)
    for i in voix[1:]:
        a, b = max(0, i - marge), min(len(audio), i + taille + marge)
        if a - fin <= TAUX // 2:
            fin = max(fin, b)
        else:
            blocs.append(audio[debut:fin])
            debut, fin = a, b
    blocs.append(audio[debut:fin])
    garde = np.concatenate(blocs)
    stats['kept_sec'] = round(len(garde) / TAUX, 3)
    return garde, stats
