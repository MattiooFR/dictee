# Dictée

Hold **Right ⌘**, speak, release. The text appears at your cursor, in any app.

100% local speech-to-text for macOS, running `mlx-whisper large-v3-turbo` on
your Mac's GPU. No network calls, no subscription, no audio ever leaves the
machine.

*[Version française](README.fr.md)*

> **Currently French-only.** The model is pinned to `language="fr"` for
> accuracy. Changing it is a one-line edit — see
> [Using another language](#using-another-language).

---

## What it does

- **Push-to-talk on Right ⌘** — a key macOS does nothing with when held alone,
  so there is no shortcut to sacrifice
- **Click-to-record** — click the edge pill to record hands-free; click again
  or press Right ⌘ to stop
- **Every dictation is kept** — triple-tap Right ⌘ to open a searchable
  history window
- **A pill at the right edge** shows what's happening: a wave of bars rides up
  it while you speak

The Whisper model stays loaded in RAM (~1 GB), so a dictation comes back in
1–2 seconds, every time.

## Requirements

- **Apple Silicon Mac** — `mlx-whisper` is built on Apple's MLX framework and
  will not run on Intel
- **macOS 14** or later
- **Xcode** or the Command Line Tools (for `swift build`)
- [**uv**](https://github.com/astral-sh/uv) — `brew install uv`
- ~1 GB of RAM for the resident model, ~1.5 GB of disk for the model weights
  (downloaded once, into the shared Hugging Face cache)

## Install

### 1. Create a self-signed code-signing certificate (once)

Keychain Access → menu **Certificate Assistant** → *Create a Certificate*:

- Name: `Dictee Dev`
- Identity Type: **Self Signed Root**
- Certificate Type: **Code Signing**

Verify with `security find-identity -p codesigning` — it should list
`Dictee Dev`.

> **Note the missing `-v`.** A self-signed root always reports
> `CSSMERR_TP_NOT_TRUSTED`, and `-v` filters it out. That is expected and
> harmless: trust is about *verifying* a signature, not producing one.
> `codesign` accepts the certificate fine.

**Why this matters.** macOS ties permissions (microphone, input monitoring,
accessibility) to the app's code identity, expressed as a designated
requirement:

```
identifier "com.dugmedia.dictee" and certificate leaf = H"<certificate hash>"
```

Bundle identifier plus certificate — never the binary hash. That is what lets
your permissions survive a rebuild. Signed ad-hoc, the app's only identity
would be its hash, and **all three permissions would reset on every build**.

### 2. Build and install

```bash
git clone https://github.com/MattiooFR/dictee.git
cd dictee
./install.sh
```

This builds the app, creates the Python virtualenv, installs a starter
vocabulary and registers a LaunchAgent so Dictée starts at login.

### 3. Grant three permissions

| Permission | Why | Where |
|---|---|---|
| Input Monitoring | Listen for Right ⌘ | Settings → Privacy & Security |
| Accessibility | Post the synthetic ⌘V | Settings → Privacy & Security |
| Microphone | Capture your voice | Dialog on first launch |

All three are requested **at startup**, never mid-dictation — a permission
dialog during push-to-talk would swallow your sentence.

While any is missing, the pill stays red and the app waits. **Nothing to
restart**: it re-checks every 2 seconds and starts on its own once you grant.
The log tells you which one is missing.

## Usage

Hold Right ⌘, speak, release. The pill at the right edge of the screen shows
the state:

| Pill | State |
|---|---|
| Thin grey bar, flush to the edge | Idle |
| Wider, lighter bar | Your mouse is hovering it |
| Dark band, wave of bars riding up | Listening |
| Dark band, slow ripple | Transcribing |
| Green checkmark | Text inserted |
| Grey pulse | Cancelled — tap too short, or nothing said |
| Red band | Error — details in the log |

A quick tap does nothing, and Right ⌘ + any other key stays a normal shortcut:
the event tap is passive and never swallows your keystrokes.

**Hands-free**: click the pill to start recording without holding anything.
Click again, or press Right ⌘, to stop. In this mode typing does not cancel.

**History**: triple-tap Right ⌘.

| Key | Action |
|---|---|
| Search field | Filters as you type, ignoring case and accents |
| Click a row | Copies the text |
| ⏎ | Pastes it back into the app you came from |
| ⌫ | Deletes the entry |
| Esc | Closes the window |

Everything is stored as JSON Lines in `~/.config/dictee/historique.jsonl`
(~200 bytes per dictation). Only text is kept — audio is never stored, and the
temporary WAV is deleted right after transcription.

## Vocabulary

Whisper mangles words it has never seen: *netlinking* becomes *net linking*,
*Supabase* becomes *super base*. Seeding it with your own terms fixes this.

Edit `~/.config/dictee/vocabulaire.txt`, one term per line, then restart:

```bash
launchctl kickstart -k gui/$UID/com.dugmedia.dictee
```

**Keep it under 60 terms.** Whisper caps `initial_prompt` at 224 tokens, and
going over *degrades* transcription rather than improving it. The worker
truncates and warns in the log. Twenty terms that matter beat sixty at random.

## Using another language

The model is pinned to French in `worker/transcribe.py`:

```python
LANGUE = "fr"
```

Change it to any [Whisper language code](https://github.com/openai/whisper#available-models-and-languages)
(`"en"`, `"es"`, `"de"`…) and restart. Forcing a language is deliberate:
auto-detection misfires on short clips and on sentences full of foreign
technical terms, which is most of what people dictate.

Making this configurable without editing code would be a welcome contribution.

## How it works

```
 Right ⌘ ─▶ Dictee.app (Swift, LSUIElement agent)
              ├─ CGEventTap (passive)     listens for Right ⌘
              ├─ AVAudioEngine            audio + RMS level
              ├─ NSPanel (non-activating) the pill, clickable
              ├─ NSPasteboard + CGEvent   the paste
              ├─ JSONL history            ~/.config/dictee
              └─▶ Python worker (child process, stdin/stdout)
                    └─ mlx-whisper large-v3-turbo, model resident in RAM
```

Two processes, one lifetime. The LaunchAgent starts the app at login; the app
starts the Python worker and keeps it alive, restarting it if it dies. The
worker's contract is one WAV path per line on stdin, one JSON line back on
stdout.

Three design decisions worth knowing about:

- **The event tap is passive** (`listenOnly`), so Right ⌘ keeps working in
  every shortcut you already use.
- **The pill is a non-activating `NSPanel`** sized to its own shape. It
  receives clicks without stealing focus — which is what lets the synthetic
  ⌘V land in the app you were writing in — and it stays small enough not to
  swallow clicks meant for a scrollbar underneath.
- **Recording starts before the 250 ms guard**, so the first word is never
  clipped; the pill only opens once the guard passes, so a Right ⌘ shortcut
  does not make it flash.

## Development

```bash
swift build
swift test                                                   # 41 tests

.venv/bin/python -m pytest worker/tests/test_filtres.py -q    # fast
.venv/bin/python -m pytest worker/tests/test_audio.py -q      # fast
.venv/bin/python -m pytest worker/tests/test_integration.py \
  -q -m lent -c worker/pytest.ini                             # loads the model
```

Each system-facing module has a standalone diagnostic subcommand, so you can
check one piece without the rest of the app:

```bash
swift run Dictee --test-micro          # VU meter, writes a 3 s WAV
swift run Dictee --test-clavier        # logs Right ⌘ presses
swift run Dictee --test-collage TEXT   # pastes TEXT after 3 s
swift run Dictee --test-pastille       # cycles through the pill states
```

The event tap, the pill rendering and the paste depend on the window server,
audio hardware and TCC state — they are verified by a manual checklist in
[README.fr.md](README.fr.md), not by automated tests. The code and comments
are in French.

## Known limitations

- Apple Silicon only
- French by default (one-line change, see above)
- No settings UI — configuration is two text files
- Right ⌘ is not remappable without editing `Declencheur.swift`

## License

MIT — see [LICENSE](LICENSE).
