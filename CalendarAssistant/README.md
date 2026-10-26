# Personal Memory Calendar (Mac companion)

Watch recording → iPhone → Mac import → the day's on-device transcription → local LLM: calendar and memo suggestions the user reviews, and the day's memory (一日の記憶). No cloud AI, no API keys.

## Run

`zsh build-app.sh` creates a new, ad-hoc signed development .app under Builds, without replacing an installed application. Open that .app, not the bare executable: speech/calendar privacy descriptions live in the bundle. macOS 14+; Japanese local speech availability depends on the device. This is not a notarized or sandboxed distribution build.

Getting recordings from the iPhone (any of these):

- **Shared folder (recommended)**: pick the same folder on the iPhone (Macと同期 → iCloud Driveのフォルダ経由) and here (共有フォルダ). `iCloud Drive/Personal Memory` is used automatically when it exists. The iPhone puts each recording there as one `<id>.pmchunk` file; this app checks the folder every 20 seconds while open, asks iCloud to download pieces not yet on this Mac, verifies SHA-256 and imports. The folder is only read.
- **Same Wi‑Fi**: enter the 6-digit code shown here on the iPhone and send directly.
- **Manual**: 録音を読み込む and select an m4a (for example one shared by AirDrop).

**日ごと (main screen, 2026-10-26)**: received pieces are grouped by the day they started (`RecordingDays`). Pick a day button, then:

- **この日を文字起こし** transcribes every piece of the day on this Mac, one at a time, and saves each piece's text as soon as it is done (`DayTranscriptBook`, `DayTranscripts/<yyyy-MM-dd>.transcript.json`). Stopping keeps the finished pieces; pressing again continues. Silent pieces are recorded as empty, not as failures.
- **項目に分けて提案** sends the day's text, about 6,000 characters at a time, to the local model only, which returns calendar and memo suggestions. `ItemSuggestionDecoder` drops any item whose quote is not in the text, and leaves unclear times empty. Suggestions and the user's decisions (edited, dismissed, saved) are kept in `DaySuggestions/<yyyy-MM-dd>.suggestions.json` (`DaySuggestionBook`). Asking again adds only new suggestions.
- **カレンダーに保存… / メモに保存…** saves one confirmed item: Calendar through write-only EventKit, Notes through one AppleScript `make new note` (macOS asks once for Automation permission; Notes is never read). `saving` is recorded before the save, so an interrupted save is shown for checking instead of being repeated.
- **この日の音声を削除…** moves this Mac's audio for the day to the Trash (`SessionChunkWorkspace.retireAudio`). Receipts, transcript and suggestions stay, so the shared folder does not bring the pieces back. The iPhone and shared-folder copies are not touched.

**ファイルから** (the older screen) still imports a single m4a:

1. Imports a separate local copy (m4a, 1–20 MB). Original remains unchanged. Content hash identifies repeat imports and reopens their saved drafts and registration states.
2. Confirm recording date: file creation date may have changed during sharing. Relative dates such as 明日 use this editable reference and the captured time zone.
3. Listen to the recording; run Japanese on-device speech or paste/correct a transcript. Recordings up to 15 minutes are split into sections under Speech's one-minute limit. No silent truncation or server fallback.
4. 予定を提案 sends text to **127.0.0.1:11434 only**, using configured Ollama model. No redirect, tool calls, calendar access or auto-install. Default is the user's installed Qwen3.8-27B GGUF label; this does not establish model provenance or benchmark parity.
5. Read source quotes next to editable proposals. Missing date/time stays missing. Confirm title and times individually. Each change clears confirmation.
6. A second explicit confirmation precedes write-only EventKit authorization and one event save. No inferred attendees, invites, recurrence, alarms or full transcript attachment. Calendar account sync may transmit the event according to the user's calendar settings; local-first does **not** mean a cloud calendar will stay local.

## Boundaries / safety

- `CalendarDomain`: proposal contract, deterministic decoder, local workspace. No SwiftUI, EventKit or Speech.
- `MemoryCalendarApp`: separate speech, loopback inference and calendar adapters; session orchestrates explicit actions; views don't write calendar records.
- Drafts and pending/saved submissions persist under Application Support/PersonalMemoryCalendar/Recordings. Pending is written **before** EventKit save. On uncertain outcome, block automatic retry and ask the user to inspect Calendar. After any registration attempt, do not re-extract that recording and lose submission IDs.
- Write-only access intentionally does not read existing events. Cross-recording duplicate detection and calendar conflict checks are not implemented. We cannot promise exactly-once side effects across OS/app crashes; uncertain means uncertain.
- Local atomic writes are not a network durable-storage acknowledgement or a power-loss durability guarantee. The only network listener is the opt-in same-Wi‑Fi receiver, which requires the 6-digit code.
- Same-user hostile filesystem mutation, concurrent multiple app processes, export/deletion UI, speech-model downloads, arbitrary language selection and multi-calendar browsing are deferred.

## Evidence-led UX decisions

- [Apple Voice Memos transcription](https://support.apple.com/guide/voice-memos/view-a-transcription-of-a-recording-vm4a03609f0d/mac): keep audio accessible alongside text, rather than discarding the original after AI extraction.
- [Microsoft Outlook Copilot](https://support.microsoft.com/en-us/outlook/copilot-outlook/create-a-meeting-agenda-with-copilot-in-outlook): editable draft → review → explicit send. Applied here to calendar registration, without copying automatic attendee inclusion.
- [Apple EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store): request only write-only access needed to add confirmed events. Its virtual calendar is not a readable list of the user's calendars; the UI does not pretend to offer a real calendar picker.
- [Apple on-device recognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition): set requiresOnDeviceRecognition **and** verify supportsOnDeviceRecognition. Do not fall back to server recognition.
- [Ollama chat API](https://docs.ollama.com/api/chat): bounded local requests and parse results as untrusted drafts, never commands.
- [Reducing Hallucinated Transcripts in Whisper, 2026-09-03 preprint](https://arxiv.org/abs/2609.04561): addresses fabricated text on low/no speech, with recognition trade-offs. It studies Whisper, **not Apple's recognizer**; we do not transfer its accuracy numbers or claim its mitigation is implemented. It motivates preserving playback and requiring transcript review rather than treating fluent text as proof of speech.

These are implementation/UX references, not evidence that a local model matches their accuracy. Live speech and calendar permission paths require separate application-level validation; passing parser tests is insufficient.

## Status

Verified on real devices (2026-10-25): Watch recordings reached this app through iCloud Drive with matching SHA-256, and the day's memory was produced from a synthetic transcript by a local 27B model with every quote grounded in the transcript. Still unverified: Calendar permission/save/denial on a real calendar, and long-term background behaviour. This is a development build, not a notarized release.
