"""Politique d'inférence locale, indépendante de la boucle stdin du worker."""
from pathlib import Path

MODELE = 'mlx-community/whisper-large-v3-turbo'


def modele_local(cache=None):
    # Aucun appel à snapshot_download : le runtime ne dépend jamais du réseau.
    if cache is None:
        from huggingface_hub.constants import HF_HUB_CACHE
        cache = HF_HUB_CACHE
    repo = Path(cache) / ('models--' + MODELE.replace('/', '--'))
    try:
        revision = (repo / 'refs/main').read_text().strip()
        if not revision or '/' in revision or '..' in revision:
            raise ValueError('révision invalide')
        dossier = repo / 'snapshots' / revision
        if not (dossier / 'config.json').is_file():
            raise FileNotFoundError()
        if not any((dossier / f).is_file() for f in ('weights.safetensors', 'weights.npz')):
            raise FileNotFoundError()
        return str(dossier)
    except (OSError, ValueError) as exc:
        raise FileNotFoundError('Modèle local absent ou incomplet : lancer ./install.sh une fois.') from exc


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
