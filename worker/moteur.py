"""Politique d'inférence locale, indépendante de la boucle stdin du worker."""
from pathlib import Path

MODELES = {
    'whisper': dict(repo='mlx-community/whisper-large-v3-turbo', dossier='',
                    fichiers=('config.json',)),
    'parakeet': dict(repo='mlx-community/parakeet-tdt-0.6b-v3', dossier='',
                     fichiers=('config.json', 'model.safetensors', 'tokenizer.model')),
    'cohere': dict(repo='littoralai/cohere-transcribe-mlx-8bit', dossier='',
                   fichiers=('config.json', 'model.safetensors', 'tokenizer.model',
                             'tokenizer_config.json', 'special_tokens_map.json')),
}
MODELE = MODELES['whisper']['repo']  # compatibilité des scripts existants


def description_modele(modele):
    if modele not in MODELES:
        raise ValueError('Modèle inconnu : ' + modele)
    return MODELES[modele]


def modele_local(cache=None, modele='whisper'):
    # Aucun téléchargement au runtime, y compris pour les tokenizers.
    spec = description_modele(modele)
    if cache is None:
        from huggingface_hub.constants import HF_HUB_CACHE
        cache = HF_HUB_CACHE
    repo = Path(cache) / ('models--' + spec['repo'].replace('/', '--'))
    try:
        revision = (repo / 'refs/main').read_text().strip()
        if not revision or '/' in revision or '..' in revision:
            raise ValueError('révision invalide')
        dossier = repo / 'snapshots' / revision / spec['dossier']
        if not all((dossier / f).is_file() for f in spec['fichiers']):
            raise FileNotFoundError()
        if modele == 'whisper' and not any((dossier / f).is_file()
                for f in ('weights.safetensors', 'weights.npz')):
            raise FileNotFoundError()
        return str(dossier)
    except (OSError, ValueError) as exc:
        raise FileNotFoundError(
            f'Modèle local {modele} absent ou incomplet : '
            f'lancer .venv/bin/python worker/installer_modele.py {modele}') from exc


def transcrire_limite(decode, audio, options):
    resultat = decode(audio, **options, temperature=0.0)
    segments = resultat.get('segments', [])
    difficiles = [s for s in segments if s.get('no_speech_prob', 0) < 0.6 and
                  (s.get('avg_logprob', 0) < -1 or s.get('compression_ratio', 0) > 2.4)]
    if not difficiles:
        return resultat, 1
    seconde = decode(audio, **options, temperature=0.2, best_of=1)
    # Une tentative supplémentaire, jamais une cascade. Ne remplacer la
    # première hypothèse que si la confiance moyenne s'améliore.
    def score(r):
        ss = r.get('segments', [])
        return sum(s.get('avg_logprob', -10) for s in ss) / len(ss) if ss else -100
    return (seconde if score(seconde) > score(resultat) else resultat), 2
