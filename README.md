# Sidetone

A small, native macOS **menu-bar app** that records your meetings and voice notes with one
click. It captures **two audio sources at once** and mixes them into a single stereo file —
so you can always tell who was on the call from who was in the room:

- **Them / desktop audio → Left channel** (the people you hear through your speakers)
- **You / microphone → Right channel** (you, and anyone physically with you)

Pure Swift / SwiftUI. No Dock icon, no external runtime, no ffmpeg — just a single
ad-hoc-signed `.app`.

---

## Why two channels?

Most recorders give you one muddy mono mix. By hard-panning **system audio left** and **your
mic right**, the channels stay cleanly separated:

- You can mute/solo either side in any audio editor.
- A crash loses at most a fraction of a second: each source is written to its **own raw
  file continuously**, and the stereo mix is produced only when you hit Save.

---

## Features

- **One-click Record / Pause / Save / Trash** from a compact menu-bar panel.
- **Live level meters** for both channels (Them / You) while recording.
- **Calendar-aware**: the panel lists nearby meetings. Click one to start a recording named
  after it; the in-progress meeting is highlighted.
- **Recordings library**: browse and re-open past recordings from the panel, even after a
  relaunch.
- **Silence auto-stop**: ends a recording after a configurable period of two-channel silence
  (default 5 min).
- **Meeting-end notification** with a "Stop Recording" action when a meeting's scheduled end
  passes while you're still recording.
- **Safe to quit / crash**: quitting mid-recording saves it; an unmixed folder offers **Mix now**.
- **System-audio watchdog** that rebuilds the Core Audio tap if macOS's known process-tap
  regression makes it go silent mid-recording.

Sidetone does **not** transcribe. Use a separate tool (for example [Voce](https://github.com))
on the saved `audio.m4a` if you want text.

---

## How it works

| Concern | Approach |
| --- | --- |
| **Desktop audio** | Core Audio **process tap** (`CATapDescription` + `AudioHardwareCreateProcessTap`) wrapped in a tap-only private aggregate device, driven by an IOProc. Needs only the *Audio Recording* permission — **not** Screen Recording. |
| **Microphone** | A separate `AVAudioEngine` input tap. The engine is created on Record and torn down on Stop, so Sidetone does not hold the mic while idle. |
| **Two captures, merged on stop** | Each source streams to its own raw `.caf`. They're aligned (via first-buffer host-time skew), resampled to a common 48 kHz, interleaved (L=desktop, R=mic), and encoded to AAC `.m4a` only on Save. The raw files are kept. |
| **Realtime safety** | The IOProc runs on a hard-realtime thread. It does **memcpy only**, into a lock-free SPSC ring buffer; a background thread drains the ring to disk. |

The design is documented in depth in [`docs/research-notes.md`](docs/research-notes.md).

---

## Requirements

- **macOS 15+** (the realtime ring buffer uses the `Synchronization` module's `Atomic`).
- **Xcode / Swift 6.x Command Line Tools** to build.

---

## Build & run

```sh
swift run SidetoneCheck   # unit checks (no hardware, no network; CLT has no XCTest)
./make-icon.sh       # optional: regenerate Assets/Sidetone.icns
./build.sh           # swift build -c release, then assemble + ad-hoc-sign Sidetone.app
open ./Sidetone.app  # launches as a menu-bar item (no Dock icon)
```

The app is **non-sandboxed** and **ad-hoc signed**. If you rebuild with a different signature,
macOS may re-issue the permission prompts (TCC tracks the code signature).

---

## Permissions

Granted on first use via standard system prompts (declared in `Info.plist`):

- **Microphone** — to capture your voice.
- **System Audio Recording** — desktop audio via the Core Audio process tap. This is the
  *audio* permission, **not** Screen Recording; you'll see the purple privacy dot while
  recording.
- **Calendars (full access)** — to list nearby meetings and name recordings after them.
- **Notifications** — for the "meeting ended — still recording" alert.

---

## File layout

Recordings land in `~/Documents/Recordings/{YYYY-M-D}-{HHMM}[-{meeting}]/`:

```
desktop.caf    raw mono system audio  (flushed continuously while recording)
mic.caf        raw mono microphone    (flushed continuously while recording)
session.json   alignment data, used to re-mix if the mix failed or was interrupted
audio.m4a      stereo AAC mix — desktop = L, mic = R (produced on Save; raw files kept)
```

CAF (not WAV) is used for the raw files so long meetings don't hit the 4 GB WAV ceiling.

---

## Project structure

```
Sources/SidetoneCore/        domain, ports (protocols), SidetoneModel state machine (no system frameworks)
Sources/SidetoneAudio/       capture (system tap, mic), file writer, ring buffer, streaming stereo mixer
Sources/SidetoneServices/    EventKit, notifications, permissions, AppKit actions
Sources/Sidetone/            menu-bar app: composition root + SwiftUI views
Tests/SidetoneCheck/         hardware-free checks (`swift run SidetoneCheck`)
Assets/                      icon.swift + Sidetone.icns
docs/ARCHITECTURE.md         modules, recording flow, threading model
```

---

## License

[MIT](LICENSE).
