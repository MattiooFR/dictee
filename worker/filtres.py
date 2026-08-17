"""Nettoyage de la sortie brute de Whisper.

Volontairement sans import mlx : ces fonctions doivent être testables sans
charger le modèle (~20 s).
"""
import unicodedata

# Whisper large-v3 invente des formules de fin de vidéo YouTube sur les
# passages silencieux. Ce sont les plus fréquentes en français.
# Comparaison sur le texte normalisé, en égalité stricte.
PHRASES_PARASITES = {
    "sous titres realises par la communaute d amara org",
    "sous titres realises par amara org",
    "sous titrage st 501",
    "sous titrage societe radio canada",
    "merci d avoir regarde cette video",
    "merci d avoir regarde",
    "abonnez vous",
    "merci a tous et a la prochaine",
    "a bientot",
}

# Signatures de sites de sous-titrage : rejetées où qu'elles apparaissent.
SIGNATURES = ("amara org", "soustitreur com", "sous titreur com")

MAXIMUM_TERMES = 60


def normaliser(texte):
    """Minuscules, sans accents, sans ponctuation, espaces compactés."""
    sans_accents = "".join(
        c
        for c in unicodedata.normalize("NFD", texte.lower())
        if unicodedata.category(c) != "Mn"
    )
    lettres = "".join(c if c.isalnum() else " " for c in sans_accents)
    return " ".join(lettres.split())


def est_repetition(texte, mots_minimum=20, ratio_maximum=0.25):
    """Un long segment dont presque tous les mots se répètent est une boucle."""
    mots = texte.split()
    return len(mots) > mots_minimum and len(set(mots)) / len(mots) < ratio_maximum


def est_parasite(texte):
    n = normaliser(texte)
    if not n:
        return True
    return n in PHRASES_PARASITES or any(s in n for s in SIGNATURES)


def nettoyer(segments):
    """Assemble les segments retenus. Rend "" s'il ne reste rien."""
    gardes = [s.strip() for s in segments if s.strip()]
    gardes = [s for s in gardes if not est_repetition(s) and not est_parasite(s)]
    return " ".join(gardes).strip()


def vocabulaire(chemin, maximum_termes=MAXIMUM_TERMES):
    """Lit le fichier de vocabulaire. Rend (prompt, avertissement ou None).

    initial_prompt est plafonné à 224 tokens côté Whisper : au-delà, il dégrade
    la transcription au lieu de l'améliorer. On tronque donc, bruyamment.
    """
    try:
        with open(chemin, encoding="utf-8") as f:
            termes = [
                l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")
            ]
    except FileNotFoundError:
        return "", None

    avertissement = None
    if len(termes) > maximum_termes:
        avertissement = (
            f"vocabulaire tronqué : {len(termes)} termes lus, "
            f"{maximum_termes} conservés (limite de 224 tokens d'initial_prompt)"
        )
        termes = termes[:maximum_termes]

    if not termes:
        return "", avertissement
    return "Vocabulaire : " + ", ".join(termes) + ".", avertissement
