# Architecture

## Modules

```
Sidetone (app) ──► SidetoneServices ──► SidetoneCore
     │                                      ▲
     └──────────► SidetoneAudio ────────────┘
```

| Target | Imports | Contents |
| --- | --- | --- |
| **SidetoneCore** | Foundation, Observation | Domain types (`Meeting`, `RecordingSession`, `SessionInfo`, `RecordingsLibrary`, `Preferences`), ports (`AudioCapturing`, `AudioMixing`, `MeetingProviding`, `MeetingAlerting`, `PermissionsProviding`, `SystemActions`), `SilenceMonitor`, and `SidetoneModel`, the `@Observable` state machine. |
| **SidetoneAudio** | AVFoundation, CoreAudio, Accelerate | `SystemAudioTap`, `MicCapture`, `MonoFileWriter`, `FloatRingBuffer`, `Downmix`, `RMSMeter`, `StereoMixer` (+ `MonoSource`). |
| **SidetoneServices** | EventKit, UserNotifications, AppKit | `CalendarAccess`, `NotificationManager`, `SystemPermissions`, `MacSystemActions`. |
| **Sidetone** | SwiftUI | `AppEnvironment` (composition root), `AppDelegate`, views in `Panel/`, `Components/`, `Preferences/`. |
| **SidetoneCheck** | Core, Audio | Hardware-free checks, `swift run SidetoneCheck`. |

`SidetoneModel` only sees protocols, so `Tests/SidetoneCheck/ModelChecks.swift` drives the whole
record / pause / save / discard / re-mix / quit flow with fakes.

## Recording flow

1. `startRecording` creates `~/Documents/Recordings/{yyyy-M-d}-{HHmm}[-title][-N]/` and starts both captures.
2. Each capture streams mono Float32 to its own CAF (`desktop.caf`, `mic.caf`).
3. `saveAndStop` stops both, writes `session.json` (each capture's first host time, rate, frame count),
   then mixes in the background into `audio.m4a`. Raw files are always kept.
4. If the mix fails or the app dies, the folder shows as "Not mixed" and **Mix now** rebuilds it from `session.json`.

## Threading model

- **Realtime threads** (Core Audio IOProc, AVAudioEngine tap): meter, downmix into preallocated scratch,
  `memcpy` into a lock-free SPSC ring. No allocation, no locks shared with control code, no disk.
- **Writer thread** (`MonoFileWriter`, one per capture): drains the ring to the CAF. If the device's sample
  rate changes mid-recording (`setSourceRate`), it resamples to the file's rate.
- **Main actor**: `SidetoneModel` and all UI. Audio callbacks hop over with `DispatchQueue.main.async`.
- **Utility task**: the stereo mix, streaming in 16k-frame chunks, so memory does not grow with recording length.

## Robustness

- **Watchdog** (`SystemAudioTap`): rebuilds tap + aggregate if output is running but the tap is silent for 3 s
  (macOS 26 zero-buffer regression).
- **Route changes** (`MicCapture`): on `AVAudioEngineConfigurationChange` the tap is reinstalled on the new format.
- **Quit**: `applicationShouldTerminate` saves an active recording and waits for mixes.
- **Mix atomicity**: encoded to `audio-partial.m4a`, then swapped in, so a failed mix never clobbers a good `audio.m4a`.
