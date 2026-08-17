# Dictée

*[English version](README.md)*

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
| Surveillance des entrées | Écouter ⌘ droite | Réglages → Confidentialité et sécurité |
| Accessibilité | Poster le ⌘V du collage | Réglages → Confidentialité et sécurité |
| Micro | Capturer la voix | Boîte de dialogue au démarrage |

Les trois sont demandées **au démarrage**, jamais en pleine dictée : une boîte
de dialogue pendant un push-to-talk ferait perdre la phrase.

Tant qu'il en manque une, la pastille reste rouge et l'app attend. **Rien à
relancer** : elle teste toutes les 2 s et démarre d'elle-même dès que tu
accordes. Le journal dit laquelle manque.

## Utilisation

Maintiens ⌘ droite, parle, relâche. La pastille au bord droit de l'écran
indique l'état :

| Pastille | État |
|---|---|
| Fine barre grise au ras du bord | Au repos |
| Barre élargie et éclaircie | La souris la survole |
| Bandeau noir, vague de barres qui monte | J'écoute |
| Bandeau noir, ondulation lente | Je transcris |
| Coche verte | Texte inséré |
| Pulsation grise | Annulé (appui trop court, ou rien dit) |
| Bandeau rouge | Erreur — détail dans le journal |

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

## Historique

Toutes les dictées sont conservées dans `~/.config/dictee/historique.jsonl`
(une ligne JSON par dictée, ~200 octets). Seul le texte est gardé, jamais
l'audio.

**Trois appuis brefs sur ⌘ droite** ouvrent la fenêtre de consultation.

| Geste | Effet |
|---|---|
| Champ de recherche | Filtre à la frappe, insensible à la casse et aux accents |
| Clic sur une ligne | Le texte part dans le presse-papier |
| ⏎ | Le texte est recollé dans l'application d'où tu venais |
| ⌫ | L'entrée est supprimée |
| Échap | La fenêtre se ferme |

## Enregistrer sans tenir la touche

La barre au repos **se réveille au survol**. Un clic dessus démarre un
enregistrement verrouillé : plus besoin de maintenir ⌘ droite. Un second clic,
ou un appui sur ⌘ droite, arrête et transcrit.

En mode verrouillé, taper au clavier n'annule pas — contrairement au
push-to-talk, où ⌘ droite + une touche reste un raccourci normal.

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
swift test                                                    # 41 tests
.venv/bin/python -m pytest worker/tests/test_filtres.py -q     # 9 tests
.venv/bin/python -m pytest worker/tests/test_integration.py \
  -q -m lent -c worker/pytest.ini                              # 2 tests (charge le modèle)
```

## Checklist de vérification manuelle

Ce qu'aucun test automatisé ne couvre : le tap système, la pastille à l'écran,
le collage dans une vraie application. À dérouler après chaque `./build.sh`.

- [ ] Les trois autorisations sont **toujours** accordées (si elles sautent,
      le certificat de signature a changé)
- [ ] `swift test` : 41 tests au vert
- [ ] `.venv/bin/python -m pytest worker/tests/test_filtres.py -q` : 9 au vert
- [ ] Dictée nominale de 3 s dans TextEdit → texte inséré
- [ ] Même chose dans Chrome, Slack et VS Code
- [ ] ⌘ droite brève → pulsation grise, rien d'inséré
- [ ] ⌘ droite + C → copie normale, aucune dictée
- [ ] ⌘ **gauche** maintenue → aucune réaction
- [ ] Silence de 3 s sous ⌘ droite → pulsation grise, aucune ligne worker
      dans le journal
- [ ] Pastille visible au-dessus d'une fenêtre en plein écran
- [ ] Sur un second écran : la pastille se repositionne à la dictée suivante
- [ ] Au repos, **aucun point orange** micro dans la barre de menus
- [ ] Après redémarrage du Mac, la dictée fonctionne sans rien relancer
- [ ] Clic sur la pastille → enregistre sans tenir de touche ; second clic →
      **le texte atterrit dans l'application d'origine** (valide le panneau
      non activant)
- [ ] Pendant un enregistrement verrouillé, taper au clavier n'annule pas
- [ ] Survol de la barre au repos → elle s'élargit et s'éclaircit
- [ ] Clic juste à côté de la pastille → traverse vers l'app du dessous
- [ ] Trois appuis brefs sur ⌘ droite ouvrent la fenêtre ; deux ne l'ouvrent pas
- [ ] Trois appuis brefs ne produisent ni saccade audio ni clignotement de
      l'indicateur micro
- [ ] Dans la fenêtre : la recherche filtre, un clic copie, ⏎ recolle **dans
      l'app d'où l'on venait**, ⌫ supprime, Échap ferme
- [ ] Après suppression et redémarrage, l'entrée n'est pas revenue

## Architecture

```
 ⌘ droite ─▶ Dictee.app (Swift, agent LSUIElement)
                ├─ CGEventTap passif       (écoute ⌘ droite)
                ├─ AVAudioEngine           (audio + niveau RMS)
                ├─ NSPanel non activant    (la pastille, cliquable)
                ├─ NSPasteboard + CGEvent  (le collage)
                ├─ Historique JSONL        (~/.config/dictee)
                └─▶ worker Python (enfant, stdin/stdout)
                       └─ mlx-whisper large-v3-turbo, modèle résident
```

Trois décisions qui expliquent le reste :

- **Le tap clavier est passif** (`listenOnly`) : ⌘ droite continue de
  fonctionner dans tous tes raccourcis existants.
- **La pastille est un `NSPanel` non activant**, dimensionné à sa propre
  forme. Il reçoit les clics sans voler le focus — c'est ce qui permet au ⌘V
  synthétique d'atterrir dans l'app où tu écrivais — et il reste assez petit
  pour ne pas avaler les clics destinés à une barre de défilement en dessous.
- **La capture démarre avant la garde de 250 ms**, donc le premier mot n'est
  jamais coupé ; la pastille, elle, ne s'ouvre qu'après la garde, pour qu'un
  raccourci ⌘ droite ne la fasse pas clignoter.

## Licence

MIT — voir [LICENSE](LICENSE).
