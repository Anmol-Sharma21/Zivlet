# 05b — Transcription: rows to merge into 05-task-list and 01b-prd-additions

Date: 2026-10-21 (imported 2026-10-22). Source: [16-transcription.md](../design/16-transcription.md) (the design) and
[16a-transcription-evidence.md](../design/16a-transcription-evidence.md) (its evidence and test plan). Section
references below point into those two files. Product name Zivlet. **Nothing here is merged into 05 or 01b yet**; each
block names its target. OWN-TR-8, OWN-TR-9 (word timing) and OWN-TR-10 were adopted as defaults on 2026-10-22 (see
[00-decisions.md](../design/00-decisions.md)); the rows below already follow them.

Placement: Phase 3 wave 3B (1.0), replacing slot P3-111. The spikes can run before Phase 3 as prototypes (no app
code). The owner's 2026-10-22 reorder puts the notch Drop Box and the Notch HUD at the front of Phase 2
([17-feature-roadmap.md §4.2](../design/17-feature-roadmap.md)); nothing here changes that.

---

## A. `docs/plan/05-task-list.md`

### A.1 Add to §9.1 (changes to existing rows)

| ID | Change | New / extra acceptance |
|---|---|---|
| P3-111 | **Slot filled by 16-transcription.md.** P3-111 becomes the umbrella for TR-01…TR-43 (§A.3, §A.4); Area `EngineSpeech` (new), `ZivletTranscript` (new); size = sum of TR rows | Done when TR-10…TR-43 are green and the 16a §11.3 gates pass in `make asr-eval` |
| P3-112 | Translate uses the transcript's Devanagari form: when the input is `<base> Transcript.txt`/`<base>.srt` and a `… Devanagari` sibling exists, the sibling is the source (FR-139) | Roman-only input (Apple fallback) → source hi as fallback, card says "translated from Roman text" |
| P3-109 | First pack is "Hindi & Hinglish" (TR-25). Packs may carry a hash-pinned Metal shader library only if OWN-TR-3(b) is chosen | Pack resume data kept 24 h; re-hash on first load after an app update |
| P2-100 | Cap lint covers `TRANSCRIBE` in audio single/multi and video single/multi (already reserved in 17 §8.1) | Video single stays at 12 |
| P2-145 | History kind `transcribe` fields: language setting, route, engine/model id, duration, output paths; never text | Privacy test greps History for a known transcript phrase: 0 hits |

### A.2 Add to §9.2 (milestones)

No new milestone. M6 (1.0) exit adds: "16a §11.3 ASR gates green; OWN-TR-1…5 decided".

### A.3 Add to §9.8 (spikes; may run before Phase 3, prototypes only)

| ID | Question / check | Gates | Size | Pass bar |
|---|---|---|---|---|
| TR-01 | Helper build, size and Metal shaders: minimal `zivlet-whisper` (v1.9.5 + mixedcode patch, `-Os`, dead-strip); precompiled `default.metallib` vs embedded source vs pack-loaded sources | TR-20, OWN-TR-3 | S | Installed/DMG deltas recorded (minimal link measured 6.7 MB / 1.56 MB gzip with embedded shaders); first-launch compile time; runs under hardened runtime with no entitlements |
| TR-02 | Trelis speed: chunk merging ≤ 28 s per language run, flash attention, threads; M1 Air 8 GB | TR-21, NFR-25 | M | long10 loose WER within +0.005 of baseline (0.052); ≥ 3× realtime on quiet M2 Pro (baseline 2.1×); M1 Air ≥ 1×, peak RSS ≤ 2.0 GB **[HW]** |
| TR-03 | Apple `SpeechAnalyzer` inside `ZivletWorker.xpc`; `AssetInventory` reservation identity; asset-download cancel; macOS 26.x behaviour | TR-23 | S | Works in worker, or decision to run in app; en supported on 26.x; hi-IN presence on 26.x recorded; no TCC prompt **[HW]** |
| TR-04 | Real-speech corpus v2 (licence-checked: Common Voice hi CC0; IndicVoices, Svarah, MUCS only if licences permit) | TR-40, FR-148 | M | ≥ 30 min real Hindi/Hinglish + ≥ 10 min Indian English, refs in Roman and Devanagari; fetch script with pinned SHA-256, never committed; router ≥ 95 % correct on real files; gates re-baselined (measured + 25 %, never looser than 16a §11.3) |
| TR-05 | Reproducible Trelis conversion (HF revision `eab1188fd2d0e91f2584229b32b3bfe1901c896c`, full 51,867-token vocabulary, q5_0) | TR-25 | S | Two clean runs → identical SHA-256 (spike artefact `f786c9a6…37bd2`, 1,081,141,083 B); NOTICE/LICENSE assembled |
| TR-06 | Router on code-mixed speech: the review's English-dominant Hinglish TTS clips (en-US confidence 0.878–0.910, mis-routed by the probe) plus TR-04 real clips | TR-14 | S | With the pack installed (OWN-TR-8 (a)): 100 % of English-dominant Hinglish reaches the Hindi route and keeps its Hindi words. Without the pack: the probe's result on these clips is recorded, and option (b) (stricter threshold plus a Trelis language-ID pass) is measured as data for the owner |
| TR-07 | Timing fixture: known phrase onsets inside chunks (the review's six-phrase TTS fixture plus the real clips) | TR-12, TR-21 | S | DTW median onset error ≤ 0.25 s, p95 ≤ 0.6 s; no `t_dtw = −1`; segment ends clamped to the chunk end (Trelis reports 30.0 s) |

> [challenge] Spike-row changes from the adversarial review (16 §2.1, §5.2, §5.6 and 16a §3.3):
> - **TR-02:** flash attention and DTW can't both be on in whisper.cpp v1.9.5 (DTW is silently disabled). Measure
>   speed **twice**: Text (flash attention on, no DTW) and SRT (flash attention off, DTW). DTW alone cost about
>   25–40 % in the review. Also measure: mixedcode on every chunk vs only on `hi` chunks; restricted en/hi detection
>   vs free `-l auto`; a per-chunk Latin-share re-decode without mixedcode for formal Hindi.
> - **TR-04:** add ≥ 10 min of **real English-dominant Hinglish** (conversational, Latin-heavy) and **human verbatim
>   re-transcription** of the 8 HumynLabs clips in both scripts. The current reference is the script, not what was
>   said. Common Voice downloads need Mozilla's terms of use: record acceptance. MUCS stays excluded until its
>   licence is verified.

### A.4 Add a new §9.6a "Phase 3 additions: transcription (wave 3B, replaces the P3-111 slot)"

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| TR-10 | `ZivletTranscript` model + R1 lint **[TDD]** | ZivletTranscript (new) | — | S | `Transcript`/`Segment`/`Word`/`Cue` Codable + Sendable (16 §5.8); check-imports allowlist = Foundation only; round-trip tests | FR-138 |
| TR-11 | `HinglishRomanizer` **[TDD]** | ZivletTranscript | TR-10 | M | Port of spike B's rules (lexicon, akshara parse, schwa deletion, Hinglish vowels, nukta); ≥ 300-word golden table; Latin passthrough; 0 Devanagari chars out; real Hinglish derived Roman strict WER ≤ 0.20 on Trelis output | FR-144 |
| TR-12 | `CueSegmenter` + TXT writer + SRT/VTT via EngineSubtitles **[TDD]** | ZivletTranscript, EngineSubtitles | TR-10, P2-18 | M | 16 §5.6 rules as property tests (≤ 2 × 42 graphemes, 1–7 s, monotonic, no overlap, identical timings across scripts); goldens incl. Devanagari and hour rollover | FR-146 |
| TR-13 | `EnergyFrames` + `ChunkPlanner` **[TDD]** | ZivletTranscript | TR-10 | S | ≤ 20 s chunks cut at the quietest 20 ms frame between 10 and 20 s; full speech coverage; deterministic | FR-145 |
| TR-14 | `LanguageRouter` **[TDD]** | ZivletTranscript | TR-10 | S | Pack installed + Auto → Hindi route with no probe (OWN-TR-8 (a)); no pack: 3 windows at 5/50/85 % of speech, English iff min confidence ≥ 0.80, files ≤ 45 s = 1 window, second-chance rule; 16a §3.3 fixtures 10/10; spliced EN+HI fixtures → Hindi route; English-dominant Hinglish fixtures → Hindi route when the pack is installed | FR-143 |
| TR-15 | `TranscriptCleanup` **[TDD]** | ZivletTranscript | TR-10 | S | Zero-length segment drop; repetition detector (spike B loop cases); NFC; never emits invalid UTF-8; Apple casing fix | FR-145 |
| TR-16 | Transcript output names **[TDD]** | Core (`OutputNamer`) | — | S | `<base> Transcript.txt`, `<base> Transcript Devanagari.txt`, `<base>.srt`, `<base> Devanagari.srt`, `.vtt` likewise; collisions; 255-byte truncation with Devanagari bases; 03a §4.4 suffix table updated | FR-147 |
| TR-20 | Vendor whisper.cpp v1.9.5 + mixedcode patch | Vendor | TR-01 | M | Pinned tag/commit d1be6fd; patch reworked as a `whisper_full_params` field (no env var) + 100-language clamp; reproducible build script; metallib per OWN-TR-3; SPDX + MIT notice | FR-144 |
| TR-21 | `zivlet-whisper` helper | Helpers | TR-20 | L | `vad` + `transcribe`; JSON-lines protocol (16 §6); restricted en/hi detection (en iff p(en) > p(hi)+p(ur)); `<|mixedcode|>` unless setting = Hindi; greedy, `no_context`, `suppress_nst`, DTW large-v3 only when word times are requested; UTF-8-safe words; repetition guard (split + one retry); coded errors; no network symbols (`nm`) | FR-145 |
| TR-22 | `WhisperHelperClient` | EngineSpeech (new) | TR-21, P2-01 | M | SubprocessRunner, own process group, PID file, orphan reaper; progress from chunk events; cancel ≤ 1 s; crash → one serial retry; model re-hash on load failure | FR-145, FR-149 |
| TR-23 | `AppleSpeechRunner` | EngineSpeech | TR-03 | M | `SpeechTranscriber` + `.audioTimeRange`, `.transcriptionConfidence`; probe API for the router; English locale choice; hi-IN fallback only if `supportedLocales` lists it; `AssetInventory` status/reserve/release (≤ 2 locales); cancel ≤ 1 s | FR-142, FR-143 |
| TR-24 | `EngineSpeech` plan and execute | EngineSpeech, Runtime | TR-11…TR-15, TR-22, TR-23 | M | ffmpeg → 16 kHz mono WAV → route → engine → clean-up → script forms → cues → writers → verify (16 §5.7); `speech` lane width 1, deferred under memory `.warning`; keep-awake activity; "No speech found" writes nothing; all outputs publish as one batch | FR-138, FR-146, FR-149 |
| TR-25 | Hindi & Hinglish pack | Runtime, Release | P3-109, TR-05 | S | `engines.lock` entries (URL, size, SHA-256) for Trelis q5_0, Silero v6.2.0 (`2aa269b7…6987`), shaders if OWN-TR-3(b); manifest + NOTICE; uploaded to release assets; Settings › Engines shows size + Delete | FR-144, FR-137 |
| TR-30 | Slice, History, progress card | Core, UI | TR-24, P2-145, P2-100 | S | `TRANSCRIBE` (`captions.bubble`) in audio/video lists within caps; hidden without an audio stream; History kind `transcribe` without text; card shows route + Change… (cancel and resubmit) | FR-138, FR-147 |
| TR-31 | Settings › Transcription + download cards | UI | TR-25, TR-23 | M | Settings per 16 §4.3 (Auto · Both scripts · Text · timestamps off); "Hindi (formal)" named in the Change… menu (OWN-TR-10); card states per 16 §4.4 incl. disk check, resume, verify failure, Roman-only fallback (macOS 27+ only); VoiceOver labels | FR-142, FR-144, FR-147 |
| TR-32 | CLI `zivlet transcribe` | zivlet-cli | TR-24, P3-31 | S | `--language auto\|en\|hi\|hinglish`, `--scripts both\|roman\|devanagari`, `--format txt\|srt\|txt+srt\|vtt`, `--json`; exit 8 when a model is missing; never downloads | FR-136, FR-147 |
| TR-40 | ASR eval harness and gates | QA, Tools | TR-04, TR-24 | M | `make asr-eval` (local [HW] job, packs present) runs the 16a §11.3 table with the unified scorer (dev-only, `python3 -I`); report kept per release; required for any engine/model/patch change | NFR-26, FR-148 |
| TR-41 | Integration tests | Tests | TR-24 | M | Cancel ≤ 1 s (helper and Apple), staging empty; crash retry; orphan reaper; offline run with packs present; packs absent → card, CI green; TCC diff zero | NFR-23, FR-149 |
| TR-42 | Manual QA | QA | TR-30, TR-31 | S | Player auto-load of both SRT names (QuickTime, IINA, VLC); Devanagari rendering; macOS 26.x pass; 8 GB M1 1-hour file; owner sign-off on naming and Roman spelling **[QA][OWNER][HW]** | OWN-TR-1 |
| TR-43 | Licences, About, privacy copy | Release, UI | TR-20, TR-25 | S | MIT (whisper.cpp, Silero) and Apache-2.0 NOTICE (Trelis) in About › Licences and in the pack; privacy copy names both download sources and says audio stays on the Mac | FR-137 |

> [challenge] Acceptance additions to the rows above:
> - **TR-15:** add the hybrid-word rule ("ग्रीनland"), Latin casing (weekdays, months, "I", sentence start) and
>   pause-based `।`/`.` insertion (the punctuation part of OWN-TR-9, still open; the owner judges samples at TR-42).
> - **TR-16:** **one collision counter per result set**. Every name in the set uses the smallest n that is free for
>   all of them. Publish with `RENAME_EXCL`; on `EEXIST`, roll the set back to staging and retry with n + 1. Names:
>   `x Transcript Devanagari 2.txt`, `x Devanagari 2.srt`. "Devanagari only" keeps the marked name. Write one file
>   when the Devanagari text has no Devanagari characters (this is the usual case for English files under
>   OWN-TR-8 (a)). Needs an O-16 row for `<base>.srt` from a tool, and a 03a §4.3 amendment.
> - **TR-21:** set `flash_attn = false` whenever DTW is requested, and request DTW only for SRT/VTT/timestamp outputs
>   (OWN-TR-9, adopted). Clamp segment ends to the chunk end. Apply mixedcode on every chunk of a Hindi-route file
>   (as measured) unless TR-02 shows otherwise. The smoke test fails if any `t_dtw < 0` when DTW is on.
> - **TR-25:** ship the pack as separate hash-pinned files (no archive, so the disk check is 1.08 GB + 10 %). Resume
>   via a fresh GitHub redirect + `Range`/`If-Range`, restarting on an ETag change. Re-hash when (inode, size,
>   mtime) changes or after an app update. NOTICE credits Trelis, ARTPARK-IISc Whisper-Vaani (Apache-2.0; Vaani data
>   CC-BY-4.0) and OpenAI Whisper (MIT).
> - **TR-30:** TRANSCRIBE appears for the **whole audio family** (mp3 m4a wav flac **ogg opus aiff wma**) and every
>   ffprobe-readable video container with audio. Add P2-100 lint fixtures.
> - **TR-31:** fix the card copy. "Roman only" triggers a ≈ 250 MB macOS download, so it is not "no download". The
>   privacy copy names GitHub and Apple.
> - **TR-42:** check whether QuickTime auto-loads sidecar SRTs (probably not). Record whether VLC/IINA load both
>   `<base>.srt` and `<base> Devanagari.srt`. The owner judges punctuation and casing in sample output.
> - **TR-03:** repeat the no-prompt test with a Developer ID-signed, notarized build, from a fresh user account, on
>   macOS 26.x.
> - **TR-20:** license the mixedcode patch MIT (not GPL), so vendored whisper.cpp stays single-licence and the
>   `extra_prompt_tokens` field can go upstream.

### A.5 Add to §9.10 (effort tally)

| Group | Rows | Count | Days (S = 1, M = 3, L = 7.5) | Weeks |
|---|---|---|---|---|
| Transcription spikes | TR-01…TR-07 | 5 S / 2 M | 11 | ≈ 2.2 |
| Transcription build (replaces the P3-111 slot) | TR-10…TR-43 | 10 S / 9 M / 1 L | 44.5 | ≈ 8.9 |

### A.6 Add to §8 (owner and hardware dependencies)

OWN-TR-1…OWN-TR-7 (16 §14), open at their recommendations. OWN-TR-8 (Auto routing with the pack installed: option
(a)), OWN-TR-9 (word timing only when subtitles or timestamps are requested) and OWN-TR-10 (Hinglish mode on in Auto;
"Hindi" for formal Hindi) were adopted as defaults on 2026-10-22; the punctuation part of OWN-TR-9 stays open until
TR-42. [HW]: a macOS 26.x device or VM and an 8 GB M1 for TR-02, TR-03 and TR-42.

---

## B. `docs/plan/01b-prd-additions.md`

### B.1 Replace the FR-138 row in §C.10 and add FR-142…FR-149

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-138 | Transcribe audio and video | `TRANSCRIBE` slice on audio and on video with an audio stream; one drop, no dialog; English → one file; Hindi/Hinglish → Roman and Devanagari files by default; internal `Transcript` model with per-segment times, language tag and both script forms (16 §5.8); all outputs publish as one batch (Undo, History) | P3 |
| FR-142 | English on device without prompts | Apple `SpeechTranscriber` (SpeechAnalyzer) when the pack is not installed or Language = English; no Speech Recognition or microphone prompt (TCC diff zero); legacy `SFSpeechRecognizer` never used; Apple model download only after a card click; English TTS loose WER ≤ 0.03 | P3 |
| FR-143 | Language setting and Auto routing | Auto (default) / English / Hindi / Hinglish. Auto with the pack installed sends every file to the Hindi & Hinglish engine (OWN-TR-8 (a)); 100 % of English-dominant Hinglish fixtures reach it. Auto without the pack probes three 15 s windows with Apple en-US (English iff min confidence ≥ 0.80, ≈ 3 s); 10/10 corpus files and ≥ 95 % of TR-04 real files routed correctly; an English pass with ≥ 10 % low-confidence speech re-runs on the Hindi route | P3 |
| FR-144 | Hindi & Hinglish pack and both scripts | Trelis/whisper-hinglish-preview (Apache-2.0, pinned revision) as our own ggml q5_0 conversion + Silero VAD, 1.08 GB, user-initiated, SHA-256-pinned, resumable, removable; Devanagari file written by the model (English words in Roman); Roman file derived by the rule-based romaniser from the same pass (0 Devanagari chars); "Hindi and Hinglish files: Both / Roman only / Devanagari only" (default Both); declined pack on macOS 27+ → optional Apple hi-IN Roman-only result, labelled | P3 |
| FR-145 | Robust Hindi/Hinglish decoding | VAD chunks ≤ 20 s; restricted en/hi detection per chunk (no Urdu script); mixedcode token on every chunk of a Hindi-route file unless Language = Hindi (as measured; pending TR-02); greedy, no cross-chunk context; repetition guard; no invalid UTF-8 and no zero-length segments in any output; long10 (602 s) loose WER ≤ 0.07 | P3 |
| FR-146 | Formats and subtitle cues | Save as Text (default) / SRT / Text + SRT / WebVTT; cues ≤ 2 lines × 42 graphemes, 1–7 s, monotonic, no overlap; identical cue timing in both scripts; mid-chunk cue onset error median ≤ 0.25 s, p95 ≤ 0.6 s; segment ends clamped to the chunk; word timing (DTW) computed only when SRT/VTT or timestamps are requested (OWN-TR-9); optional paragraph timestamps in TXT; verification (UTF-8, NFC, last cue ≤ duration + 0.5 s) before publish | P3 |
| FR-147 | Naming, settings, CLI, History | `<base> Transcript.txt` / `<base> Transcript Devanagari.txt` / `<base>.srt` / `<base> Devanagari.srt` (`.vtt` likewise) with 03a §4.4 collision rules and one collision counter per result set; Settings › Transcription; progress card Change… resubmits; `zivlet transcribe` (never downloads, exit 8 when a model is missing); History kind `transcribe` with no text | P3 |
| FR-148 | Accuracy gates per language | 16a §11.3 table passes in `make asr-eval`: real Hindi (FLEURS) loose WER ≤ 0.20 / CER ≤ 0.11; real Hinglish loose ≤ 0.12, strict Devanagari ≤ 0.25, strict Roman ≤ 0.22; Hindi TTS ≤ 0.10; Hinglish TTS ≤ 0.07; mixed ≤ 0.10; English ≤ 0.03; gates re-baselined on TR-04 real sets, never looser | P3 |
| FR-149 | Progress and cancel for long files | Stage-weighted monotonic progress with ETA; idle sleep held off while running; Cancel ≤ 1 s for both engines, nothing published, staging removed; helper crash → one retry, then the crash message; "No speech found" writes nothing | P3 |

> [challenge] **FR-148:** the real-Hinglish gate is a single scripted sentence scored against the script. Re-reference
> it verbatim (TR-04) before it is binding. Mark TTS-only rows as regression alarms, not quality claims.

### B.2 Add to §D (non-functional)

| ID | Requirement | Target / acceptance | Verified by | Ph |
|---|---|---|---|---|
| NFR-25 | Transcription speed and memory | Quiet M2 Pro: Apple English ≥ 15× realtime (when no pack is installed or Language = English); Hindi/Hinglish pack, Text ≥ 2× (flash attention on; target ≥ 3× after TR-02) and SRT/VTT ≥ 1.5× (DTW, flash attention off); 8 GB M1: ≥ 1×, helper peak RSS ≤ 2.0 GB; first Apple result ≤ 3 s | TR-02, TR-40 | P3 |
| NFR-26 | ASR quality gate | No release, engine bump, model change or whisper.cpp patch change without a green `make asr-eval` report (FR-148); report kept with the release | TR-40 | P3 |

### B.3 Amend NFR-24 (size)

Add the line: "Transcription adds ≈ +7 MB installed / +2 MB DMG (helper + Metal shaders; models are downloads), or
≈ +2 MB installed if OWN-TR-3(b) moves the shader library into the pack. Decide with OWN-SIZE-1 on the measured
P1-52 DMG."

### B.4 Add to §E (success metrics)

| Metric | Target | Source |
|---|---|---|
| Hindi/Hinglish transcription accuracy | Real Hinglish loose WER ≤ 0.12 and real Hindi ≤ 0.20 on every release | `make asr-eval` (TR-40) |
| Transcription speed | Hindi/Hinglish ≥ 2× realtime on quiet M2 Pro (target 3×) | TR-02 / TR-40 |

---

## C. Other docs to touch when this lands (edits, not tasks)

| Doc | Edit | State |
|---|---|---|
| `docs/design/00-decisions.md` §(d) | Design pointer and the OWN-TR-8…10 outcomes | done 2026-10-22 |
| `docs/design/17-feature-roadmap.md` §5.4, §7, §8.1, §9, §10 | Slot filled; module = `EngineSpeech` + `ZivletTranscript`; size row "+7 MB (or +2 MB)"; licence rows for whisper.cpp (MIT), Trelis (Apache-2.0), Silero (MIT); "TRANSCRIBE sheet" wording removed | done 2026-10-22 |
| `docs/plan/02-architecture.md` §2.1, §4.1, §4.2 | Process row `zivlet-whisper` (signed helper, no entitlements, no network); modules `ZivletTranscript` (add to R1) and `EngineSpeech`; lane `speech` | open |
| `docs/plan/03a-system-design-interaction.md` §4.2, §4.3, §4.4, §4.6 | Lane `speech` width 1; one collision counter per result set; suffixes `Transcript`, `Transcript Devanagari`, `Devanagari`; helper cancellation row (SIGINT → SIGKILL +1 s), Apple `cancelAndFinishNow` row | open |
| `docs/design/17d-media-ai.md` §9 | Answered: segments + language + both scripts (16 §5.8); no `task=translate`; packs shared (P3-109); Phase 3 | open |
