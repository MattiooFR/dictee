# Dictée

*[English version](README.md)*

Dictée vocale globale sur macOS, 100 % locale. Maintiens **⌘ droite**, parle,
relâche : le texte s'insère là où est ton curseur, dans n'importe quelle
application.

Aucun appel réseau pendant la dictée, aucun abonnement. Le modèle est téléchargé une seule fois à l’installation, s’il manque au cache local. La reconnaissance tourne sur le GPU de la
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

## Mémoire et réactivité (0.3)

Le mode **Équilibré** est actif par défaut. Le micro enregistre dès l’appui.
Après 250 ms sur ⌘ droite, le moteur démarre ou se réchauffe pendant que tu
parles. Un clic sur la pastille le réveille immédiatement. Un appui relâché ou transformé en raccourci avant 250 ms ne lance pas le modèle.

Après une dictée, le cache MLX est purgé après 60 secondes au repos. Le
modèle reste disponible jusqu’à 15 minutes d’inactivité, puis le worker
s’arrête pour libérer sa mémoire. Il ne s’arrête jamais pendant une capture
ou une transcription. Le menu micro de la barre macOS permet de choisir
**Toujours garder le modèle prêt** (la purge du cache reste active).

Le bandeau orange indique la préparation du modèle ; le bandeau noir indique
la transcription. Le chargement a son propre délai maximal de 120 secondes,
puis chaque transcription dispose de 30 secondes. Un timeout arrête le
worker bloqué ; les identifiants empêchent les réponses tardives de se
mélanger avec une autre dictée.

Réglages avancés : `~/.config/dictee/config.json` (menu micro → ouvrir les réglages).
Le mode se change immédiatement dans le menu. Les durées et le plafond sont
lus au lancement de l’app :

```json
{
  "toujoursPret": false,
  "inactiviteSecondes": 900,
  "purgeSecondes": 60,
  "cacheMo": 512
}
```

Le plafond de cache est souple ; les poids du modèle restent en plus en
mémoire. Dans un essai local sur une phrase synthétique de 3,1 secondes,
MLX gardait environ 1 543 Mio actifs et 515 Mio de cache, puis zéro cache
après purge. Cela ne représente pas toute l’empreinte du processus et ne
prédit pas la latence sur un Mac sous pression mémoire.

WebRTC VAD repère la voix sans modèle supplémentaire. Les marges de 250 ms
protègent les mots ; seules les longues pauses sont raccourcies. Whisper
fait une première passe à température zéro, puis au maximum une seconde
si la confiance est faible. Le vocabulaire est relu à chaque demande.

## Réessayer une dictée

Le menu micro → **Réessayer une dictée** liste les enregistrements en échec.
Place ton curseur dans le champ cible, puis choisis l’enregistrement par sa
date. Le texte est transcrit puis collé, sans refaire l’enregistrement.

Les WAV restent dans `~/.config/dictee/a-reessayer`, dossier privé (0700,
fichiers 0600). Ils sont supprimés après réussite. En cas d’échec ou de crash,
ils restent disponibles pendant 24 heures. L’app nettoie les fichiers expirés
au lancement puis toutes les minutes, sans supprimer un travail en cours.
Si l’app est arrêtée, le nettoyage reprend à son prochain lancement.

## Utilisation

Maintiens ⌘ droite, parle, relâche. La pastille au bord droit de l'écran
indique l'état :

| Pastille | État |
|---|---|
| Fine barre grise au ras du bord | Au repos |
| Barre élargie et éclaircie | La souris la survole |
| Bandeau noir, vague de barres qui monte | J'écoute |
| Bandeau orange, ondulation lente | Je prépare le modèle |
| Bandeau noir, ondulation lente | Je transcris |
| Coche verte | Texte inséré |
| Pulsation grise | Annulé (appui trop court, ou rien dit) |
| Bandeau rouge | Erreur — détail dans le journal |

Un appui bref sur ⌘ droite ne déclenche rien, et ⌘ droite + une autre touche
reste un raccourci normal.

## Vocabulaire

`~/.config/dictee/vocabulaire.txt` — un terme par ligne. Sans lui,
« netlinking » devient « net linking ».

**Maximum 60 termes et 223 tokens Whisper.** Le worker conserve des termes
complets dans le budget réel du tokenizer. Il prévient dans le journal si
le vocabulaire est tronqué. Les modifications sont prises en compte à la
prochaine demande, sans relancer l’app.

## Historique

Toutes les dictées sont conservées dans `~/.config/dictee/historique.jsonl`
(une ligne JSON par dictée, ~200 octets). Cet historique ne contient que le texte. Les audios à réessayer sont conservés séparément, au plus 24 heures pendant que l’app fonctionne.

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
swift test                                                    # tests Swift
.venv/bin/python -m pytest worker/tests/test_filtres.py -q     # tests rapides
.venv/bin/python -m pytest worker/tests/test_integration.py \
  -q -m lent -c worker/pytest.ini                              # intégration avec le modèle local
```

## Checklist de vérification manuelle

Ce qu'aucun test automatisé ne couvre : le tap système, la pastille à l'écran,
le collage dans une vraie application. À dérouler après chaque `./build.sh`.

- [ ] Les trois autorisations sont **toujours** accordées (si elles sautent,
      le certificat de signature a changé)
- [ ] `swift test` : tous les tests au vert
- [ ] `.venv/bin/python -m pytest worker/tests/test_filtres.py -q` : tous au vert
- [ ] Dictée nominale de 3 s dans TextEdit → texte inséré
- [ ] Même chose dans Chrome, Slack et VS Code
- [ ] ⌘ droite brève → pulsation grise, rien d'inséré
- [ ] ⌘ droite + C → copie normale, aucune dictée
- [ ] ⌘ **gauche** maintenue → aucune réaction
- [ ] Silence de 3 s sous ⌘ droite → pulsation grise, aucune demande de
      transcription (le réveil du moteur reste possible)
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
                       └─ mlx-whisper large-v3-turbo, modèle à la demande
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

## Mesures et validation

Le journal inclut les durées d’import, de préparation, de VAD, d’inférence,
l’attente du worker, le nombre de passes et la mémoire active/cache/pic MLX.
La latence relâchement → collage mesure l’envoi du raccourci, pas la réception
par l’application cible. Le texte dicté n’est pas recopié dans ces métriques.

```bash
.venv/bin/python -m pytest worker/tests -q -c worker/pytest.ini
DICTEE_TEST_MODELE=1 swift test --filter vraiModeleLocal
```

`worker/requirements.lock` fige toutes les versions Python. `install.sh`
synchronise aussi les venv existants. Il réutilise le modèle présent dans le
cache Hugging Face ; il ne télécharge que s’il manque. Pendant l’usage,
le worker est forcé hors ligne et signale un cache absent/incomplet.
