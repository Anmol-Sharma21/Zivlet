# 16a. Transcription evidence: accuracy, speed, router, permissions, test plan

> Split out of [16-transcription.md](16-transcription.md) on import (2026-10-22). Section numbers match the design
> (§3 Evidence, §11 Test plan), so "16 §3.3" and "16a §3.3" mean the same table. Bare § references below point into
> 16. Evidence labels (MEASURED, RESCORED, TTS, INFERRED, SPIKE), the test machine and the limits of the corpus are
> defined at the top of 16. Every number here is our own measurement on public datasets (Google FLEURS hi_in and
> HumynLabs airline-support Hinglish, both CC-BY-4.0) or on macOS `say` TTS, run on 2026-10-21. The spikes' scripts,
> corpora and raw outputs are local prototypes and are not published.

## 3. Evidence

### 3.1 Accuracy (RESCORED, loose WER unless noted; lower is better)

TTS columns: `hi` (Lekha, 105 words), `devamix` (Hinglish read from Devanagari-with-English text), `alt` (Hinglish,
alternating hi/en voices), `mixed` (EN → HI → Hinglish blocks, 114 s), `long10` (602 s, 4 × en/hi/devamix/alt).
`hinglish_lekha_roman` is excluded: the Hindi voice mispronounces Latin text, so its reference is unreliable.

| Engine / setup | EN | hi | devamix | alt | mixed | **FLEURS real Hindi** (CER) | **Real Hinglish** (CER) | long10 | Real Hinglish strict, Devanagari file | Real Hinglish strict, Roman file |
|---|---|---|---|---|---|---|---|---|---|---|
| **Trelis-mc q5_0, chunked, auto, greedy** (chosen) | 0.007 | 0.078 | 0.027 | 0.040 | 0.076 | **0.163** (0.090) | **0.083** (0.042) | **0.052** | **0.198** | **0.172** (spike B romaniser) / 0.214 (spike C romaniser) |
| Apple ST hi-IN (macOS 27; Roman only) | 0.013 | 0.126 | 0.067 | 0.173 | 0.060 | 0.279 (0.158) | 0.266 (0.180) | 0.075 | — (no Devanagari) | 0.339 |
| Apple ST en-US, English only (spike A scorer) | 0.013 | — | — | — | — | — | — | — | — | — |
| Apple DT hi-IN (Devanagari, English transliterated or dropped) | 0.712 | 0.311 | 0.440 | 0.493 | 0.505 | 0.292 (0.213) | 0.380 (0.356) | — | 0.521 | — |
| Oriserve Apex q5_0, chunked, `en`, greedy (Roman only) | 0.013 | 0.068 | 0.027 | 0.067 | 0.030 | 0.210 (0.115) | 0.083 (0.044) | 0.033 | — | 0.208 |
| Stock large-v3-turbo q5_0, chunked, en/hi detect, Devanagari prompt (spike B) | 0.013 | 0.194 | 0.053 | 0.093 | 0.082 | 0.238 (0.113) | 0.161 (0.086) | 0.076 | 0.203 | 0.234 |
| Stock large-v3 q5_0, chunked, en/hi detect, no prompt | 0.020 | 0.165 | 0.307 | 0.227 | 0.115 | 0.172 (0.079) | 0.234 (0.133) | 0.122 | 0.370 | — |

From Spike C's table (same scorer), all rejected: Trelis without the mixedcode token (English written in Devanagari,
real Hinglish 0.266); IndicWhisper large-hi (EN 0.882); IndicConformer-hi (EN 0.725); Qwen3-ASR Hinglish (truncates,
FLEURS 0.931); vasista22 small (0.80 mean); Oriserve Swift (FLEURS 0.517); whisper base (real Hinglish 0.88, translates
to English even when forced to Hindi); stock turbo over whole files (loops, 0.27–0.91).

Reading the table:
- On **real speech**, Trelis has about half of Apple hi-IN's error on Hindi and a third on Hinglish. TTS hides this:
  on `mixed` Apple even wins (0.060 vs 0.076).
  > [challenge] "A third on Hinglish" means 16 vs 51 word errors on one scripted sentence (see the evidence note at the
  > top). Treat it as a direction, not a ratio, until TR-04.
- [challenge] **Pure Hindi pays for mixedcode in Auto.** Auto sends every non-English file down the mixedcode path,
  so formal Hindi loses about a third: Spike C's scorer gives FLEURS 0.150 with mixedcode vs 0.097 forced `hi` without
  it. With mixedcode Trelis wrote 28 % of FLEURS words in Latin (`deva_frac` 0.72), including hybrid words such as
  "ग्रीनland". §5.7 verification doesn't catch mixed-script words. Add a clean-up rule: a word that mixes Devanagari and
  Latin goes all-Devanagari in the Devanagari file. Also measure a per-chunk "Latin share < 5 % → re-decode without
  mixedcode" rule in TR-02. OWN-TR-10, adopted as the default on 2026-10-22, keeps mixedcode in Auto and names the
  "Hindi" setting as the option for formal Hindi.
- [challenge] **No punctuation or casing in Hindi/Hinglish output** (MEASURED, spike C's greedy outputs and the
  adversarial review). Mixedcode chunks come out lowercase with no punctuation: "…before monday ठीक है also please send…". English
  chunks detected as `hi` lose their punctuation too (the `mixed_blocks` output). Loose and strict WER both strip punctuation,
  so no gate sees this.
  - The TXT will be an unpunctuated wall of text, and the §5.6 cue rule "split at sentence end" will almost never
    fire.
  - Apex outputs *are* punctuated ("Meri flight delay ho gai. Next flight mein…").
  - Owner-visible: show sample output at TR-42, and add a "proper-noun/weekday casing" clean-up for Latin words.
- Apex matches Trelis on Hinglish and wins on TTS, but is weaker on real formal Hindi and has no Devanagari output.
- The real sets are small (12 clips; 8 readings of one sentence). TR-04 enlarges them before the gates are frozen.

Effect of the pipeline fixes (Spike B/C, MEASURED): whole-file decoding is unusable for Hindi. The 220-token-per-window
cap truncates and duplicates Devanagari, sometimes mid-character (invalid UTF-8). File-level auto-detect locks onto the
first 30 s (English loops over Hindi). Per-chunk free detection labels real Hindi as Urdu. Chunking (Trelis stock 30 s
windows: hi 0.495 → 0.078 chunked) and restricted detection fix all three.

### 3.2 Speed, memory, size

| Engine | 10-min file (602 s) wall | × realtime | Peak memory | Bundle cost | Download |
|---|---|---|---|---|---|
| Apple ST hi-IN | 26.4 s (54.7 s under load) | 22.8× | app 20 MB + `localspeechrecognition.xpc` 235–297 MB | 0 | 247 MB (OS) |
| Apple ST, 50 s English file | 1.35–1.6 s | 30–37× | same | 0 | 138 MB (OS) |
| **Trelis-mc q5_0 greedy** (quiet) | **287 s** | **2.1×** | 1.56 GB | helper (§9) | 1.08 GB |
| Trelis-mc q5_0 beam 5 | 1277 s | 0.5× | — | — | — |
| Apex q5_0 greedy (quiet) | 47 s | 12.8× | 0.76 GB | helper | 574 MB |
| Stock turbo q5_0 chunked | 180 s | 3.3× | 0.79 GB | helper | 574 MB |

Other MEASURED facts:
- First Apple results arrive ≈ 2 s after start. whisper Metal is ≈ 13× faster than CPU-only.
- The encoder dominates whisper time: every chunk is padded to 30 s, so fewer, longer chunks are faster (TR-02).
- CoreML encoder: not worth it (≈ 10 s load per launch, +1.17 GB download for turbo).
- Greedy decoding is almost as accurate as beam 5 for Trelis (mean loose WER 0.071 vs 0.065) and 4.4× faster (the beam run may have overlapped other GPU jobs).

### 3.3 Router evidence (MEASURED)

Since 2026-10-22 (OWN-TR-8 (a)) this probe runs only when the Hindi & Hinglish pack is not installed; with the pack,
Auto sends every file through the Hinglish model.

Mean word confidence from Apple `SpeechTranscriber` en-US on three 15 s windows (at 5 %, 50 % and 85 % of the file):

| File | 5 % | 50 % | 85 % | min | Route (min ≥ 0.80 → English) | Correct |
|---|---|---|---|---|---|---|
| en | 0.926 | 0.945 | 0.957 | 0.926 | English | yes |
| hi | 0.162 | 0.339 | 0.323 | 0.162 | Hindi/Hinglish | yes |
| hinglish_alt / devamix / roman | 0.455–0.533 | | | ≤ 0.473 | Hindi/Hinglish | yes |
| mixed_blocks (starts English) | **0.962** | 0.331 | 0.496 | 0.331 | Hindi/Hinglish | yes (a start-only probe would fail) |
| mixed_blocks_hi_first | 0.341 | **0.943** | 0.456 | 0.341 | Hindi/Hinglish | yes |
| real_fleurs_hi | 0.335 | 0.033 | 0.392 | 0.033 | Hindi/Hinglish | yes |
| real_hinglish | 0.261 | 0.500 | 0.515 | 0.261 | Hindi/Hinglish | yes |
| long10 | 0.982 | 0.896 | 0.029 | 0.029 | Hindi/Hinglish | yes |

Each window costs ≈ 1 s. `NLLanguageRecognizer` on romanised Hindi guesses id/nl/de/cs (spike A), so it is not
used. Not yet measured: **real Indian-accented English**, which may score below 0.80. Mis-routing English to the Hindi
route still gives a correct transcript (Trelis EN 0.007), just slower and with two identical-looking files (TR-04).

> [challenge] **The table is 8 TTS files plus 2 real ones, both Hindi-dominant. The failure mode that matters runs the
> other way.** Added in the adversarial review (MEASURED, TTS, the same probe with 15 s en-US windows):
>
> | File (TTS) | Content | en-US mean conf | Route | Apple en-US output for the Hindi words |
> |---|---|---|---|---|
> | r_en | Indian-English TTS (Rishi), pure English | 0.973 | English | — (correct) |
> | r_enhl | English-dominant Hinglish, Rishi | **0.910** | **English (wrong)** | "yaar" → "yeah", "theek hai" → "See, hi" |
> | l_enhl | same, Lekha, Hindi words in Devanagari | **0.878** | **English (wrong)** | "लेकिन यार" → "Like in Yard", "ठीक है" dropped, "deck" → "debt" |
> | s_enhl | same, Samantha | **0.900** | **English (wrong)** | — |
>
> Mis-routing in this direction is **not** fail-safe: Hindi words are rewritten as English or dropped, and the owner
> gets no Devanagari file. The asymmetry argues for an owner choice (OWN-TR-8):
> - **(a)** With the pack installed, Auto sends **every** file through Trelis. EN 0.007, so English stays correct,
>   but runs ≈ 10× slower. Apple English is used only when the pack is absent or the setting is English.
> - **(b)** Keep the probe but route to English only when min confidence ≥ 0.95 **and** a Trelis language-ID pass
>   (encoder only, ≈ 0.3 s per window, SPIKE) gives p(en) ≥ 0.98 on all three windows.
>
> Recommendation: **(a)**, because Hindi/Hinglish quality decides the engine (16 R-2). Adopted as the default on
> 2026-10-22.

### 3.4 Permissions and privacy (MEASURED)
- `SpeechAnalyzer` with `SpeechTranscriber` needs **no** Speech Recognition permission and no usage string. This was
  tested from a bare CLI and from an ad-hoc-signed hardened-runtime .app launched through LaunchServices. No prompt
  appeared and transcription worked.
- Legacy `SFSpeechRecognizer` hi-IN is server-only (`supportsOnDeviceRecognition = false`) and needs a prompt: banned.
- `lsof -i` during a 10-min Apple run: zero sockets in our process and in `localspeechrecognition.xpc`.
- whisper helper: ad-hoc-signed with `codesign -o runtime`, Metal works, no entitlements needed.

> [challenge] Permission evidence comes from macOS 27 with ad-hoc signing only. Before calling it "no prompt", TR-03
> must repeat it with the **Developer ID-signed, notarized** build on macOS 26.x, from a **fresh user account** (no
> earlier Speech grants). The word "prompt" in §2.1/§2.2 means *our* download card, not a macOS dialog. Say so, or
> readers will assume a TCC prompt. Reading dropped files from Desktop/Documents/Downloads is governed by the app's
> existing Files-and-Folders behaviour (ffmpeg already does this). Transcription adds nothing here, because the
> helper reads only our own WAV in Caches.

---

## 11. Test plan

### 11.1 Unit (`swift test`, pure, [TDD], no models)
- `HinglishRomanizer`: golden table of ≥ 300 words (schwa cases कमरा → kamra, समझना → samajhna, लड़का → ladka; nukta;
  anusvara; lexicon). Latin passes through byte-identical. Output contains no Devanagari. Property test: idempotent on
  Roman input.
- `CueSegmenter`: property tests (monotonic, no overlap, ≤ 2 × 42 graphemes, 1–7 s, every word in exactly one cue,
  identical timings for both scripts). Golden cues for the corpus word lists.
- Writers: golden TXT/SRT/VTT, including Devanagari, NFC/NFD input, hour rollover, `Timestamps in text`.
- `ChunkPlanner`: ≤ 20 s, cut at the quietest frame, full coverage, deterministic.
- `LanguageRouter`: the §3.3 table as fixtures (10/10), boundary values 0.79/0.80, short files, second-chance rule.
- `TranscriptCleanup`: zero-length drop, loop detector cases from Spike B ("इंग इंग इंग…", "the summer, the summer…"),
  casing rules, invalid-UTF-8 inputs never produce invalid output.
- `HelperProtocol`: round-trip and fuzzing of malformed JSON lines (truncated line, bad UTF-8, unknown event).
- `OutputNamer`: the §4.2 table, collisions, 255-byte truncation with Devanagari base names.

### 11.2 Integration (`.integration`, needs ffmpeg, helper and models from `Artifacts/`)
- Decode → helper on a 30 s fixture with a tiny test model: events parsed, progress monotonic.
- Cancel ≤ 1 s for helper and Apple. Staging empty afterwards. Orphan reaper kills a stray helper after a simulated
  app crash.
- Worker or helper crash → retried once, then "This file made the engine crash".
- Offline: full run with the network blocked passes when packs are present. With packs absent the card appears and CI
  stays green (NFR-23).
- TCC diff: zero new TCC entries after a transcription run.

### 11.3 Accuracy and speed gates (`make asr-eval`, local [HW] job; packs present; unified scorer ported from spike C's rules, run with `python3 -I`)

| Set | Engine | Metric | Gate | Measured now |
|---|---|---|---|---|
| English TTS (en) | Apple en-US / Trelis | loose WER | ≤ 0.03 | 0.013 / 0.007 |
| Hindi TTS (hi) | Trelis | loose WER / CER | ≤ 0.10 / ≤ 0.04 | 0.078 / 0.026 |
| Hinglish TTS (devamix, alt) | Trelis | loose WER each | ≤ 0.07 | 0.027, 0.040 |
| Mixed TTS (mixed_blocks, hi_first) | Trelis via router | loose WER | ≤ 0.10 | 0.076, 0.036 |
| **Real Hindi (FLEURS 12)** | Trelis | loose WER / CER | **≤ 0.20 / ≤ 0.11** | 0.163 / 0.090 |
| **Real Hinglish (HumynLabs 8)** | Trelis | loose WER; strict WER Devanagari file; strict WER Roman file | **≤ 0.12; ≤ 0.25; ≤ 0.22** | 0.083; 0.198; 0.172 |
| Real Hinglish | Apple hi-IN fallback | loose WER | ≤ 0.32 | 0.266 |
| long10 (602 s) | router + Trelis | loose WER; last cue end vs duration; overlaps | ≤ 0.07; ±1 s; 0 | 0.052; —; — |
| Router (no pack; OWN-TR-8 (a)) | probe | files routed correctly | 10/10 corpus + TR-04 real sets ≥ 95 % | 10/10 |
| Script form | Trelis | Roman file Devanagari chars; Devanagari file: share of reference English words written in Latin (real Hinglish) | 0; ≥ 80 % | —; SPIKE |
| Speed, quiet M2 Pro | Apple en / Trelis | × realtime on long10 | ≥ 15× / ≥ 2× (target 3× after TR-02) | 23–37× / 2.1× |
| Speed, M1 Air 8 GB [HW] | Trelis | × realtime; peak RSS | ≥ 1× ; ≤ 2.0 GB | SPIKE |
| Size | build | installed / DMG delta | ≤ +7.5 MB / ≤ +2 MB | 6.7 / 1.56 (helper) |

- TR-04 re-baselines the real-speech gates on the larger sets: gate = measured + 25 %, never looser than the table above.
- Any engine, model or patch change must re-run the full table.

> [challenge] Gate fixes:
> - **Real Hinglish (HumynLabs 8) measures closeness to a script.** Re-transcribe the 8 clips verbatim, in both
>   scripts, by a human (TR-04) before using them as a gate. Until then, label the gate "scripted, TTS-adjacent".
> - **Add an English-dominant Hinglish set** (TTS now, real at TR-04) to the router row. Pass bar: 100 % routed to the
>   Hindi route, and the Devanagari file keeps the Hindi words (e.g. "ठीक है", "लेकिन यार").
> - **Add timing rows:**
>   - mid-chunk onset error: median ≤ 0.25 s, p95 ≤ 0.6 s on the review's TTS timing fixture (six phrases at known
>     onsets 0, 2.168, 4.51, 6.863, 9.097 and 11.388 s) plus the real clips;
>   - max cue duration ≤ 7 s;
>   - `t_dtw` never −1.
> - **Speed row:** measure with DTW on (SRT) and off (Text) separately. The 2.1× baseline is DTW off.
> - **Mark which rows are TTS-only:** en, hi, devamix, alt, mixed and long10. Real-speech gates are binding;
>   TTS-only gates are regression alarms.
> - Every row must use the decoding config that ships (§2.1 challenge).

### 11.4 Manual QA
- [QA] Player auto-load of `<base>.srt` and `<base> Devanagari.srt` in QuickTime, IINA and VLC.
- [QA] Devanagari rendering in TextEdit, Notes and Pages.
- [QA][OWNER] The owner reads one Roman and one Devanagari output and approves the spelling and naming (OWN-TR-1).
- [HW] macOS 26.x VM or device: Apple en path, hi-IN hidden if unsupported, no prompts.
- [HW] 8 GB M1: 1-hour file finishes, no memory-pressure kill, ETA within ±20 %.

