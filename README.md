# Talkeet

A native macOS app for editing talking-head videos. Talkeet detects silences, lets you review and adjust the cuts on a waveform timeline, transcribes speech locally with WhisperX, and exports the edit to the formats used by DaVinci Resolve, Final Cut Pro, and Premiere Pro.

Everything runs on-device — no cloud APIs, no API keys, no uploads.

---

## How it works

Talkeet is split into two independent layers that talk to each other over `localhost`:

- **Backend (Python / FastAPI)** — does the heavy lifting: silence detection, waveform extraction, WhisperX transcription, and export file generation. Runs as a local server on `localhost:8742`, launched and stopped automatically by the macOS app.
- **Frontend (Swift / SwiftUI)** — the native UI: video playback (AVKit), waveform timeline, segment list, and export controls. Talks to the backend over REST and WebSockets.

```
[MP4 file]
    → Backend: silence detection            → segments JSON
    → Backend: waveform extraction           → float array JSON
    → Backend: WhisperX transcription        → words + timestamps JSON
    → Frontend: review and edit segments
    → Backend: export to EDL / FCPXML / Premiere XML + SRT
```

## Tech stack

| Layer                   | Technology                          |
|--------------------------|--------------------------------------|
| Backend language        | Python 3.11+                        |
| Backend framework       | FastAPI + Uvicorn                   |
| Audio/video processing  | ffmpeg (bundled binary, via subprocess) |
| Transcription           | WhisperX (local, CPU)               |
| Backend packaging       | uv                                   |
| Frontend language       | Swift 6.2+                          |
| Frontend framework      | SwiftUI (macOS 26+)                 |
| Video playback          | AVKit                               |
| HTTP/WebSocket client   | URLSession                          |

## Export formats

| Target NLE       | Format          | Notes                          |
|--------------------|------------------|----------------------------------|
| DaVinci Resolve   | EDL (CMX 3600)  | Primary target                  |
| Final Cut Pro     | FCPXML          | Secondary                       |
| Premiere Pro      | Premiere XML    | Secondary                       |
| Subtitles (any NLE) | SRT           | Exported separately, imported manually |

## Requirements

- macOS 26 (Tahoe) or later
- ffmpeg (bundled in the packaged app; required on `PATH` or via `FFMPEG_PATH` for local development)
- Python 3.11+ and [uv](https://github.com/astral-sh/uv) (backend development)
- Xcode (frontend development)

## Getting started (development)

### 1. Backend

```bash
cd backend
uv sync --group dev
FFMPEG_PATH=$(which ffmpeg) uv run uvicorn app.main:app --port 8742 --reload
```

Transcription (WhisperX) is a separate dependency group — install it only when you need Milestone 2 functionality, since it pins specific `torch`/`torchaudio` versions:

```bash
uv sync --group transcription
```

Verify the server is up:

```bash
curl http://localhost:8742/health
# {"status":"ok"}
```

Full API reference, example requests, and the WhisperX model-size/RAM table: [`backend/README.md`](backend/README.md).

### 2. Frontend

Open `frontend/Talkeet/Talkeet.xcodeproj` in Xcode and run. The app starts the backend process automatically and polls `/health` until ready — no need to run the backend manually when working in the app.

## Project structure

```
backend/            FastAPI server — silence detection, waveform, transcription, export
  app/routers/       HTTP/WebSocket route handlers
  app/services/      Core processing logic (ffmpeg, WhisperX, export generators)
  tests/              Unit + integration tests (pytest)
  resources/          Reference scripts (e.g. waveform visualization)
frontend/Talkeet/    SwiftUI macOS app (Xcode project)
  Talkeet/Views/       Video player, waveform timeline, segment list
  Talkeet/ViewModels/  App state and orchestration
  Talkeet/Services/    Backend lifecycle + HTTP/WebSocket clients
  Talkeet/Models/      Shared data models (segments, etc.)
milestones/          Per-milestone specs and acceptance criteria
docs/                 Design and planning notes
```

## Project status

Talkeet is under active development, built milestone by milestone. Backend processing (silence detection, transcription, waveform extraction, and all four export formats) is complete and tested. The SwiftUI frontend has video playback, a segment list, and a waveform timeline with zoom/scroll; playhead sync, segment editing, the parameters panel, and the export panel are in progress.

| # | Milestone | Status |
|---|------------|--------|
| 1 | Backend scaffold + silence detection | ✅ Done |
| 2 | WhisperX transcription endpoint | ✅ Done |
| 3 | Waveform extraction endpoint | ✅ Done |
| 4 | Export endpoints (EDL / FCPXML / Premiere / SRT) | ✅ Done |
| 5 | SwiftUI app scaffold + backend lifecycle | ✅ Done |
| 6 | Video player + segment list | 🚧 In progress |
| 7 | Waveform timeline | 🚧 In progress |
| 8 | Segment editor + keep/cut decisions | ⬜ Not started |
| 9 | Parameters panel + WhisperX integration | ⬜ Not started |
| 10 | Export panel + final polish | ⬜ Not started |

See [`milestones/`](milestones/) for the full spec and acceptance criteria of each milestone.

## Key constraints

- All processing runs locally — no cloud inference, no API keys.
- WhisperX always runs on CPU on Apple Silicon (`compute_type="int8"`); MPS is not supported by CTranslate2.
- ffmpeg is bundled with the packaged app and never resolved via system `PATH` in production.
- The app works with the original video file in place — it never copies or moves the source file.
- Backend listens on a fixed port, `localhost:8742`.

## Out of scope (for now)

- Multi-track or multicam editing
- Real-time silence detection while recording
- Direct NLE plugin / extension
- Windows or Linux support

## Testing

```bash
# Backend unit tests (no video needed)
cd backend
FFMPEG_PATH=$(which ffmpeg) uv run pytest -v

# Backend integration tests (require a real video file)
TEST_VIDEO=/path/to/video.mp4 FFMPEG_PATH=$(which ffmpeg) uv run pytest -v
```

Frontend tests run from Xcode (`TalkeetTests` / `TalkeetUITests` targets).

## License

TBD.
