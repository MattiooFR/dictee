#!/bin/bash
# Installe Dictée : venv, vocabulaire, LaunchAgent, premier lancement.
set -euo pipefail
cd "$(dirname "$0")"
RACINE="$PWD"
ETIQUETTE="com.dugmedia.dictee"
PLIST="$HOME/Library/LaunchAgents/$ETIQUETTE.plist"
CONFIG="$HOME/.config/dictee"

./build.sh

if [ ! -x .venv/bin/python ]; then
  echo "→ création du venv"
  uv venv --python 3.11
fi
# Vérifie aussi les dépendances lors d'une mise à jour d'un venv existant.
uv pip sync --python .venv/bin/python worker/requirements.lock
.venv/bin/python worker/installer_modele.py

mkdir -p "$CONFIG"
if [ ! -f "$CONFIG/vocabulaire.txt" ]; then
  cp worker/vocabulaire-defaut.txt "$CONFIG/vocabulaire.txt"
  echo "→ vocabulaire installé dans $CONFIG/vocabulaire.txt"
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTFIN
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$ETIQUETTE</string>
  <key>ProgramArguments</key>
  <array><string>$RACINE/Dictee.app/Contents/MacOS/Dictee</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>DICTEE_ROOT</key><string>$RACINE</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/dictee.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/dictee.log</string>
</dict>
</plist>
PLISTFIN

launchctl bootout "gui/$UID/$ETIQUETTE" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"

cat <<'FIN'

✓ installé.

Trois autorisations à accorder, dans cet ordre :
  1. Micro           — demandé au démarrage
  2. Surveillance des entrées — Réglages → Confidentialité et sécurité
  3. Accessibilité   — Réglages → Confidentialité et sécurité

Ajouter Dictee.app dans les listes 2 et 3, puis relancer :
  launchctl kickstart -k gui/$UID/com.dugmedia.dictee

Journal : tail -f ~/Library/Logs/dictee.log
FIN
