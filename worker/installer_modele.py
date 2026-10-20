"""Installation explicite uniquement : téléchargement des poids et tokenizers."""
import argparse
from moteur import MODELES, description_modele, modele_local


def installer(modele='whisper'):
    spec = description_modele(modele)
    try:
        return modele_local(modele=modele)
    except FileNotFoundError:
        from huggingface_hub import snapshot_download
        prefixe = spec['dossier'] + '/' if spec['dossier'] else ''
        patterns = ([prefixe + '*.json', prefixe + '*.safetensors', prefixe + '*.model',
                     prefixe + '*.vocab', prefixe + '*.txt'] if modele != 'whisper'
                    else ['config.json', 'weights.safetensors', 'weights.npz'])
        snapshot_download(repo_id=spec['repo'], allow_patterns=patterns)
        return modele_local(modele=modele)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('modeles', nargs='*', metavar='MODELE',
                        help='whisper, parakeet, cohere ou tous (défaut : whisper)')
    args = parser.parse_args()
    if any(m not in [*MODELES, 'tous'] for m in args.modeles):
        parser.error('modèle inconnu : choisir whisper, parakeet, cohere ou tous')
    for modele in (MODELES if 'tous' in args.modeles else args.modeles or ['whisper']):
        print(f'Modèle local {modele} prêt : ' + installer(modele), flush=True)
