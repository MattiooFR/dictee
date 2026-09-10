"""Installation uniquement : réutilise le modèle local, télécharge s'il manque."""
from moteur import MODELE, modele_local


def installer():
    try:
        return modele_local()
    except FileNotFoundError:
        from huggingface_hub import snapshot_download
        return snapshot_download(repo_id=MODELE, allow_patterns=['config.json', 'weights.safetensors', 'weights.npz'])


if __name__ == '__main__':
    print('Modèle local prêt : ' + installer())
