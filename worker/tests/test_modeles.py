"""Cache complet et routage des moteurs, sans réseau ni chargement de poids."""
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from moteur import modele_local


def cache_modele(tmp_path, repo, sous_dossier='', fichiers=()):
    root = tmp_path / ('models--' + repo.replace('/', '--'))
    (root / 'refs').mkdir(parents=True)
    (root / 'refs/main').write_text('abc123')
    snap = root / 'snapshots/abc123' / sous_dossier
    snap.mkdir(parents=True)
    for fichier in ('config.json', *fichiers):
        (snap / fichier).write_text('{}')
    return snap


def test_parakeet_exige_tokenizer(tmp_path):
    snap = cache_modele(tmp_path, 'mlx-community/parakeet-tdt-0.6b-v3', fichiers=['model.safetensors'])
    with pytest.raises(FileNotFoundError):
        modele_local(tmp_path, 'parakeet')
    (snap / 'tokenizer.model').write_text('tokenizer')
    assert modele_local(tmp_path, 'parakeet') == str(snap)


def test_cohere_exige_tokenizers(tmp_path):
    snap = cache_modele(tmp_path, 'littoralai/cohere-transcribe-mlx-8bit', '',
        ['model.safetensors', 'tokenizer.model', 'tokenizer_config.json', 'special_tokens_map.json'])
    assert modele_local(tmp_path, 'cohere') == str(snap)
    (snap / 'tokenizer.model').unlink()
    with pytest.raises(FileNotFoundError):
        modele_local(tmp_path, 'cohere')


def test_modele_inconnu_refuse(tmp_path):
    with pytest.raises(ValueError, match='inconnu'):
        modele_local(tmp_path, '../../autre')


def test_chargement_strict_et_options_natives(monkeypatch):
    import types
    import numpy as np
    import backend
    from mlx_audio.stt import utils
    appels = []
    class Modele:
        def generate(self, audio, **options):
            appels.append(options)
            return types.SimpleNamespace(text=' À bientôt. ')
    def load(path, **options):
        assert isinstance(path, Path)
        assert options['strict'] is True  # pas de poids manquants silencieusement ignorés
        assert options['model_type'] in ('parakeet', 'cohere_asr')
        return Modele()
    monkeypatch.setattr(backend, 'modele_local', lambda **kw: '/modele-local')
    monkeypatch.setattr(utils, 'load', load)
    for nom in ['cohere', 'parakeet']:
        moteur = backend.Backend(nom)
        assert moteur.transcrire(np.zeros(16000, dtype=np.float32)) == ('À bientôt.', 1)
    assert appels[0]['language'] == 'fr'
    assert appels[0]['batch_size'] == 1
    assert appels[1]['chunk_duration'] == 30
    assert 'initial_prompt' not in appels[1]


def test_comparaison_remonte_une_erreur_de_modele(monkeypatch, tmp_path):
    import types
    import comparer
    monkeypatch.setattr(comparer.subprocess, 'run', lambda *a, **kw:
                        types.SimpleNamespace(stdout='{"fatal":"poids incompatibles"}\n',
                                              stderr='', returncode=1))
    with pytest.raises(RuntimeError, match='poids incompatibles'):
        comparer.comparer(tmp_path / 'audio.wav', 'cohere')


def test_installeur_sans_argument_reutilise_whisper(tmp_path):
    import os
    import subprocess
    snap = cache_modele(tmp_path, 'mlx-community/whisper-large-v3-turbo', fichiers=['weights.safetensors'])
    result = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / 'installer_modele.py')],
                            capture_output=True, text=True, timeout=10,
                            env={**os.environ, 'HF_HUB_CACHE': str(tmp_path), 'HF_HUB_OFFLINE': '1'})
    assert result.returncode == 0, result.stderr
    assert str(snap) in result.stdout
