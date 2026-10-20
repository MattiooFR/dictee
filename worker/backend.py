"""Adaptateurs ASR. Un seul moteur est chargé dans chaque processus."""
import sys
from contextlib import redirect_stdout
from pathlib import Path
from moteur import modele_local, transcrire_limite
from filtres import nettoyer, vocabulaire


class Backend:
    def __init__(self, modele):
        self.modele = modele
        self.chemin = modele_local(modele=modele)
        with redirect_stdout(sys.stderr):
            if modele == 'whisper':
                import mlx_whisper
                from mlx_whisper.tokenizer import get_tokenizer
                self.decode = mlx_whisper.transcribe
                self.tokenizer = get_tokenizer(True, num_languages=100, language='fr', task='transcribe')
            else:
                from mlx_audio.stt.utils import load
                # Le nom du cache/snapshot ne permet pas toujours l'auto-détection.
                self.model = load(Path(self.chemin), strict=True, model_type=(
                    'cohere_asr' if modele == 'cohere' else 'parakeet'))

    def transcrire(self, audio):
        # Les bibliothèques ne doivent jamais polluer le protocole JSON stdout.
        with redirect_stdout(sys.stderr):
            if self.modele == 'whisper':
                prompt, warning = vocabulaire(Path.home() / '.config/dictee/vocabulaire.txt',
                                              encoder=self.tokenizer.encode)
                if warning:
                    print(warning, file=sys.stderr)
                resultat, passes = transcrire_limite(self.decode, audio, dict(
                    path_or_hf_repo=self.chemin, language='fr', initial_prompt=prompt or None,
                    condition_on_previous_text=False, verbose=None))
                return nettoyer(s['text'] for s in resultat['segments']), passes
            import mlx.core as mx
            options = (dict(language='fr', batch_size=1, max_tokens=512)
                       if self.modele == 'cohere' else dict(chunk_duration=30, overlap_duration=2))
            resultat = self.model.generate(mx.array(audio), verbose=False, **options)
            # Les filtres anti-hallucination Whisper suppriment certaines phrases
            # légitimes : ne pas les appliquer aux autres familles de modèles.
            return resultat.text.strip(), 1
