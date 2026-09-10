"""Processus contrôlé pour tester le protocole sans GPU."""
import json
import sys
import time

mode = sys.argv[1] if len(sys.argv) > 1 else 'ok'
if mode == 'demarrage_lent':
    time.sleep(0.7)
print(json.dumps({'ready': True}), flush=True)
for line in sys.stdin:
    try:
        q = json.loads(line)
    except ValueError:
        q = {'cmd': 'transcribe', 'path': line.strip(), 'id': 'legacy'}
    id_ = q['id']
    if q['cmd'] in ('warmup', 'purge'):
        if mode == 'warmup_lent':
            time.sleep(0.6)
        print(json.dumps({'id': id_, 'done': q['cmd']}), flush=True)
        continue
    path = q['path']
    if mode == 'lent' or (mode == 'lent_chemin' and path.endswith('lent.wav')):
        time.sleep(10)
    if mode == 'meurt':
        sys.exit(3)
    if mode == 'erreur':
        print(json.dumps({'id': id_, 'error': 'micro cassé'}), flush=True)
        continue
    if mode == 'perime':
        print(json.dumps({'id': 'ancienne-demande', 'text': 'ancienne dictée', 'sec': 0.1}), flush=True)
    print(json.dumps({'id': id_, 'text': 'bonjour ' + path.split('/')[-1], 'sec': 0.2}), flush=True)
