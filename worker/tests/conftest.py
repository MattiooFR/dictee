import subprocess
import wave
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"
PHRASE = "Bonjour, ceci est un test de transcription en français."


@pytest.fixture(scope="session")
def wav_parole():
    FIXTURES.mkdir(exist_ok=True)
    wav = FIXTURES / "parole.wav"
    if not wav.exists():
        aiff = FIXTURES / "parole.aiff"
        subprocess.run(["say", "-o", str(aiff), PHRASE], check=True)
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)],
            check=True,
        )
        aiff.unlink()
    return wav


@pytest.fixture(scope="session")
def wav_silence():
    FIXTURES.mkdir(exist_ok=True)
    wav = FIXTURES / "silence.wav"
    if not wav.exists():
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16_000)
            w.writeframes(b"\x00\x00" * 16_000 * 2)
    return wav
