"""Contrats locaux : pas de téléchargement ni de modèle pour ces tests."""
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from moteur import modele_local, transcrire_limite
from audio import preparer_parole, charger_wav
from filtres import vocabulaire
from mlx_whisper.tokenizer import get_tokenizer


def test_modele_absent_ne_telecharge_pas(tmp_path):
    with pytest.raises(FileNotFoundError, match="local"):
        modele_local(tmp_path)


def test_modele_resout_la_revision_cachee(tmp_path):
    repo = tmp_path / 'models--mlx-community--whisper-large-v3-turbo'
    (repo / 'refs').mkdir(parents=True)
    (repo / 'refs/main').write_text('abc123')
    snap = repo / 'snapshots/abc123'
    snap.mkdir(parents=True)
    (snap / 'config.json').write_text('{}')
    (snap / 'weights.safetensors').write_bytes(b'cached')
    assert modele_local(tmp_path) == str(snap)


def test_aucune_voix_aucun_audio_a_transcrire():
    audio, stats = preparer_parole(np.zeros(32000, dtype=np.float32))
    assert len(audio) == 0
    assert stats['speech_sec'] == 0


def test_voix_gardee_et_long_silence_retire(wav_parole):
    voix = charger_wav(wav_parole)
    source = np.concatenate([np.zeros(48000), voix, np.zeros(48000)]).astype(np.float32)
    audio, stats = preparer_parole(source)
    assert stats['speech_sec'] > 0.4
    assert len(voix) * 0.8 < len(audio) < len(source) - 64000
    assert np.max(np.abs(audio)) == np.max(np.abs(voix))


def test_deux_phrases_separees_par_un_long_silence_sont_gardees(wav_parole):
    voix = charger_wav(wav_parole)
    source = np.concatenate([voix, np.zeros(64000), voix]).astype(np.float32)
    audio, stats = preparer_parole(source)
    assert len(audio) > 1.5 * len(voix)
    assert len(audio) < len(source) - 32000


def test_vocabulaire_limite_les_vrais_tokens_et_se_recharge(tmp_path):
    f = tmp_path / 'v.txt'
    f.write_text('\n'.join(['anticonstitutionnellement-' * 8] * 60))
    encode = get_tokenizer(True, language='fr').encode
    prompt, warning = vocabulaire(f, encoder=encode)
    assert len(encode(' ' + prompt)) <= 223
    assert warning
    f.write_text('LinkQuiver')
    assert 'LinkQuiver' in vocabulaire(f, encoder=encode)[0]


def test_decodage_borne_et_pas_de_retry_si_bon():
    def decode(audio, **options):
        assert options['temperature'] == 0.0
        return {'segments': [{'text':'bonjour', 'avg_logprob': -0.2, 'compression_ratio': 1.1}]}
    result, attempts = transcrire_limite(decode, np.zeros(100), {})
    assert result['segments'][0]['text'] == 'bonjour'
    assert attempts == 1


def test_decodage_difficile_deux_passes_maximum():
    calls = []
    def decode(audio, **options):
        calls.append(options['temperature'])
        return {'segments': [{'text':'bonjour', 'avg_logprob': -2, 'compression_ratio': 3}]}
    _, attempts = transcrire_limite(decode, np.zeros(100), {})
    assert attempts == 2
    assert calls == [0.0, 0.2]


def test_fausse_reconnaissance_ne_remplace_pas_une_meilleure_premiere_passe():
    def decode(audio, **options):
        if options['temperature'] == 0:
            return {'segments': [{'text': 'le bon texte', 'avg_logprob': -1.1}]}
        return {'segments': [{'text': 'texte moins fiable', 'avg_logprob': -2.0}]}
    result, attempts = transcrire_limite(decode, np.zeros(100), {})
    assert result['segments'][0]['text'] == 'le bon texte'
    assert attempts == 2


def test_installation_reutilise_le_cache_sans_appel_reseau(tmp_path, monkeypatch):
    import huggingface_hub
    import huggingface_hub.constants
    from installer_modele import installer
    repo = tmp_path / 'models--mlx-community--whisper-large-v3-turbo'
    (repo / 'refs').mkdir(parents=True)
    (repo / 'refs/main').write_text('cached')
    snap = repo / 'snapshots/cached'
    snap.mkdir(parents=True)
    (snap / 'config.json').write_text('{}')
    (snap / 'weights.safetensors').write_bytes(b'cached')
    monkeypatch.setattr(huggingface_hub.constants, 'HF_HUB_CACHE', str(tmp_path))
    def interdit(*args, **kwargs):
        raise AssertionError('un modèle existant ne doit pas être téléchargé')
    monkeypatch.setattr(huggingface_hub, 'snapshot_download', interdit)
    assert installer() == str(snap)
