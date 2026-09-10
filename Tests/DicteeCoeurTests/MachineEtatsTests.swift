import Testing
@testable import DicteeCoeur

@Test("l'appui démarre la capture immédiatement et arme les deux minuteries")
func appui() {
    var m = MachineEtats()
    #expect(m.recevoir(.appui) == [.demarrerCapture, .armerGarde, .armerDureeMax])
    #expect(m.etat == .capture(gardeFranchie: false))
}

@Test("un appui trop court jette l'audio et affiche annulé")
func appuiTropCourt() {
    var m = MachineEtats(); _ = m.recevoir(.appui)
    #expect(m.recevoir(.relachement) == [.desarmerMinuteries, .abandonnerCapture, .pastille(.annule)])
    #expect(m.etat == .repos)
}

@Test("le cercle ne s'ouvre qu'après la garde")
func gardeOuvreLeCercle() {
    var m = MachineEtats(); _ = m.recevoir(.appui)
    #expect(m.recevoir(.gardeEcoulee) == [.preparerModele, .pastille(.ecoute)])
    #expect(m.etat == .capture(gardeFranchie: true))
}

@Test("une dictée nominale clôture la capture et passe en transcription")
func dicteeNominale() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee)
    #expect(m.recevoir(.relachement) == [.desarmerMinuteries, .pastille(.transcription), .cloturerCapture])
    #expect(m.etat == .transcription)
}

@Test("un raccourci ⌘ droite + touche annule sans aucun retour visuel")
func raccourciAnnule() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee)
    #expect(m.recevoir(.autreTouche) == [.desarmerMinuteries, .abandonnerCapture, .pastille(.repos)])
    #expect(m.etat == .repos)
}

@Test("la coupure de sécurité transcrit ce qui a été dit")
func coupureSecurite() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee)
    #expect(m.recevoir(.dureeMax) == [.desarmerMinuteries, .pastille(.transcription), .cloturerCapture])
}

@Test("moins de 400 ms de parole n'atteint jamais le modèle")
func tropPeuDeParole() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee); _ = m.recevoir(.relachement)
    #expect(m.recevoir(.captureAnalysee(secondesParlees: 0.2)) == [.pastille(.annule)])
    #expect(m.etat == .repos)
}

@Test("assez de parole part au worker")
func assezDeParole() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee); _ = m.recevoir(.relachement)
    #expect(m.recevoir(.captureAnalysee(secondesParlees: 1.5)) == [.envoyerAuWorker])
    #expect(m.etat == .transcription)
}

@Test("un texte vide après filtrage annule au lieu d'échouer")
func texteVide() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee); _ = m.recevoir(.relachement)
    _ = m.recevoir(.captureAnalysee(secondesParlees: 1.5))
    #expect(m.recevoir(.texteRecu("   \n ")) == [.pastille(.annule)])
    #expect(m.etat == .repos)
}

@Test("un texte non vide est collé, débarrassé de ses blancs")
func texteColle() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee); _ = m.recevoir(.relachement)
    _ = m.recevoir(.captureAnalysee(secondesParlees: 1.5))
    #expect(m.recevoir(.texteRecu(" bonjour ")) == [.coller("bonjour"), .pastille(.succes)])
}

@Test("un échec affiche l'erreur")
func echec() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee); _ = m.recevoir(.relachement)
    _ = m.recevoir(.captureAnalysee(secondesParlees: 1.5))
    #expect(m.recevoir(.echec("délai dépassé")) == [.pastille(.erreur("délai dépassé"))])
    #expect(m.etat == .repos)
}

@Test("un appui pendant la transcription est ignoré : un seul travail à la fois")
func appuiPendantTranscription() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee); _ = m.recevoir(.relachement)
    #expect(m.recevoir(.appui) == [])
    #expect(m.etat == .transcription)
}

@Test("l'affichage de la transcription précède la clôture de capture")
func ordreAffichageAvantCloture() {
    // La clôture produit l'événement suivant (captureAnalysee), dont l'état
    // d'affichage doit recouvrir le rotor. Dans l'ordre inverse, le rotor
    // écrasait l'annulation et ne partait plus jamais.
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee)
    let actions = m.recevoir(.relachement)
    let iPastille = actions.firstIndex(of: .pastille(.transcription))
    let iCloture = actions.firstIndex(of: .cloturerCapture)
    #expect(iPastille != nil && iCloture != nil)
    #expect(iPastille! < iCloture!)
}

// ── mode verrouillé et triple appui ───────────────────────────────────────

@Test("un clic sur la pastille démarre un enregistrement verrouillé")
func clicDemarre() {
    var m = MachineEtats()
    #expect(m.recevoir(.clicPastille) == [.demarrerCapture, .preparerModele, .armerDureeMax, .pastille(.ecoute)])
    #expect(m.etat == .captureVerrouillee)
}

@Test("il n'y a pas de garde en mode verrouillé : le bandeau s'ouvre tout de suite")
func pasDeGardeEnVerrouille() {
    var m = MachineEtats()
    let actions = m.recevoir(.clicPastille)
    #expect(!actions.contains(.armerGarde))
    #expect(actions.contains(.pastille(.ecoute)))
}

@Test("un second clic arrête et transcrit")
func secondClicArrete() {
    var m = MachineEtats(); _ = m.recevoir(.clicPastille)
    #expect(m.recevoir(.clicPastille) == [.desarmerMinuteries, .pastille(.transcription), .cloturerCapture])
    #expect(m.etat == .transcription)
}

@Test("⌘ droite arrête aussi le mode verrouillé, à l'appui")
func commandeArreteLeVerrouille() {
    var m = MachineEtats(); _ = m.recevoir(.clicPastille)
    #expect(m.recevoir(.appui) == [.desarmerMinuteries, .pastille(.transcription), .cloturerCapture])
    #expect(m.etat == .transcription)
}

@Test("relâcher ⌘ droite ne coupe pas le mode verrouillé")
func relachementSansEffetEnVerrouille() {
    var m = MachineEtats(); _ = m.recevoir(.clicPastille)
    #expect(m.recevoir(.relachement) == [])
    #expect(m.etat == .captureVerrouillee)
}

@Test("taper au clavier n'annule pas le mode verrouillé")
func autreToucheSansEffetEnVerrouille() {
    var m = MachineEtats(); _ = m.recevoir(.clicPastille)
    #expect(m.recevoir(.autreTouche) == [])
    #expect(m.etat == .captureVerrouillee)
}

@Test("la coupure de sécurité s'applique aussi au mode verrouillé")
func dureeMaxEnVerrouille() {
    var m = MachineEtats(); _ = m.recevoir(.clicPastille)
    #expect(m.recevoir(.dureeMax) == [.desarmerMinuteries, .pastille(.transcription), .cloturerCapture])
}

@Test("trois appuis brefs ouvrent l'historique sans toucher à l'état")
func tripleAppuiOuvreHistorique() {
    var m = MachineEtats()
    #expect(m.recevoir(.tripleAppui) == [.ouvrirHistorique])
    #expect(m.etat == .repos)
}

@Test("un clic pendant une transcription est ignoré : un seul travail à la fois")
func clicPendantTranscriptionIgnore() {
    var m = MachineEtats(); _ = m.recevoir(.clicPastille); _ = m.recevoir(.clicPastille)
    #expect(m.recevoir(.clicPastille) == [])
    #expect(m.etat == .transcription)
}

@Test("un clic pendant un push-to-talk est ignoré")
func clicPendantPushToTalkIgnore() {
    var m = MachineEtats(); _ = m.recevoir(.appui); _ = m.recevoir(.gardeEcoulee)
    #expect(m.recevoir(.clicPastille) == [])
    #expect(m.etat == .capture(gardeFranchie: true))
}

@Test("réessayer depuis le repos envoie la dictée conservée sans réenregistrer")
func reessayerSansCapture() {
    var m = MachineEtats()
    #expect(m.recevoir(.reessayer) == [.pastille(.preparation), .envoyerAuWorker])
    #expect(m.etat == .transcription)
    #expect(m.recevoir(.reessayer).isEmpty)
}

@Test("un micro en échec rend la main et désarme la capture")
func echecMicroRendLaMain() {
    var m = MachineEtats(); _ = m.recevoir(.appui)
    let actions = m.recevoir(.echec("micro"))
    #expect(m.etat == .repos)
    #expect(actions.contains(.abandonnerCapture))
    #expect(actions.contains(.desarmerMinuteries))
}
