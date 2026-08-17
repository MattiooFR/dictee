import sys
import wave
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from audio import charger_wav


def ecrire(chemin, echantillons, canaux=1, largeur=2, taux=16_000):
    with wave.open(str(chemin), "wb") as w:
        w.setnchannels(canaux)
        w.setsampwidth(largeur)
        w.setframerate(taux)
        w.writeframes(echantillons.astype("<i2").tobytes())


def test_charge_un_wav_conforme(tmp_path):
    f = tmp_path / "a.wav"
    ecrire(f, np.array([0, 16384, -16384, 32767, -32768]))
    e = charger_wav(f)
    assert e.dtype == np.float32
    assert len(e) == 5
    assert e[0] == 0
    assert abs(e[1] - 0.5) < 1e-4
    assert -1.0 <= e.min() and e.max() <= 1.0


def test_le_silence_donne_des_zeros(tmp_path):
    f = tmp_path / "silence.wav"
    ecrire(f, np.zeros(16_000))
    assert np.all(charger_wav(f) == 0)


@pytest.mark.parametrize(
    "canaux,largeur,taux",
    [(2, 2, 16_000), (1, 1, 16_000), (1, 2, 44_100)],
)
def test_un_format_inattendu_est_refuse_explicitement(tmp_path, canaux, largeur, taux):
    f = tmp_path / "mauvais.wav"
    ecrire(f, np.zeros(1000), canaux=canaux, largeur=largeur, taux=taux)
    with pytest.raises(ValueError, match="WAV inattendu"):
        charger_wav(f)


def test_le_wav_de_la_fixture_parole_se_charge(wav_parole):
    e = charger_wav(wav_parole)
    assert len(e) > 16_000          # plus d'une seconde
    assert np.abs(e).max() > 0.05   # il y a bien du signal
