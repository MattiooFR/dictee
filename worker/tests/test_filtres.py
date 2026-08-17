import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from filtres import est_parasite, est_repetition, nettoyer, normaliser, vocabulaire


def test_normaliser_enleve_accents_ponctuation_et_casse():
    assert normaliser("Merci d'avoir REGARDÉ, cette vidéo !") == "merci d avoir regarde cette video"


def test_les_phrases_de_fin_de_video_sont_rejetees():
    assert est_parasite("Sous-titres réalisés par la communauté d'Amara.org")
    assert est_parasite("Merci d'avoir regardé cette vidéo !")
    assert est_parasite("❤️ par SousTitreur.com")


def test_une_phrase_normale_passe():
    assert not est_parasite("On va publier un guest post sur ce spot demain.")


def test_la_repetition_est_detectee():
    assert est_repetition(" ".join(["oui"] * 40))
    assert not est_repetition("Je pense qu'on devrait revoir le maillage interne de la page.")


def test_nettoyer_assemble_et_ecarte():
    segments = [
        " On publie demain. ",
        "Sous-titres réalisés par la communauté d'Amara.org",
        "  ",
        "Il faudra vérifier l'indexation.",
    ]
    assert nettoyer(segments) == "On publie demain. Il faudra vérifier l'indexation."


def test_nettoyer_rend_une_chaine_vide_si_tout_est_ecarte():
    assert nettoyer(["Merci d'avoir regardé cette vidéo", "   "]) == ""


def test_vocabulaire_absent_ne_casse_pas(tmp_path):
    prompt, avertissement = vocabulaire(tmp_path / "rien.txt")
    assert prompt == ""
    assert avertissement is None


def test_vocabulaire_ignore_commentaires_et_lignes_vides(tmp_path):
    f = tmp_path / "v.txt"
    f.write_text("# commentaire\n\nnetlinking\nbacklink\n", encoding="utf-8")
    prompt, avertissement = vocabulaire(f)
    assert prompt == "Vocabulaire : netlinking, backlink."
    assert avertissement is None


def test_vocabulaire_trop_long_est_tronque_avec_avertissement(tmp_path):
    f = tmp_path / "v.txt"
    f.write_text("\n".join(f"terme{i}" for i in range(80)), encoding="utf-8")
    prompt, avertissement = vocabulaire(f, maximum_termes=60)
    assert prompt.count(",") == 59
    assert "tronqué" in avertissement
