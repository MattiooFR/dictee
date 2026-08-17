"""Faux worker pour les tests : même protocole, aucun modèle.
Modes : ok | erreur | meurt | lent
"""
import json
import sys
import time

mode = sys.argv[1] if len(sys.argv) > 1 else "ok"
print(json.dumps({"ready": True}), flush=True)

for ligne in sys.stdin:
    chemin = ligne.strip()
    if not chemin:
        continue
    if mode == "lent":
        time.sleep(10)
    elif mode == "meurt":
        sys.exit(3)
    elif mode == "erreur":
        print(json.dumps({"error": "micro cassé"}), flush=True)
    else:
        print(json.dumps({"text": "bonjour " + chemin.split("/")[-1], "sec": 0.2}), flush=True)
