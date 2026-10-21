# 16. Transcription: audio and video → transcript (English, Hindi, Hinglish)

> Imported into the repository on 2026-10-22 from the transcription design draft of 2026-10-21. The evidence
> (accuracy, speed, router and permission measurements) is split out into
> [16a-transcription-evidence.md](16a-transcription-evidence.md), which keeps this file's section numbers (§3 and
> §11). Task rows are in [05b-task-additions-transcription.md](../plan/05b-task-additions-transcription.md). The
> spikes' scripts, corpora and raw outputs are local prototypes and are not published; only the results are recorded
> here.

Date: 2026-10-21 (imported 2026-10-22). Status: **design proposal**. OWN-TR-8, OWN-TR-9 and OWN-TR-10 were adopted as
defaults on 2026-10-22 (§14, [00-decisions.md](00-decisions.md)); OWN-TR-1 … OWN-TR-7 are still open at their
recommendations. Fills the slot reserved by [17-feature-roadmap.md §7](17-feature-roadmap.md) (P3-111, FR-138,
`TRANSCRIBE` slice, History kind `transcribe`, CLI verb `zivlet transcribe`) and answers what
[17d-media-ai.md §9](17d-media-ai.md) needs from it.

Scope: one drop of an audio or video file on `TRANSCRIBE` produces a transcript (TXT) and/or subtitles (SRT/VTT)
beside the original, on device, for English, Hindi, Hinglish (Hindi and English mixed inside one sentence) and files
that switch between them. Out of scope: translation (P3-112), meeting notes and speakers (P4-100/101), burn-in
subtitles (owner said NO), live dictation, microphone input.

Inputs read: `00-decisions.md` (§(d) transcription, O-3 size, OWN-MA-*), `10-tech-strategy.md` (§9 size, §13 spikes),
`11-media-engine.md` (ffmpeg helper, §8 runner), `14-app-platform.md`, `17-feature-roadmap.md` (§7, §8.1 caps, §9 size),
`17d-media-ai.md` (§9, §10 model packs), `docs/plan/01-prd.md`, `01b-prd-additions.md` (FR-137…141, NFR-23/24),
`02-architecture.md` (§2 processes, §4 modules, R1–R9), `03a` (§4.3 staging and publish, §4.4 naming, §4.5 progress,
§4.6 cancellation), `03b`, `05-task-list.md` (§9, P3-109…112). Owner answers of 2026-10-21, recorded in
[00-decisions.md](00-decisions.md) §(d): English, Hindi, Hinglish and mixes of the three; both script files for
Hindi/Hinglish, one file for pure English; no owner recording, so only TTS and freely licensed public recordings,
labelled. Evidence: three local spikes run on 2026-10-21 (A: Apple Speech; B: whisper.cpp; C: Hindi and Hinglish
fine-tunes of Whisper and other Indic models) and an adversarial review of this design the same day.

Principles applied: offline and on device, no telemetry, no permission prompts, bundle ≤ 70 MB with large models as
optional downloads, clean room (nothing from the reference app or Open-Tangerine).

### Evidence labels and test machine
- **MEASURED**: our own runs on the development Mac (Apple M2 Pro, 16 GB, macOS 27.0 build 26A428, `MacOSX27.0.sdk`,
  Homebrew ffmpeg 8.1.2, whisper.cpp v1.9.5 commit d1be6fd with Metal). Other agents loaded the machine (load average
  3–296) during most runs, so every speed figure is a **lower bound** unless marked "quiet". Accuracy is not affected
  by load.
- **RESCORED**: all saved transcripts from spikes A, B and C were re-scored with **one** scorer for this document
  (spike C's scoring rules). The three spikes each used a different scorer, so their own numbers are not comparable
  with each other; the tables here are.
- **VERIFIED-SDK / VERIFIED-UPSTREAM / VERIFIED-WEB**: read from the SDK, upstream source at a pinned tag, or dated web
  sources. **INFERRED**: engineering judgement. **SPIKE**: must be measured before the decision is final.
- **Corpus** (local, never committed): TTS from macOS `say` (Samantha en_US, Lekha hi_IN, Rishi en_IN;
  far cleaner than real speech, so treat TTS numbers as best case), plus **real speech**: 12 Google FLEURS hi_in clips
  (141 s, read Hindi, CC-BY-4.0) and 8 HumynLabs airline-support Hinglish clips (96 s, noisy phone quality, one
  scripted sentence, CC-BY-4.0). The owner supplied **no recordings**. References exist in both forms: Roman
  ("Kal meeting mein humne decide kiya") and Devanagari with English words kept in Roman ("कल meeting में हमने decide
  किया").
- **Metrics**: WER/CER, plus **loose WER** (transliteration-insensitive: both sides romanised and phonetically folded,
  so "हमने" = "humne" = "hamne"; floor ≈ 0.01–0.03 on a perfect Hindi transcript). Strict WER is also given against
  the reference in the script the engine wrote.

> [challenge] **What the evidence covers.** These limits apply to every Hinglish claim below.
> - **"Real Hinglish" is one scripted sentence** (24 words) read by 8 speakers: 192 reference words. The reference is the
>   *script*, not a verbatim transcript, and speakers drift from it. Trelis's 16 "errors" are mostly real speech that
>   isn't in the script: "हो गई **है**", "**please कुछ करिए**", "सकते हैं **क्या**", a repeated "पहुँचा". Apex makes the
>   same 16. This set is near its ceiling, so it **can't rank the top engines**. It only shows that Trelis/Apex (16
>   errors) beat stock turbo (31) and Apple hi-IN (51) on this sentence. The two female speakers are
>   scored against "फँसा … चाहता"; they may have said the feminine "फँसी … चाहती".
> - **There is no real conversational or English-dominant Hinglish** ("So basically we decided…, लेकिन यार…"). Every
>   number for that kind of speech is **TTS-only**.
> - `mixed_blocks`, `mixed_blocks_hi_first`, `long10`, `hi`, `devamix` and `alt` are **TTS**. The TL;DR's "10-min
>   mixed file 0.052" is a TTS number.
> - FLEURS-hi and Common Voice hi appear as benchmarks on the Trelis model card, so its authors evaluated on them (and
>   may have tuned toward them). Use only the test splits, and prefer sets that aren't on the card (TR-04).

---

## 0. TL;DR

- **Two engines, chosen per file, one slice.**
  - **English → Apple `SpeechTranscriber`** (Speech framework, `SpeechAnalyzer`). +0 MB, 23–37× realtime, WER 0.013 on
    English, no permission prompt, model managed by macOS. English is a launch language on macOS 26.
  - **Hindi, Hinglish and mixed files → whisper.cpp with the Trelis Hinglish model** (`Trelis/whisper-hinglish-preview`,
    Apache-2.0, a Whisper large-v3 fine-tune), converted by us to ggml q5_0 and offered as a one-time **1.08 GB
    "Hindi & Hinglish" pack**. It is the best engine measured on every Hindi/Hinglish set, real speech included
    (loose WER: real Hinglish **0.083**, real Hindi **0.163**, 10-min mixed file **0.052**).
    > [challenge] **Not "best on every set".** In [16a §3.1](16a-transcription-evidence.md):
    > - Apex beats Trelis on TTS `hi` (0.068), `mixed` (0.030) and `long10` (0.033), and **ties** it on real Hinglish
    >   (0.083: the same 16 of 192 words).
    > - Apple hi-IN beats Trelis on TTS `mixed` (0.060).
    > - Stock large-v3 has the lower FLEURS CER (0.079 vs 0.090).
    >
    > What the evidence supports: Trelis is best on real Hindi loose WER (0.163 vs 0.172 for large-v3 and 0.210 for
    > Apex). It is tied-best on one real scripted Hinglish sentence. It is the only engine that writes the owner's
    > Devanagari-with-Roman form natively. "10-min mixed file 0.052" is **TTS**.

    It writes the owner's
    Devanagari form directly ("मेरी flight delay हो गई है"), and a rule-based romaniser derives the Roman file from the same
    pass (real Hinglish strict Roman WER **0.172**, better than any engine's native Roman output).
- **Auto language (default), as adopted on 2026-10-22 (OWN-TR-8 (a)):** with the Hindi & Hinglish pack installed,
  Auto sends **every** file through the Hinglish model, English included (English loose WER 0.007, but about 10×
  slower than Apple). Apple English runs only when the pack is not installed or Language = English.
- **The probe (used only without the pack):** it costs about 3 s and needs no download. Three 15 s windows of the
  file go through Apple's en-US model; if every window has mean word confidence ≥ 0.80 the file is English, otherwise
  it takes the Hindi/Hinglish route (which then offers the pack). MEASURED 10/10 corpus files routed correctly
  (English windows 0.93–0.96; Hindi/Hinglish windows 0.03–0.53).
  > [challenge] **English-dominant Hinglish goes to the English engine** (MEASURED in the adversarial review, **TTS
  > only**). Three English-dominant Hinglish clips ("So basically we decided…, but yaar…, toh…, theek hai?")
  > were read by Rishi en-IN, Lekha hi-IN and Samantha. Their en-US mean confidence was **0.910, 0.878 and 0.900**, all
  > above 0.80, so all three route to English. Apple en-US then rewrites the Hindi words as English: "yaar" → "yeah",
  > "toh" → "so", "theek hai" → "See, hi", "लेकिन यार" → "Like in Yard", and "ठीक है" is dropped.
  > - The owner gets one English-looking file and no Devanagari file.
  > - The §5.3 second-chance rule doesn't fire: whole-file confidence stays high.
  > - On the same three clips Trelis (mixedcode) keeps "लेकिन यार", "तो" and "ठीक है".
  > - No threshold separates the two cases: English windows go as low as 0.896, and these clips sit at 0.878–0.910.
  >
  > This is a likely real-world mix for the owner, so it became an owner decision (**OWN-TR-8**, §14). Adopted
  > 2026-10-22: option (a), which is why Auto skips the probe when the pack is installed.
- **Owner's two files.** Hindi/Hinglish always saves both scripts by default: `<name> Transcript.txt` (Roman) and
  `<name> Transcript Devanagari.txt`. English saves one file. Subtitles follow the same rule (`<name>.srt`,
  `<name> Devanagari.srt`).
- **Fallback without the pack (macOS 27+ only):** Apple `SpeechTranscriber` hi-IN gives a Roman-only transcript with no
  pack download; macOS downloads its own Indic model (about 250 MB) instead. Real Hinglish loose WER 0.266, about 3×
  Trelis's error. It is offered on the download card, never silently.
- **Pipeline:** bundled ffmpeg → 16 kHz mono WAV → route → engine → clean-up → script forms → cue segmenter →
  TXT/SRT/VTT writers → verify → atomic publish. whisper runs in a new signed helper, `zivlet-whisper`, spawned by the
  worker like ffmpeg: VAD-chunked (≤ 20 s), per-chunk en/hi detection, the `<|mixedcode|>` token (a 40-line
  whisper.cpp patch), greedy decoding, no cross-chunk context.
- **Modules:** new pure `ZivletTranscript` (model, router, chunk planner, cue segmenter, romaniser, clean-up, TXT
  writer; `swift test`), new `EngineSpeech` (plans, Apple runner, helper client), existing `EngineSubtitles` (SRT/VTT).
- **Size:** helper code ≈ 1.5 MB plus the Metal shader library (5.2 MB embedded; precompiled size SPIKE). MEASURED
  minimal helper: **6.7 MB installed, 1.6 MB compressed**. Models are never in the bundle. This pushes the expected
  install above the 70 MB target (below the 85 MB gate): owner decision OWN-TR-3.
- **Speed is the main cost:** Trelis runs at **2.1× realtime** (quiet M2 Pro; 1 h of audio ≈ 28 min). TR-02 targets
  ≥ 3× before 1.0.
  > [challenge] **The 2.1× figure has no word timestamps.** Trelis emits no timestamp tokens, so the 1–7 s subtitle
  > cues in §5.6 need DTW word times.
  > - In whisper.cpp v1.9.5, **DTW is silently disabled when flash attention is on**, and flash attention is the
  >   default (`whisper.cpp:3820`, VERIFIED-UPSTREAM). With the design's settings every token came back with
  >   `t_dtw = -1` (MEASURED).
  > - With `-nfa` (flash attention off) DTW works. On 91 s of real Hinglish (8 clips, load 5–9) the run took
  >   **35–40 s instead of 28 s, about 25–40 % slower**. Expect ≈ 1.5–1.7× realtime when subtitles are written.
  > - TR-02 lists flash attention as a speed lever, which conflicts with DTW.
  > - Fix: request DTW (and so flash attention off) **only when the output includes SRT/VTT or text timestamps**.
  >   Text-only jobs keep flash attention. See OWN-TR-9, adopted 2026-10-22.
- **Phase:** spikes TR-01…TR-07 can run before Phase 3 (prototypes only, no app code); build in **Phase 3 wave 3B (1.0)**, replacing P3-111,
  after P3-109 (model packs), shipping with P3-112 (translate).

---

## 1. Requirements

| # | Requirement | Source |
|---|---|---|
| R-1 | Drop audio or video → transcript, zero-click, beside the original | 00 §(b), FR-138 |
| R-2 | English, Hindi, Hinglish and mixes; **Hindi/Hinglish quality decides** the engine | owner answers (the weighting is this design's reading: English is served well by any engine measured) |
| R-3 | Hindi/Hinglish: **both** a Roman file and a Devanagari file (English words kept in Roman); one file for English; distinguishable names consistent with 03a §4.4 | owner answers |
| R-4 | Offline, on device, no telemetry, no TCC prompt | 00, FR-137, NFR-23 |
| R-5 | Bundle ≤ 70 MB; models are optional, verified, user-initiated downloads | O-3, FR-137, P3-109 |
| R-6 | Segments with timestamps (word times where available), a language tag per segment and both script forms, held in an internal model | 17d §9, 17 §7 |
| R-7 | A `task=translate` decision; shared model-pack mechanism; a phase | 17d §9 |
| R-8 | Progress, cancel ≤ 1 s, never a partial file at the final name | 03a §4.5–4.6 |

---

## 2. Decision

### 2.1 Engine per language case

| Case (from the router, §5.3) | Engine | Output files (default) | Download needed |
|---|---|---|---|
| English (pack not installed, or Language = English) | Apple `SpeechTranscriber`, locale en-US (or the Mac's English locale if supported, e.g. en-IN) | 1: Roman/English | Apple English model if macOS hasn't installed it (≈ 138 MB, macOS-managed, our card) |
| Any file in Auto with the pack installed (OWN-TR-8 (a), adopted 2026-10-22) | whisper.cpp + Trelis pack, as the Hinglish row | 2, or 1 when the Devanagari text has no Devanagari characters (§4.2) | — |
| Hindi | whisper.cpp + Trelis pack, every chunk forced `hi`, **no** mixedcode token | 2: Roman + Devanagari | Hindi & Hinglish pack, 1.08 GB |
| Hinglish / mixed / Auto-non-English | whisper.cpp + Trelis pack, per-chunk en/hi detection, mixedcode token on `hi` chunks | 2: Roman + Devanagari | Hindi & Hinglish pack |
| Hindi/Hinglish, pack declined, macOS 27+ | Apple `SpeechTranscriber` hi-IN (= mul-IN) | 1: Roman only, card says why | Apple Indic model ≈ 247 MB (macOS-managed, our card) |
| English, Apple model unavailable, pack installed | whisper.cpp + Trelis, forced `en` | 1 | — |

> [challenge] **The decoding that was measured is not the decoding specified here or in §5.2.** Every "chosen" Trelis
> number (spike C's chunked, greedy, auto-language q5_0 run) came from:
> - whisper-cli `-l auto`: **free detection over all 99 languages**, not the restricted en-vs-hi rule;
> - `WHISPER_EXTRA_LANG_TOKEN=51866`, which puts `<|mixedcode|>` on **every** chunk, `en` chunks included.
>
> The rows above ("per-chunk en/hi detection, mixedcode on `hi` chunks"; English chunks plain `en`) were never run with
> Trelis. Cheap check in the review (TTS): on English-dominant Hinglish, Trelis detects `en` (p = 0.69–0.998).
> - `en` + mixedcode keeps "ठीक है" in Devanagari.
> - `en` without mixedcode (this design) writes "**Thick hai**".
>
> **Fix:** on the Hindi route, put mixedcode on every chunk, as measured. Keep restricted detection only to choose the
> language token (stopping Urdu script), and re-measure that combination in TR-02/TR-40 before freezing the gates.

Why the split instead of one engine:
- Apple is 10× faster on English and costs nothing, and the Trelis model is no better there (0.007 vs 0.013, both at the
  floor). Under OWN-TR-8 (a) this only matters without the pack, or when Language = English.
- No Apple module writes Devanagari with English kept in Roman. DictationTranscriber hi-IN writes all-Devanagari and
  drops English words; its loose WER is 0.29–0.71 (16a §3.1). Apple's Hindi in `SpeechTranscriber` is also likely
  macOS 27+ only (its asset metadata says `_minOs 27.0`, MEASURED). The product minimum is macOS 26.
- Trelis is the only engine measured that produces the owner's Devanagari form natively and is best on real Hindi and
  real Hinglish.

### 2.2 Default engine and optional downloads

| Item | What | Size | Licence | Hosted / managed by | Default |
|---|---|---|---|---|---|
| Apple English speech model | `SpeechTranscriber` en asset via `AssetInventory` | ≈ 138 MB download | system | macOS (shared across apps) | Used on the first English drop without the pack; our card if not installed |
| **Hindi & Hinglish pack** | Trelis ggml q5_0 + Silero VAD v6.2.0 + Metal shader library (§9) + NOTICE | 1,081,141,083 + 885,098 B + shaders | Apache-2.0 (model), MIT (VAD, whisper.cpp) | Our GitHub release assets, pinned in `engines.lock` (P3-109) | Offered on first Hindi/Hinglish drop and in Settings |
| Apple Indic speech model | `com.apple.speech.asr.transcription.mul-IN` | 247,463,936 B download, 624 MB on disk | system | macOS | Only for the Roman-only fallback, only on macOS 27+, only on click |

Not offered in 1.0 (OWN-TR-6): a "Fast, Roman only" pack with Oriserve **Apex** (Apache-2.0, 574 MB, 12.8× realtime,
real Hinglish loose 0.083, real Hindi 0.210). It can't write the Devanagari file, which the owner asked for by default.
Revisit if the owner finds Trelis too slow.

### 2.3 `task=translate`
Not offered. Translation is P3-112 (Apple Translation framework, Devanagari form as source, per FR-139). Trelis's
translate behaviour is untested and turbo models can't translate (17d §6).

---

## 4. UX

### 4.1 Wheel slice
- `TRANSCRIBE` (SF Symbol `captions.bubble`) in the Tools lists already reserved by 17 §8.1: audio single and multi,
  video single (at the 12-cap, reserved) and multi.
- Probe gating (11 §8.2): hidden for video with no audio stream.
- Never dimmed for a missing model. The first drop that needs one shows the download card (§4.4), so the first frame's
  slice set stays stable (FR-18).
- One drop, no dialog. Multi-file drops run one job per file. A batch asks for any download once.

> [challenge] Slice and cap notes:
> - **Caps are fine.** TRANSCRIBE is already counted in 17 §8.1: audio single 10, audio multi 7, video single **12 (at
>   cap)**, video multi 8. Adding it costs no slot. Any later video-single tool must displace something (P2-100 lint).
>   Keep NOTES (P4) in extras.
> - **The format list is too narrow.** 17 §8.1's row says "mp3 m4a wav flac", but the audio family (11 §1) also has
>   **ogg, opus, aiff and wma**. WhatsApp voice notes (`.opus`/`.ogg`) are probably the owner's most common Hinglish
>   source. State that TRANSCRIBE appears for the **whole audio family**, and for every video container ffprobe reads
>   with an audio stream (webm and avi included). Add those to the P2-100 lint fixtures.
> - **Contradiction to fix:** 17 §8.1 said "Meeting notes is also an option in the TRANSCRIBE sheet", but this doc
>   says "one drop, no dialog". Fix 17: notes is a setting or a Change… item, not a sheet. (17 §8.1 was corrected
>   on 2026-10-22.)
> - **Multi-file drops:** TRANSCRIBE is *not* a 03a §4.4 "multi-input tool" (`<first base> <Suffix>`). Each file names
>   its own outputs.

### 4.2 Output naming (03a §4.4 tool pattern `<base> <Suffix>.<ext>`; staging and atomic publish per §4.3)

| Result | English file | Hindi/Hinglish, Roman (default on) | Hindi/Hinglish, Devanagari (default on) |
|---|---|---|---|
| Text | `<base> Transcript.txt` | `<base> Transcript.txt` | `<base> Transcript Devanagari.txt` |
| SRT | `<base>.srt` | `<base>.srt` | `<base> Devanagari.srt` |
| WebVTT | `<base>.vtt` | `<base>.vtt` | `<base> Devanagari.vtt` |

- The unmarked name is always the Roman/English file. It is the one players load automatically (same basename) and
  the one users type into search. The Devanagari file is always marked. This makes the two distinguishable and keeps
  the English case identical (owner: OWN-TR-1).
- Subtitles use the conversion pattern `<base>.<ext>` so QuickTime, IINA and VLC pick them up; `<base>.srt` existing →
  `<base> 2.srt` (collision rule). Whether players auto-load `<base> Devanagari.srt` is unverified [QA].
- Suffixes join the 03a §4.4 tool-suffix table: `Transcript`, `Transcript Devanagari`, `Devanagari`.
- All files from one drop publish as **one batch**: Undo and History treat them as one result.

> [challenge] Naming gaps against 03a §4.3–4.4:
> 1. **Pairs can split on collision.** 03a reserves and publishes **one name at a time** (`NameReserver`, then
>    `renamex_np(RENAME_EXCL)`, `EEXIST` → next candidate). If `x Transcript.txt` exists but
>    `x Transcript Devanagari.txt` doesn't, the result is `x Transcript 2.txt` beside an unnumbered
>    `x Transcript Devanagari.txt`. That pair no longer reads as a pair, and the P3-112 sibling lookup breaks. Add a
>    rule: **a result set uses one counter n**, the smallest n for which *every* name in the set is free (case-folded).
>    Publish each file with `RENAME_EXCL`. On `EEXIST` for any file, move the files already published in this set back
>    to staging (they are ours and seconds old) and retry with n + 1, within the 9,999 cap. The counter goes before
>    the extension and after the full suffix: `x Transcript Devanagari 2.txt`, `x Devanagari 2.srt`. Add this to 03a
>    §4.3 and test it in TR-16.
> 2. **`<base>.srt` from a tool is a deviation.** 03a says tools use `<base> <Suffix>.<ext>`, and "any deviation is an
>    explicit O-16 row". Add the O-16 row. `<base>.srt` usually exists already (downloaded subtitles), so the output
>    becomes `<base> 2.srt` and no player picks it up. The card should say so.
> 3. **"QuickTime, IINA and VLC pick them up" is unverified and likely wrong for QuickTime.** QuickTime Player
>    doesn't auto-load sidecar `.srt` files (INFERRED; TR-42 must check). VLC and IINA match on the base-name
>    prefix, so they may load **both** `<base>.srt` and `<base> Devanagari.srt`. Record what actually happens.
> 4. **Undefined cases:**
>    - "Devanagari only" setting: keep the marked name (`<base> Transcript Devanagari.txt`), so a name never changes
>      meaning.
>    - Hindi route on audio that turned out to be English (the Devanagari text has no Devanagari characters): write
>      **one** file, not two identical ones.
>    - Apple Roman-only fallback: unmarked name, and the card says "Roman only".
> 5. **Name the route in the file?** English and Hinglish-Roman results share `<base> Transcript.txt`. That is fine
>    for the owner, but History must record which engine and route produced it (it already does: engine/model id).

### 4.3 Settings › Transcription (defaults in bold)

| Setting | Values | Notes |
|---|---|---|
| Language | **Auto** · English · Hindi · Hinglish | Auto = §5.3 router; with the pack installed every file takes the Hinglish route (OWN-TR-8 (a)), so Hinglish mode is on in Auto (OWN-TR-10). Hindi is the option for formal Hindi: it forces `hi` without mixedcode (spike C FLEURS 0.097 vs 0.150) but writes English words in Devanagari. Hinglish skips the probe. Both decisions adopted 2026-10-22 |
| Hindi and Hinglish files | **Both scripts** · Roman only · Devanagari only | Owner answer: both by default |
| Save as | **Text** · Subtitles (SRT) · Text + SRT · WebVTT | Text is what "transcript" means. SRT/VTT for players and editors (OWN-TR-4) |
| Timestamps in text | **Off** · On | On adds `[00:12:30]` (or `[12:30]` under 1 h) at each paragraph |
| Speech models | List with size, source and Delete (shared Settings › Engines, P3-109) | "Hindi & Hinglish pack · 1.08 GB · Installed · Delete"; "English speech · managed by macOS" |

The progress card shows the route ("Hinglish · 2 files") with a **Change…** menu (Language, with "Hindi (formal)"
named there per OWN-TR-10; Scripts; Save as). Choosing
an item cancels and resubmits the job. History's Re-run (FR-135) does the same afterwards. No modifier-at-drop
variant: FR-28 accepts drops with modifiers still held from Finder, so a modifier can't mean "options".

### 4.4 First use: model download card
Shown in the HUD card when a job needs a missing model. The job waits in `planned`. Cancelling the card cancels the
job.

| State | Copy (draft) | Controls |
|---|---|---|
| Offer (pack) | "Hindi and Hinglish need the Hindi & Hinglish speech pack. One-time download, 1.08 GB. It runs on this Mac; your audio never leaves it." | **Download (1.08 GB)** · Roman only, no download (macOS 27+ only) · Cancel |
| Offer (Apple) | "macOS needs its English speech model (about 138 MB). macOS downloads and manages it." | **Download** · Cancel |
| Disk check | "Needs 1.6 GB free on Macintosh HD (1.08 GB pack + room to unpack)." | Shown instead of Download when short |
| Downloading | "Downloading Hindi & Hinglish pack · 412 MB of 1.08 GB · about 3 min left" | Cancel (keeps resume data 24 h) |
| Verifying | "Checking the download…" (SHA-256, ≈ 3 s for 1 GB) | — |
| Failed | "The download was damaged or interrupted. Nothing was installed." | Try Again · Cancel |
| Done | Card turns into normal transcription progress. The waiting job starts automatically | — |

- Pack downloads follow P3-109: HTTPS from our release assets, URL + size + SHA-256 pinned in `engines.lock` inside
  the signed app, download to Caches, verify, atomic rename into
  `~/Library/Application Support/Zivlet/Packs/hindi-hinglish/<version>/`.
- The pack is re-hashed (size + SHA-256) on first load after each app update, and on any helper model-load failure.
- Apple assets: `AssetInventory.status(forModules:)` → `assetInstallationRequest(supporting:)` → `downloadAndInstall()`.
  Progress is `progress.fractionCompleted` (`totalUnitCount` is 1, MEASURED). Zivlet reserves at most 2 of the 5 locale
  slots (en, hi-IN) and releases hi-IN when the pack is installed. Cancelling the Apple download is SPIKE (TR-03).
- The CLI never downloads. It exits 8 ("model not installed; open Zivlet › Settings › Transcription").

> [challenge] Download UX and integrity:
> - **The card contradicts §2.1.** The pack card offers "Roman only, **no download**", but §2.1/§2.2 say this path
>   needs Apple's Indic model: **247 MB** download, 624 MB on disk. Fix the copy: "Roman only, lower accuracy
>   (macOS downloads about 250 MB)". Show it only when `supportedLocales` lists hi-IN.
> - **Hashes and size confirmed** (re-run in the review): model 1,081,141,083 B, SHA-256 `f786c9a6…37bd2`; Silero
>   885,098 B, `2aa269b7…6987`. SHA-256 of the 1.08 GB file takes **3.15 s** on M2 Pro, so "≈ 3 s" holds.
> - **"Room to unpack" is undefined.** Ship the pack as separate files: model, VAD, manifest, NOTICE and optional
>   metallib, each hash-pinned. Nothing then gets unpacked, and the disk check is 1.08 GB + 10 %. A tar/zip pack
>   would need ≈ 2.2 GB free.
> - **Resume against GitHub release assets is a SPIKE.** Asset URLs redirect to short-lived signed URLs on
>   `release-assets.githubusercontent.com` / `objects.githubusercontent.com`. `URLSession` resume data can point at
>   an expired URL. Plan: on resume failure, fetch a fresh redirect and continue with `Range:` + `If-Range` (ETag).
>   If the ETag changed, restart. Verify size + SHA-256 before the atomic move. Add this to TR-25 acceptance.
> - **Integrity between updates.** The pack lives in user-writable Application Support, and the helper's ggml loader
>   parses it. A swapped file is untrusted input to a parser, even though the helper has no network access and
>   hardened runtime. Record (inode, size, mtime) after verification and re-hash whenever they change before load,
>   as well as after app updates. It costs about 3 s, and only after a change.
> - **Privacy copy** must name **GitHub** (it sees the user's IP when the pack downloads) and Apple, not just "our
>   release assets".
> - Mirror: there is a single host. If GitHub is unreachable the card should say "Try again later". There is no
>   silent fallback to Hugging Face, which matches §9.

### 4.5 Progress and cancel
- Stages and weights: Decode 0.05 · Detect 0.03 · Transcribe 0.87 · Write 0.05 (03a §4.5 plan-supplied weights).
- Transcribe fraction = end time of the last finished chunk (whisper) or final result (Apple) ÷ file duration. It is
  monotonic. ETA comes from a rolling speed over the last 60 s of audio.
- Card text: "Transcribing · Hinglish · 12:30 of 58:00 · about 9 min left".
- While a job runs: `ProcessInfo.beginActivity(.userInitiated + .idleSystemSleepDisabled)`, so a 1-hour file isn't cut
  by idle sleep.
- Cancel (03a §4.6): Apple `analyzer.cancelAndFinishNow()` (throws within ≈ 1 s, MEASURED); helper SIGINT → SIGKILL at
  +1 s to its process group. State turns `.cancelled` at once, staging is deleted, nothing is published. Partial
  transcripts are not kept in 1.0.
- Close ≠ cancel. Quit follows 03a (cancel all, wait ≤ 2 s).
- "No speech found" (VAD finds < 1 s of speech, or the engine returns no words): the card says so and nothing is
  written.

---

## 5. Pipeline

```
input (any ffmpeg-readable audio/video with an audio stream)
  │ 1 Probe (ffprobe, cached): duration, audio streams           → hide slice / plan weights
  │ 2 Decode: ffmpeg -vn -map 0:a:0 -ac 1 -ar 16000 -c:a pcm_s16le → Jobs/<uuid>/audio.wav (115 MB per hour)
  │ 3 Route (Language = Auto): pack installed → Hindi route (OWN-TR-8 (a)); no pack → energy frames → 3 speech
  │   windows → Apple en-US probe → English | Hindi route
  ├─ English: Apple SpeechTranscriber(locale, [.audioTimeRange, .transcriptionConfidence]) on audio.wav
  │           → words with time ranges and confidence
  └─ Hindi/Hinglish: zivlet-whisper vad → speech segments → ChunkPlanner (Swift, pure) → zivlet-whisper transcribe
              → per chunk: language (en | hi), words with DTW times
  │ 4 Clean-up (pure): drop zero-length segments, loop detector, NFC, UTF-8 check, Apple casing fix
  │ 5 Script forms (pure): Devanagari = model text; Roman = HinglishRomanizer(Devanagari); Latin words unchanged
  │ 6 Cue segmenter (pure): one timing plan, applied to both scripts
  │ 7 Writers: TXT (ZivletTranscript), SRT/VTT (EngineSubtitles)
  │ 8 Verify → stage → publish all files as one batch (03a §4.3)
```

### 5.1 Decode
- Bundled GPL ffmpeg, no new flags. The first audio stream is used. Multiple audio streams: first stream in 1.0; a
  stream picker comes later only if asked for.
- Disk preflight per 03a §4.2 with the WAV counted as scratch (≈ 1.9 MB per minute).
- `AVAudioFile` could read WAV/AIFF/MP4 directly (MEASURED), but one path for all containers is simpler. Apple then
  reads only our own 16 kHz WAV.

### 5.2 Chunking and decoding (whisper route)
- **VAD:** Silero v6.2.0 through whisper.cpp's VAD API, inside the helper. It returns speech segments. Defaults:
  threshold 0.5, min speech 250 ms, min silence 300 ms, pad 200 ms.
- **ChunkPlanner** (pure Swift): merges speech segments separated by < 0.3 s. It cuts any run longer than 20 s at the
  quietest 20 ms frame (RMS from the WAV) between 10 s and 20 s. Every speech sample lands in exactly one chunk.
  Overlap from padding is clamped at stitch time.
- **Per chunk:**
  1. Language detection restricted to English vs Hindi: `en` only if p(en) > p(hi) + p(ur), else `hi`. Spike B; this
     stops the Urdu-script outputs. "Hindi" and "Hinglish" settings skip detection.
  2. `hi` chunks get `<|mixedcode|>` (token 51866) after the language token, unless the setting is Hindi. `en` chunks
     decode as `en`.
  3. Greedy (`best_of 1`), `no_context = true`, `suppress_nst = true`, temperature fallback capped at 2 steps.
     `dtw_token_timestamps` uses the large-v3 alignment heads.
     > [challenge] Three corrections (MEASURED in the review):
     > - **(a)** DTW needs `flash_attn = false`. v1.9.5 defaults to `true` and then turns DTW off with only a log
     >   warning. The helper must set the flag explicitly, and the helper smoke test must fail if any `t_dtw` is
     >   −1.
     > - **(b)** Measured with the mixedcode token, `t_dtw` is close: six phrase onsets inside one 13.7 s chunk land
     >   at −0.38 … +0.07 s (Hindi phrases about 0.35 s early). Without DTW, whisper's fallback token offsets are
     >   right for the first ≈ 9 s and then **all collapse onto the chunk end**: the last 18 tokens (≈ 3 s of speech)
     >   sit at 13.72 s, up to +3.8 s late. The "spread words by length" fallback in §5.6 is better than those
     >   offsets.
     > - **(c)** Trelis reports every segment as ending at **30.0 s** whatever the chunk length (no timestamp
     >   tokens). The helper must clamp to the chunk end. Otherwise the §5.7 check "last cue ≤ duration + 0.5 s"
     >   fails, or a cue hangs on screen.
     >
     > Item 2 (mixedcode only on `hi` chunks) doesn't match what was measured: see the challenge under §2.1.
- **Repetition guard:** if a chunk's text repeats the same 1–4-word n-gram ≥ 4 times, or ≥ 200 tokens come out of a
  ≤ 20 s chunk, the chunk is split in half at its quietest frame and decoded again once. If it still fails, its text is
  kept up to the first repeat and the segment is flagged `low_confidence`.
- **UTF-8 safety:** the helper joins token bytes into words and emits only complete UTF-8 sequences. A trailing partial
  character is dropped and counted in the diagnostics. This fixes Spike B's invalid UTF-8.

### 5.3 Language router (pure decision + Apple probe)

Adopted 2026-10-22 (OWN-TR-8 (a)): when the Hindi & Hinglish pack is installed, Auto skips steps 1–4 and every
file takes the Hindi/Hinglish route. The probe below runs only when the pack is absent, to decide between Apple
English and the pack offer.

1. Energy frames (20 ms RMS) mark speech. Take up to three 15 s windows centred at 5 %, 50 % and 85 % of the speech
   time. Files ≤ 45 s use the whole file as one window.
2. Run Apple en-US `SpeechTranscriber` on each window (≈ 1 s each) and take the mean word confidence per window.
3. **English if min(window confidence) ≥ 0.80, else Hindi/Hinglish.** The threshold is set between 0.896 (lowest
   English window measured) and 0.53 (highest Hindi/Hinglish window).
   > [challenge] 0.53 was the highest *Hindi-dominant* window. English-dominant Hinglish measured 0.878–0.910 (TTS,
   > 16a §3.3 challenge). No threshold separates it from English. Resolved by OWN-TR-8 (a): with the pack installed
   > the probe is skipped.
4. **Second chance:** after an English pass, if segments covering ≥ 10 % of speech time have mean confidence < 0.50,
   the file is re-run on the Hindi route (pack permitting) and the card says "Hindi detected; re-transcribing" (INFERRED
   rule; tested in TR-14 with spliced fixtures).
5. Apple English model missing and declined → route on the whisper side (pack) with full per-chunk detection.
   Neither available → the offer card (§4.4).

### 5.4 Script forms (`HinglishRomanizer`, pure)
- Input: Devanagari-with-Roman text. Latin-script runs pass through unchanged. Each Devanagari word goes through:
  1. a lexicon of ≈ 60 common function words in Hinglish spelling ("में" → mein, "हम" → hum, "नहीं" → nahi, "है" → hai);
  2. otherwise akshara parse → final and medial schwa deletion → Hinglish vowel spelling (final aa → a, ee → i) and
     nukta letters (क़ → q, ज़ → z, फ़ → f).
- Port of spike B's romaniser rules, which beat spike C's romaniser on every set (strict Roman WER on Trelis output:
  real Hinglish 0.172 vs 0.214, Hindi TTS 0.184 vs 0.252, MEASURED in the unified rescore).
- `।` → `.`; numerals kept as written.
- Spelling conventions vary between people; strict Roman WER measures convention as much as accuracy. A user word list
  (Settings) is a Phase 4 option, not 1.0.
- Nothing is converted the other way. The Apple Roman-only fallback gets no Devanagari file: ICU Latin→Devanagari
  gives garbage such as "मॆऎतिन्ग्" (WER 0.88, MEASURED), and Roman→Devanagari would need to know which words are English.

### 5.5 Clean-up (pure)
- Drop segments with end ≤ start (whisper-cli's truncated duplicate, Spike C).
- NFC normalisation. Collapse whitespace. Strip a leading space from whisper text.
- Apple casing fix (hi-IN fallback and English): lowercase a capitalised word when it is a known Roman-Hindi lexicon
  word and not sentence-initial ("Humne", "Tha", "Bhej Denge"). Lowercase the word after a comma unless it is "I" or
  capitalised elsewhere mid-sentence. Sentence-case the first word.
- Collapse Silero silence hallucinations: segments whose text is a single repeated syllable ("झाल झाल") over < 1 s of
  speech are removed.
- [challenge] Clean-up needs three more rules:
  - **Hybrid words** ("ग्रीनland", seen on real FLEURS): render the whole word in Devanagari in the Devanagari file.
  - **Latin casing** after mixedcode decoding: sentence-initial words, "I", weekdays and months, plus a small
    proper-noun list ("monday" → "Monday").
  - **Punctuation:** mixedcode output has almost none, and nothing above adds it. Without it the TXT reads as one long
    run. Either insert `।`/`.` at pauses ≥ 0.7 s (INFERRED, cheap) or accept unpunctuated text. This part of
    OWN-TR-9 was not settled on 2026-10-22 (only the word-timing part was): the recommendation stands, and the
    owner judges samples at TR-42.

### 5.6 Cue segmentation (pure)
- Input: words with start/end. Output: cues, computed **once** and rendered in both scripts. The Roman form maps
  word-for-word from the Devanagari form, so cue boundaries never differ.
- Rules:
  - ≤ 2 lines of ≤ 42 `Character`s (grapheme clusters, so Devanagari conjuncts count once);
  - duration 1.0–7.0 s;
  - split preference: sentence end (`।` `.` `?` `!`) > pause ≥ 0.5 s > language switch > comma > any word boundary;
  - never split inside a word;
  - cues are monotonic and never overlap;
  - a cue shorter than 1 s extends into the following gap.
- Without word times (DTW failure, rare): spread the words over the segment in proportion to their length (INFERRED
  fallback, flagged in diagnostics).

> [challenge] **SRT timing accuracy evidence.**
> - **Chunk-level timing is good.** On real Hinglish, all 9 Trelis cues fall inside their source clip. On
>   `mixed_blocks`, block onsets are off by −0.02 … +0.12 s (spike C's timestamp check). But those anchors sit at
>   VAD chunk starts, so they test chunk offsets, not word times.
> - **No spike output follows these rules.** The chosen config's SRTs have **one cue per chunk, up to 20.1 s long**,
>   with no line limit. The 1–7 s / 2 × 42 cue rules have never been run on Trelis output.
> - **Mid-chunk word timing was measured only in the review**, on 6 TTS phrases: DTW error ≤ 0.38 s with flash
>   attention off; the fallback offsets were up to 3.8 s late (§5.2 challenge).
>
> Add gates to 16a §11.3:
> - a **timing fixture** with known phrase onsets inside chunks (TTS + the 8 real clips): median |onset error| ≤ 0.25 s
>   and p95 ≤ 0.6 s;
> - **no cue longer than 7 s** in any SRT.

- TXT paragraphs: a new paragraph at a pause ≥ 1.5 s, at a language switch between whole sentences, or after 80 words.

### 5.7 Writers and verification
- TXT: UTF-8 without BOM, LF line endings, final newline. SRT: `HH:MM:SS,mmm`, UTF-8, line endings as EngineSubtitles
  already writes them (P2-18 goldens). VTT: `WEBVTT` header, `HH:MM:SS.mmm`.
- Verify before publish:
  - valid UTF-8 and NFC;
  - at least one cue;
  - cue times monotonic and the last cue ends ≤ duration + 0.5 s;
  - the Roman file contains zero Devanagari characters;
  - both script files have the same number of cues;
  - [challenge] no word mixes Devanagari and Latin, and no cue lasts longer than 7 s (helper clamp, §5.2 challenge).
  Failure → `verificationFailed` (02 §9), nothing published.

### 5.8 Internal model (for P3-112, P4-100/101, P2-135)
```swift
public struct Transcript: Sendable, Codable, Equatable {
    public let duration: Double
    public let engine: String          // "apple.speechtranscriber/en-US", "whisper/trelis-hinglish-q5_0@eab1188"
    public let languageSetting: LanguageSetting   // .auto, .english, .hindi, .hinglish
    public let segments: [Segment]
}
public struct Segment: Sendable, Codable, Equatable {
    public let start: Double, end: Double
    public let language: SegmentLanguage          // .en, .hi (Hindi or Hinglish chunk)
    public let devanagari: String?                // nil for English and for the Apple Roman-only fallback
    public let roman: String
    public let words: [Word]                      // Word { text, start, end, confidence? }; text in model script
    public let lowConfidence: Bool
}
```
- The model stays inside the job. Files are the only output; there is no hidden sidecar.
- P3-112 Translate, given a Roman transcript, uses its `Transcript Devanagari` sibling as the source when it exists
  (FR-139).
- P2-135's keep-list remap works on `Segment` or on any parsed SRT.

---

## 6. Module placement

| Module | Layer | Depends on | Contents | Pure / `swift test` | Phase |
|---|---|---|---|---|---|
| `ZivletTranscript` (new) | domain | Foundation only (added to R1) | `Transcript` model, `LanguageRouter` decision, `EnergyFrames`, `ChunkPlanner`, `CueSegmenter`, `HinglishRomanizer`, `TranscriptCleanup`, `TranscriptTextWriter`, `HelperProtocol` (JSON lines Codable) | **Pure.** Golden + property tests | 3 |
| `EngineSubtitles` (existing, P2-18) | engine | Core | SRT/VTT writers, reused; one new entry point that takes `[Cue]` | Pure | 2 |
| `EngineSpeech` (new) | engine | EngineKit, ZivletTranscript, EngineSubtitles, Speech, AVFoundation | `TranscribePlan` (Codable stages), `AppleSpeechRunner` (`SpeechAnalyzer`, `AssetInventory` status), `WhisperHelperClient` (SubprocessRunner, JSON lines, cancel), `TranscriptVerifier` | Plans pure; runners `.integration` | 3 |
| `zivlet-whisper` (new helper) | Helpers | libwhisper + ggml (vendored v1.9.5 + patch), Metal, Accelerate | C++17 `main` (≈ 400 lines): `vad`, `transcribe` subcommands; reads WAV path + JSON request on stdin, writes JSON lines on stdout; no network code | Helper smoke test with a tiny model | 3 |
| `ZivletRuntime` | application | — | New lane `speech`, width 1 (GPU-bound; memory pressure `.warning` defers admission); pack lookup via the P3-109 `PackStore` | Logic tests | 3 |
| `ZivletUI` | shell | — | Settings › Transcription, download cards (P3-109 card reused), route label + Change… | View models | 3 |
| `zivlet-cli` | front end | — | `zivlet transcribe <files…> [--language auto\|en\|hi\|hinglish] [--scripts both\|roman\|devanagari] [--format txt\|srt\|txt+srt\|vtt] [--json]` | Parsing tests | 3 |

- Module name: **`EngineSpeech`**, not `EngineAI` (17 §7 left this to 16). It keeps Speech/AVFoundation out of
  EngineAI (Foundation Models, Translation), and EngineAI depends on `ZivletTranscript` only for the model.
- Process placement: `EngineSpeech` runs in `ZivletWorker.xpc` like other engines. It spawns `zivlet-whisper` through
  `SubprocessRunner` (own process group, PID file, orphan reaper).
- Whether `SpeechAnalyzer` works inside the XPC worker, and which identity holds the `AssetInventory` reservation, is
  SPIKE TR-03. If it fails, `AppleSpeechRunner` runs in the app. That is allowed by principle P3: Apple framework, and
  it reads only our own WAV.
- `AssetInventory` install requests always start in the app (UI) process. The worker never touches the network (02
  §2.1).

Helper protocol (JSON lines; `HelperProtocol` decodes and fuzzes it):
```
→ stdin  {"cmd":"transcribe","model":"…/ggml-trelis-hinglish-q5_0.bin","wav":"…/audio.wav",
          "chunks":[{"id":0,"start":0.84,"end":17.2},…],"lang":"auto-enhi","mixedcode":true,"threads":4}
← stdout {"ev":"loaded","ms":2140,"metal":true}
← stdout {"ev":"chunk","id":0,"lang":"hi","p_en":0.02,"words":[["कल",0.92,1.18,0.91],["meeting",1.18,1.60,0.88],…]}
← stdout {"ev":"done","chunks":44}      or {"ev":"error","code":"model_load|bad_wav|oom","detail":"…"}
```

---

## 7. Permissions and privacy

| Item | Behaviour |
|---|---|
| TCC | None. No Speech Recognition prompt (MEASURED, 16a §3.4), no microphone (files only), no `NSSpeechRecognitionUsageDescription`. CI's TCC-diff check (NFR-23 suite) covers a transcription run |
| Network | Only (a) the pack download from our release assets and (b) macOS asset downloads, each started by a click on a card (FR-137). Transcription itself is offline: `lsof` zero sockets (MEASURED); the helper has no network code |
| Data | Audio and text stay on the Mac. Scratch WAV lives in `Caches/<bundle>/Jobs/<uuid>/` and is deleted at job end; the orphan reaper deletes leftovers |
| Logs | Never contain transcript text. Diagnostics hold counts, timings, route, confidences and chunk languages only |
| History | Kind `transcribe`: language setting, detected route, engine/model id, duration, output paths. **No text** (FR-135) |
| Banned | Legacy `SFSpeechRecognizer` (server path for hi-IN), any cloud ASR, `PrivateCloudComputeLanguageModel` (P3-110 lint) |
| Privacy copy | Settings and the card name the two download sources and say audio never leaves the Mac |

---

## 8. Size impact

| Item | Installed | Compressed (DMG) | Status |
|---|---|---|---|
| `zivlet-whisper` code (libwhisper + ggml CPU/Metal/BLAS + main, `-Os`, dead-strip, stripped) | ≈ 1.5 MB | ≈ 0.5 MB | MEASURED minimal link: `__TEXT` 1.33 MB |
| Metal shader library | 5.2 MB embedded source (MEASURED `__ggml_metallib` section); precompiled `default.metallib` size SPIKE | ≈ 1.1 MB (MEASURED total helper gzip -9: 1.56 MB) | TR-01 |
| `ZivletTranscript` + `EngineSpeech` Swift code | +0.3–0.6 MB | +0.15 MB | EST |
| Silero VAD (0.9 MB), Trelis model (1.08 GB) | 0 (in the pack) | 0 | download |
| Apple speech models | 0 | 0 | macOS-managed |
| **Total** | **+7–7.5 MB** (≈ +2 MB if the shaders move to the pack) | **+1.7–2 MB** | OWN-TR-3 |

Against 17 §9 (ungated ≈ 70.2–71.6 MB): ≈ **77–79 MB** installed, below the 85 MB hard gate, above the 70 MB target.

Options for OWN-TR-3:
- (a) **Accept** the overage, measured at the P1-52 gate (default).
- (b) **Shaders in the pack.** Build the helper with `GGML_METAL_EMBED_LIBRARY=OFF` and ship the precompiled
  `default.metallib` (or kernel sources via `GGML_METAL_PATH_RESOURCES`, VERIFIED-UPSTREAM in `ggml-metal-device.m`
  v1.9.5) inside the pack, hash-pinned like the model. Bundle cost drops to ≈ 2 MB.
  - It needs an explicit FR-137/NFR-23 reading: GPU shader code isn't Mach-O and can't bypass library validation, and
    its hash is pinned in the signed app.
  - The whisper route is useless without the pack anyway.

Either way, precompile the metallib in CI. The Metal Toolchain must be on the build machine:
`xcodebuild -downloadComponent MetalToolchain`. Precompiling removes the 7–30 s first-launch shader compile (MEASURED
with embedded source).

---

## 9. Packaging, licences, provenance

| Component | Version / pin | Licence | How shipped | Notice |
|---|---|---|---|---|
| whisper.cpp + ggml | v1.9.5, commit d1be6fd | MIT | static in `Contents/Helpers/zivlet-whisper` | MIT text in About › Licences |
| mixedcode patch | ≈ 40 lines (spike C's patch); rewrite the env-var hook as a `whisper_full_params.extra_prompt_tokens` field and clamp the language count to 100 for 51,867-token vocabularies | ours, GPL-3.0-or-later (MIT-compatible) | `Vendor/whisper/patches/` | patch listed in SPDX |
| Trelis/whisper-hinglish-preview | HF revision `eab1188fd2d0e91f2584229b32b3bfe1901c896c`; full 51,867-token vocabulary; ggml q5_0 | Apache-2.0 (base: Vaani Apache-2.0, OpenAI Whisper MIT) | pack file `ggml-trelis-hinglish-q5_0.bin`; spike artefact 1,081,141,083 B, SHA-256 `f786c9a64b4c57b4812b5ef32a0788827bfbb359dd854abc88e58c8072037bd2` (MEASURED; production conversion must reproduce or re-pin, TR-05) | NOTICE + LICENSE in the pack and About |
| Silero VAD | ggml-silero-v6.2.0, 885,098 B, SHA-256 `2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987` | MIT | in the pack | About |
| Apple Speech | system | — | system | — |

- Trelis is marked "research preview; weights may change". We pin the revision, self-host our own conversion on our
  release assets, and never fetch from Hugging Face at runtime.
- Its training data is not fully disclosed. The CC-BY-NC CoSHE set was used only for its evaluation.
- Third-party ggml conversions on Hugging Face are never used.
- Apache-2.0 weights downloaded by the user beside a GPL-3.0-or-later app: compatible (Spike C licence review).
- Signing: the helper is signed inside-out with the app, with hardened runtime and no entitlements (11 §7.2).

> [challenge] **Licence check, re-verified 2026-10-21** (Hugging Face API and the raw model cards; whisper.cpp
> checkout):
>
> | Item | Verified | Note |
> |---|---|---|
> | Trelis/whisper-hinglish-preview @ `eab1188…` | `license: apache-2.0` in card metadata; HEAD sha = pinned revision; not gated | Card: "Research preview. Numbers and weights may change." No NOTICE file upstream, so our NOTICE must carry attribution to Trelis, ARTPARK-IISc Whisper-Vaani and OpenAI Whisper |
> | Base: ARTPARK-IISc/whisper-large-v3-vaani-hindi | apache-2.0; trained on ARTPARK-IISc/Vaani (dataset **CC-BY-4.0**, gated "auto") | §9 says "Vaani Apache-2.0": the *checkpoint* is Apache-2.0, the *dataset* is CC-BY-4.0. Dataset licences don't bind the weights we ship, but list both in NOTICE |
> | CoSHE (CC-BY-NC-4.0) | The card names it only as the **evaluation** benchmark (CoSHE-500 from soketlabs/CoSHE-Eval) | Supports §9's claim. Trelis's *training* data is still undisclosed beyond the Vaani start: residual risk, accepted |
> | Oriserve Apex @ `f3214ee…` | apache-2.0 (base whisper-large-v3-turbo, MIT) | Only relevant if OWN-TR-6 is adopted |
> | whisper.cpp v1.9.5 `d1be6fd` | MIT (LICENSE in checkout) | — |
> | Silero VAD ggml v6.2.0 | MIT upstream; hash re-verified | Fetch from the ggml-org conversion; pin it like the model |
> | mixedcode patch | §9 says "ours, GPL-3.0-or-later" | Licensing it **MIT** keeps vendored whisper.cpp single-licence and lets us upstream the `extra_prompt_tokens` field. Recommend MIT |
> | Test corpora | FLEURS CC-BY-4.0; HumynLabs CC-BY-4.0 (card verified); TTS from `say` for internal testing only | Never shipped or committed. Common Voice (TR-04) is CC0, but downloads now go through Mozilla's portal with terms of use (no re-identification): record acceptance. IndicVoices/Svarah are CC-BY-4.0 per their cards (re-check at TR-04). MUCS-2021: licence unclear, so excluded until verified |

---

## 10. Risks

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| 1 | **Real-speech evidence is thin** (12 read-Hindi clips, 8 readings of one Hinglish sentence) | High / High | TR-04 adds licensed real sets (Common Voice hi CC0, IndicVoices and Svarah after licence check) before gates freeze; owner may add a consented test clip (OWN-TR-7) |
| 2 | **Speed:** 2.1× realtime (1 h ≈ 28 min on M2 Pro; M1 Air INFERRED ≈ 1.2–1.5×) | High / Medium | TR-02: merge same-language chunks up to 28 s, flash attention, threads; ETA and keep-awake; Fast pack (Apex) as OWN-TR-6 |
| 3 | Trelis weights withdrawn or changed upstream | Medium / Medium | Pinned revision, own hosted conversion, Apache-2.0 allows redistribution. Fallbacks measured: stock turbo + Devanagari prompt (real Hinglish 0.161) or Apex (Roman only) |
| 4 | Patch drift on whisper.cpp updates | Medium / Low | Patch is small and covered by a helper test (token 51866 accepted, 100 languages); bump only with the full eval |
| 5 | macOS 26 behaviour of the Apple path unverified (only a macOS 27 machine was available) | Medium / Medium | TR-03 on 26.x [HW]. English `SpeechTranscriber` is a launch language (VERIFIED-WEB). hi-IN fallback hidden unless `supportedLocales` lists it at runtime |
| 6 | Router mis-routes Indian-accented English | Medium / Low | Only without the pack (OWN-TR-8 (a) skips the probe when it is installed). Fails safe (Trelis transcribes English well); TR-04 measures real Indian English; threshold is a constant tuned by the eval |
| 7 | Hallucinations on music/silence, repetition loops | Medium / Medium | VAD-only chunks, `suppress_nst`, no context, repetition guard (§5.2), clean-up (§5.5) |
| 8 | Bundle above the 70 MB target | Certain / Low | OWN-TR-3 options (§8) |
| 9 | `AssetInventory` reservation identity in the XPC worker; 5-locale cap shared with nothing else today | Medium / Low | TR-03; run Apple in the app if needed |
| 10 | Memory: helper 1.56 GB + Apple service ≈ 0.3 GB on 8 GB Macs | Medium / Medium | `speech` lane width 1; defer under `.warning`; TR-02 measures an 8 GB M1 |
| 11 | Roman spelling differs from the owner's habits | Medium / Low | Lexicon is data; Phase 4 user word list; owner reviews sample output (TR-42) |
| 12 | Long files: 1 h WAV scratch 115 MB; GPU contention with video encodes | Low / Low | Disk preflight; `speech` lane separate from `hwVideo` |
| 13 | [challenge] **English-dominant Hinglish routed to Apple English** (TTS: 3/3 clips, conf 0.88–0.91); Hindi words rewritten as English | **High / High** | OWN-TR-8 (a), adopted 2026-10-22: Trelis for everything when the pack is installed |
| 14 | [challenge] **DTW off under flash attention** (the v1.9.5 default): SRT cues land seconds off, or every word gets time −1 | Certain if unhandled / High | `flash_attn = false` whenever word times are needed; helper test asserts `t_dtw ≥ 0`; DTW only for SRT/VTT/timestamps (OWN-TR-9, adopted 2026-10-22) |
| 15 | [challenge] **Measured config ≠ specified config** (free 99-language detection + mixedcode on all chunks vs restricted detection + mixedcode on `hi` only) | High / Medium | Specify what was measured, or re-measure before the gates freeze (§2.1 challenge) |
| 16 | [challenge] Unpunctuated, lowercase Hindi/Hinglish output | Certain / Medium | §5.5 challenge rules; owner sees samples at TR-42 |
| 17 | [challenge] Pair names split on collision; P3-112 can't find the Devanagari sibling | Medium / Medium | One counter per result set (§4.2 challenge) |

---

## 12. Phase placement

- **Before Phase 3 (prototypes only, no app code): TR-01…TR-07.** They settle size, speed, the XPC question, the real
  corpus, conversion reproducibility, routing of code-mixed speech and subtitle timing before Phase 3 planning. They
  do not compete with the first beta: the owner moved the notch Drop Box and the Notch HUD to the front of Phase 2 on
  2026-10-22 (17 §4.2).
- **Phase 3 wave 3B (1.0): TR-10…TR-43**, replacing slot P3-111.
  - Hard dependencies: P2-01 (worker), P2-18 (EngineSubtitles), P3-109 (packs), P2-145 (History), P2-146/P3-31 (CLI).
  - The pure rows (TR-10…16) can start any time; they need nothing but Foundation.
- **Ships with P3-112 Translate**, as 17 §7 requires. P4-100/101 (speakers, notes) consume `Transcript` (§5.8).
- Not pulled into Phase 2: Hindi/Hinglish quality decides this feature (R-2), so an English-only early release would
  deliver the less important half. It also isn't worth moving P3-109 forward.

---

## 13. Task list

The rows (spikes TR-01…TR-07, build rows TR-10…TR-43, the PRD rows FR-142…FR-149 and NFR-25/26) are in
[05b-task-additions-transcription.md](../plan/05b-task-additions-transcription.md), in the 05 §9.0 columns. They
replace slot P3-111 and are not yet merged into 05 or 01b.

Effort (ESTIMATE; S = 1 d, M = 3 d, L = 7.5 d as in 05 §9.10): spikes 5 S + 2 M = 11 d; build 10 S + 9 M + 1 L =
44.5 d; **≈ 55.5 engineer-days (≈ 11 weeks for one engineer, about 6 weeks with two working the pure and engine
tracks in parallel).**


---

## 14. Owner decisions

Outcomes recorded on 2026-10-22: OWN-TR-8, OWN-TR-9 (its word-timing part) and OWN-TR-10 were the assistant's
recommendations, and they were applied as defaults because the owner did not object (see
[00-decisions.md](00-decisions.md), 2026-10-22 section). The owner may still change them. OWN-TR-1 … OWN-TR-7 are
open at their recommendations.

| ID | Question | Recommendation | Outcome |
|---|---|---|---|
| OWN-TR-1 | Names: `<base> Transcript.txt` (Roman/English) + `<base> Transcript Devanagari.txt`; `<base>.srt` + `<base> Devanagari.srt` | Adopt | open |
| OWN-TR-2 | Hindi/Hinglish engine = Trelis pack, 1.08 GB one-time download, ≈ 2× realtime today | Adopt: best measured quality, and the only engine that writes the Devanagari file natively | open |
| OWN-TR-3 | Size: accept ≈ +7 MB installed, or move the Metal shader library into the pack (≈ +2 MB) | (a) accept, decide finally on the P1-52 measured DMG; (b) if the gate is tight | open |
| OWN-TR-4 | Default "Save as" | Text; SRT one setting away | open |
| OWN-TR-5 | Offer Apple's Roman-only fallback (macOS 27+) when the pack is declined | Adopt, clearly labelled "Roman only, lower accuracy" | open |
| OWN-TR-6 | "Fast, Roman only" Apex pack (574 MB, 12.8×) | Not in 1.0; revisit after the owner tries Trelis on real files | open |
| OWN-TR-7 | Optional: one consented 2–5 min real recording of the owner's typical speech for the private eval set (never committed) | Ask; the plan works without it | open |
| OWN-TR-8 [challenge] | **Auto routing when the pack is installed.** (a) Everything goes through Trelis: correct on English, Hindi and every Hinglish mix, but English runs ≈ 2× realtime instead of ≈ 30×. (b) Keep the Apple English probe with a stricter rule (≥ 0.95 plus a Trelis language-ID check). That needs a spike, and English-dominant Hinglish may still slip through | **(a)**. English-dominant Hinglish scored 0.88–0.91 and was mangled by Apple English (TTS). The owner's content mixes English, Hindi and Hinglish, and Hinglish quality decides (R-2). Apple English stays the engine when no pack is installed, or when Language = English | **(a) adopted as default, 2026-10-22** |
| OWN-TR-9 [challenge] | **Subtitle timing vs speed, and punctuation.** Accurate SRT cues need DTW with flash attention off: ≈ 25–40 % slower (≈ 1.5–1.7× realtime). Mixedcode output is unpunctuated | DTW only when SRT/VTT/timestamps are requested; Text keeps the fast path. Add pause-based `।`/`.` insertion; the owner judges samples at TR-42 | **Word timing only when subtitles or timestamps are requested: adopted as default, 2026-10-22.** Punctuation: open (TR-42) |
| OWN-TR-10 [challenge] | Formal Hindi in Auto: mixedcode costs ≈ ⅓ more errors on pure Hindi (FLEURS 0.150 vs 0.097) and writes some Hindi words in Latin | Keep mixedcode in Auto (Hinglish is the mix that decides, R-2). Mention the "Hindi" setting in the Change… menu. Spike a per-chunk Latin-share re-decode in TR-02 | **Adopted as default, 2026-10-22:** Hinglish mode on in Auto; "Hindi" is the option for formal Hindi |

---

## Sources

- Our own measurements (2026-10-21, development Mac, see the evidence labels above): spikes A (Apple Speech), B
  (whisper.cpp) and C (Hindi and Hinglish fine-tunes), the unified rescore, the router probe, the minimal helper link,
  and the adversarial review's TTS timing fixture, English-dominant Hinglish router clips and licence re-check. The
  scripts, corpora and raw outputs are local prototypes and are not published. Results are in
  [16a-transcription-evidence.md](16a-transcription-evidence.md).
- [Apple: SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) ·
  [WWDC25 "Bring advanced speech-to-text to your app with SpeechAnalyzer"](https://developer.apple.com/videos/play/wwdc2025/277/)
- [whisper.cpp v1.9.5](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.5) (MIT) ·
  [ggerganov/whisper.cpp models on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp)
- [Trelis/whisper-hinglish-preview](https://huggingface.co/Trelis/whisper-hinglish-preview) (Apache-2.0) ·
  [Oriserve/Whisper-Hindi2Hinglish-Apex](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Apex) (Apache-2.0)
- [Silero VAD](https://github.com/snakers4/silero-vad) (MIT)
- [Google FLEURS](https://huggingface.co/datasets/google/fleurs) (CC-BY-4.0) ·
  [HumynLabs airline-customersupport-Hinglish-audio](https://huggingface.co/datasets/HumynLabs/airline-customersupport-Hinglish-audio) (CC-BY-4.0)
