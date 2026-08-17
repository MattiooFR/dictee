# Dictée

Dictée vocale globale sur macOS, 100 % locale. Maintiens **⌘ droite**, parle,
relâche : le texte s'insère là où est ton curseur, dans n'importe quelle
application.

Aucun appel réseau, aucun abonnement. La reconnaissance tourne sur le GPU de la
machine avec `mlx-whisper large-v3-turbo`, en français.

## Installation

### 1. Créer le certificat de signature (une seule fois)

Trousseau d'accès → menu **Assistant de certification** → *Créer un
certificat* :

- Nom : `Dictee Dev`
- Type d'identité : **Racine auto-signée**
- Type de certificat : **Signature de code**

Vérifier : `security find-identity -p codesigning` doit lister `Dictee Dev`.

⚠️ **Sans le `-v`.** Un certificat racine auto-signé est toujours signalé
`CSSMERR_TP_NOT_TRUSTED`, et `-v` l'écarterait. C'est normal et sans
conséquence : l'approbation sert à *vérifier* une signature, pas à en produire
une. `codesign` accepte parfaitement ce certificat.

**Pourquoi c'est indispensable.** macOS rattache les autorisations
(micro, entrées, accessibilité) à l'identité de code, sous la forme d'une
exigence désignée :

```
identifier "com.dugmedia.dictee" and certificate leaf = H"<hash du certificat>"
```

Identifiant de bundle + certificat, jamais le hash du binaire — donc les
autorisations survivent aux recompilations. Signée en ad-hoc, l'app n'aurait
que son hash comme identité et **les trois autorisations sauteraient à chaque
build**.

### 2. Installer

```bash
./install.sh
```

Le script compile l'app, crée le venv Python, installe le vocabulaire et pose
le LaunchAgent (démarrage automatique à l'ouverture de session).

### 3. Accorder les trois autorisations

| Autorisation | Pourquoi | Où |
|---|---|---|
| Micro | Capturer la voix | Demandé automatiquement à la première dictée |
| Surveillance des entrées | Écouter ⌘ droite | Réglages → Confidentialité et sécurité |
| Accessibilité | Poster le ⌘V du collage | Réglages → Confidentialité et sécurité |

Ajouter `Dictee.app` dans les deux dernières listes, puis :

```bash
launchctl kickstart -k gui/$UID/com.dugmedia.dictee
```

## Utilisation

Maintiens ⌘ droite, parle, relâche. La pastille au bord droit de l'écran
indique l'état :

| Pastille | État |
|---|---|
| Barre verticale grise | Au repos |
| Cercle noir, anneau qui respire | J'écoute |
| Arc qui tourne | Je transcris |
| Coche verte | Texte inséré |
| Pulsation grise | Annulé (appui trop court, ou rien dit) |
| Cercle rouge | Erreur — détail dans le journal |

Un appui bref sur ⌘ droite ne déclenche rien, et ⌘ droite + une autre touche
reste un raccourci normal.

## Vocabulaire

`~/.config/dictee/vocabulaire.txt` — un terme par ligne. Sans lui,
« netlinking » devient « net linking ».

**Maximum 60 termes.** `initial_prompt` est plafonné à 224 tokens côté Whisper :
au-delà, il *dégrade* la transcription au lieu de l'améliorer. Le worker tronque
et prévient dans le journal.

Relancer l'app après modification :
`launchctl kickstart -k gui/$UID/com.dugmedia.dictee`

## Diagnostic

```bash
tail -f ~/Library/Logs/dictee.log     # journal

swift run Dictee --test-micro          # vumètre + WAV de 3 s
swift run Dictee --test-clavier        # journalise les appuis sur ⌘ droite
swift run Dictee --test-collage TEXTE  # colle TEXTE après 3 s
swift run Dictee --test-pastille       # fait défiler les six états
```

Chaque module se vérifie seul, sans le reste de l'application.

## Tests

```bash
swift test                                                    # 22 tests
.venv/bin/python -m pytest worker/tests/test_filtres.py -q     # 9 tests
.venv/bin/python -m pytest worker/tests/test_integration.py \
  -q -m lent -c worker/pytest.ini                              # 2 tests (charge le modèle)
```

## Checklist de vérification manuelle

Ce qu'aucun test automatisé ne couvre : le tap système, la pastille à l'écran,
le collage dans une vraie application. À dérouler après chaque `./build.sh`.

- [ ] Les trois autorisations sont **toujours** accordées (si elles sautent,
      le certificat de signature a changé)
- [ ] `swift test` : 22 tests au vert
- [ ] `.venv/bin/python -m pytest worker/tests/test_filtres.py -q` : 9 au vert
- [ ] Dictée nominale de 3 s dans TextEdit → texte inséré
- [ ] Même chose dans Chrome, Slack et VS Code
- [ ] ⌘ droite brève → pulsation grise, rien d'inséré
- [ ] ⌘ droite + C → copie normale, aucune dictée
- [ ] ⌘ **gauche** maintenue → aucune réaction
- [ ] Silence de 3 s sous ⌘ droite → pulsation grise, aucune ligne worker
      dans le journal
- [ ] Pastille visible au-dessus d'une fenêtre en plein écran
- [ ] Clic à l'emplacement de la pastille → traverse vers l'app du dessous
- [ ] Sur un second écran : la pastille se repositionne à la dictée suivante
- [ ] Au repos, **aucun point orange** micro dans la barre de menus
- [ ] Après redémarrage du Mac, la dictée fonctionne sans rien relancer

## Architecture

Voir `docs/superpowers/specs/2026-08-17-dictee-design.md` pour le design et
`docs/superpowers/plans/2026-08-17-dictee.md` pour le découpage.

```
 ⌘ droite ─▶ Dictee.app (Swift, agent LSUIElement)
                ├─ CGEventTap passif       (écoute ⌘ droite)
                ├─ AVAudioEngine           (audio + niveau RMS)
                ├─ NSWindow flottante      (la pastille)
                ├─ NSPasteboard + CGEvent  (le collage)
                └─▶ worker Python (enfant, stdin/stdout)
                       └─ mlx-whisper large-v3-turbo, modèle résident
```
