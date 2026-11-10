# Architecture

Sidetone is a SwiftPM package with five modules and no third-party dependencies. Everything is a
system framework: AVFoundation, Core Audio, EventKit, UserNotifications, AppKit, SwiftUI.

```
Sidetone (app) ──► SidetoneServices ──► SidetoneCore
     │  │                                   ▲
     │  └──────► SidetoneAudio ─────────────┤
     └─────────► SidetoneUI ────────────────┘
```

| Target | Imports | Contents |
| --- | --- | --- |
| **SidetoneCore** | Foundation, Observation, os | Domain types (`Meeting`, `RecordingSession`, `SessionInfo`, `RecordingsLocation`, `RecordingsLibrary`, `Preferences`), ports (`AudioCapturing`, `AudioMixing`, `MeetingProviding`, `MeetingAlerting`, `PermissionsProviding`, `SystemActions`), `SilenceMonitor`, `MeterBridge`, `WaveformData`, and `SidetoneModel`, the `@Observable` state machine. |
| **SidetoneAudio** | AVFoundation, CoreAudio, Accelerate | `SystemAudioTap`, `MicCapture`, `MonoFileWriter`, `FloatRingBuffer`, `Downmix`, `RMSMeter`, `LevelStats`, `VoiceChain`, `StereoMixer` (+ `MonoSource`). |
| **SidetoneServices** | EventKit, UserNotifications, AppKit | `CalendarAccess`, `NotificationManager`, `SystemPermissions`, `MacSystemActions` (including the folder picker). |
| **SidetoneUI** | SwiftUI, AppKit, Core | Panel, setup, settings and the design tokens in `Support/Design.swift`. Depends only on Core, so the preview harness can host every screen with fakes. |
| **Sidetone** | Core, Audio, Services, UI | `AppEnvironment` (composition root), `AppDelegate`, the `@main` app. |

`SidetoneModel` only sees protocols, so `Tests/SidetoneCheck/ModelChecks.swift` drives the whole
record / pause / save / discard / re-mix / quit flow with fakes — no hardware, no permissions.

## Recording flow

1. `startRecording` asks `RecordingsLocation` for the folder (the user's choice, or
   `~/Documents/Recordings`) and creates `{yyyy-M-d}-{HHmm}[-title][-N]/`.
2. Both captures start, each streaming mono Float32 to its own CAF (`desktop.caf`, `mic.caf`).
3. `saveAndStop` stops both, writes `session.json` (each capture's first host time, rate, frame
   count, RMS and peak), then mixes in the background.
4. The mixer level-matches each channel from the measured RMS/peak, runs the mic through
   `VoiceChain` (high-pass, gentle noise-floor expander, limiter), and writes `audio.m4a` plus a
   mono `voice.m4a` — both in the same streaming pass.
5. `RecordingOutput.promote` moves a readable mix out to `{folder}.m4a` and the voice track to
   `{folder}.voice.m4a`, deletes the raw files, and removes the folder when empty. If the mix fails
   or the app dies first, the folder stays and **Mix now** rebuilds it from `session.json`.

The take in progress is never listed as a recent recording; the library only shows finished takes
and recoverable folders.

## Threading model

- **Realtime threads** (Core Audio IOProc, `AVAudioEngine` tap): meter, downmix into preallocated
  scratch, `memcpy` into a lock-free SPSC ring. No allocation, no locks shared with control code, no
  disk. The IOProc reads the incoming `AudioBufferList` in place instead of wrapping it in an
  `AVAudioPCMBuffer`, which would allocate on every callback.
- **Writer thread** (`MonoFileWriter`, one per capture): drains the ring to the CAF. If the device's
  sample rate changes mid-recording (`setSourceRate`), it resamples to the file's rate.
- **Main actor**: `SidetoneModel` and all UI.
- **Utility task**: the stereo mix, streaming in 16k-frame chunks, so memory does not grow with
  recording length. The voice chain is offline (mix time) and stateful across chunks.

## Voice quality

`LevelStats` accumulates RMS and peak on the producer side, only for the frames actually written
(paused audio is neither metered nor counted). At mix time:

- **Level match** — a static gain brings each channel to a -20 dBFS speech RMS, capped so the
  measured peak cannot go above -1 dBFS. Recordings made before 1.2 have no measurement and are
  left at their original level.
- **VoiceChain** — 70 Hz 12 dB/octave high-pass, a 2.5:1 downward expander (max 10 dB reduction,
  5 ms attack / 200 ms release) and a soft limiter at -1 dBFS. Deliberately gentle: an aggressive
  gate clips consonants and makes transcription worse.
- **Voice track** — the processed mic channel is encoded to mono AAC 96 kbps in the same pass as
  the stereo mix, so it costs no extra read of the raw file. A failure to write it is logged and
  never fails the recording.

### Meters without a main-queue storm

A tap fires every ~10 ms and the mic just as often. Forwarding every callback to main meant hundreds
of hops per second that mostly overwrote the same two floats. `MeterBridge` keeps the peak per
channel and delivers **at most one update per 50 ms** (20 Hz) on the main actor. That one update
feeds the levels, the scope history (`WaveformData`, 96 samples per channel) and the silence monitor.
`WaveformData` is its own `@Observable` object, so a level change redraws the scope only.

## Efficiency notes

- `RecordingsLibrary` caches a recording's duration by path + size + modification date, so opening
  the panel does not re-open every `.m4a`.
- `RecordingOutput.promoteFinishedFolders` skips a scan when the recordings folder's modification
  date has not changed.
- EventKit is read once per panel open / calendar change, not on a timer. The panel only uses a 30 s
  `TimelineView` to tick the "in progress" highlight.
- The watchdog is a 1 s `DispatchSourceTimer` that exists only between `start()` and `stop()`.
- Logging is `os.Logger`, one category per concern (`Log.app`, `Log.model`, `Log.capture`, `Log.mix`,
  `Log.library`, `Log.permissions`, `Log.alerts`); nothing is logged from a realtime thread.

## Robustness

- **Watchdog** (`SystemAudioTap`): rebuilds tap + aggregate if output is running but the tap is
  silent for 3 s (macOS 26 zero-buffer regression).
- **Route changes** (`MicCapture`): on `AVAudioEngineConfigurationChange` the tap is reinstalled on
  the new format and the writer switches source rate.
- **Quit**: `applicationShouldTerminate` saves an active recording and waits for every mix.
- **Mix atomicity**: encoded to `audio-partial.m4a`, then swapped in, so a failed mix never clobbers
  a good `audio.m4a`.
- **Permissions**: setup asks explicitly; recording re-checks the microphone status and the panel
  shows a per-permission banner with a direct link to the right System Settings pane.

## Preferences

All persisted keys live in `Preferences` (UserDefaults): silence timeout / threshold / auto-stop,
microphone on/off, the custom recordings folder, and whether setup was completed. `SidetoneModel`
mirrors them into observable properties, so the UI binds to the model while storage stays out of band.

## Logging

```sh
log stream --level debug --predicate 'subsystem == "com.mariocodarin.Sidetone"'
```

Lifecycle at `.notice` (launch, setup, capture start/stop, mix duration, folder changes), failures at
`.error`, per-refresh detail at `.debug`. `Log.begin`/`Span.end` measure the capture start and each
mix.
