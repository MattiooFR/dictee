#!/bin/bash
# Compile et assemble Dictee.app. SwiftPM ne sait pas produire de bundle
# d'application : on l'assemble à la main.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITE="Dictee Dev"
APP="Dictee.app"

if ! security find-identity -v -p codesigning | grep -q "$IDENTITE"; then
  echo "✗ certificat « $IDENTITE » absent."
  echo "  Trousseau d'accès → Assistant de certification → Créer un certificat"
  echo "  Nom : $IDENTITE · Type : Racine auto-signée · Certificat : Signature de code"
  echo
  echo "  Sans lui, macOS voit chaque recompilation comme une nouvelle app et"
  echo "  réinitialise les trois autorisations (micro, entrées, accessibilité)."
  exit 1
fi

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Dictee "$APP/Contents/MacOS/Dictee"
cp Ressources/Info.plist "$APP/Contents/Info.plist"

# Pas de --options runtime : le hardened runtime exigerait des droits
# audio-input et un profil de provisionnement, pour une app ni notariée ni
# distribuée. Ce serait un mode d'échec gratuit.
codesign -s "$IDENTITE" --force "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority" || true
echo "✓ $APP prêt"
