# Contributing

Sidetone is a small, system-framework-only Swift package. The goal is to stay readable: a bug should
be findable by reading one module.

## Prerequisites

- macOS 15+
- Swift 6.2+ (Xcode 26 or the matching Command Line Tools). Xcode is not required.

## Commands

```sh
swift build                      # debug build
swift run SidetoneCheck          # hardware-free checks (no devices, no network)
swift run SidetonePreview out/   # render every panel/setup/settings state to PNGs (light + dark)
./build.sh                       # release build -> ./Sidetone.app (ad-hoc signed)
./build.sh --install             # also replace /Applications/Sidetone.app and launch it
```

`swift run SidetonePreview out/ idle recording setup` limits the capture to named scenarios. It opens
real windows and uses `screencapture`, so it needs a logged-in session; the screenshots land in
`out/` (gitignored).

## Module rules

```
SidetoneCore    Foundation / Observation / os only. No AppKit, AVFoundation or EventKit.
SidetoneAudio   AVFoundation, Core Audio, Accelerate. Implements `AudioCapturing` / `AudioMixing`.
SidetoneServices EventKit, UserNotifications, AppKit. Implements the remaining ports.
SidetoneUI      SwiftUI + Core only. Views call model intent methods; they never touch audio.
Sidetone        Composition root. The only target that knows every concrete adapter.
```

If a view needs hardware, add a port in Core and an adapter in Services — do not import the
framework in UI.

## Realtime rules (SidetoneAudio)

Code that runs on the IOProc / AVAudioEngine tap may not:

- allocate or free memory,
- take a lock shared with control code,
- write to disk,
- call into `Logger` (formatting allocates).

It may: read its preallocated scratch memory, use `vDSP`, take the `OSAllocatedUnfairLock` flags that
are written only by control paths, and `memcpy` into the ring buffer. If you need more, hand it to
the writer thread.

## UI rules

- Every spacing, radius, colour, font and duration comes from `DS` in `Sources/SidetoneUI/Support/Design.swift`.
  If a value is missing, add it there rather than hard-coding it.
- 4 pt grid; one accent (amber `accent`), red only for a live recording, orange only for attention.
- Honour Reduce Motion: use the `motion(_:value:)` modifier rather than `.animation`.
- Every control needs an accessibility label and, when it shows a value, a value. Check both
  appearances (`SidetonePreview` renders light and dark).

## Checks

`swift run SidetoneCheck` is the test suite: plain `expect` assertions in `Tests/SidetoneCheck`.
Add a check with every behaviour change — especially anything that touches file layout, alignment
maths, or the model's state machine. The suite must stay at 0 failures.

## Privacy and secrets

Sidetone has no network code and no keys. Do not add analytics, remote calls, or checked-in
credentials. Personal data (recordings, API keys, real names) must never be committed; the repo is
public. See [`SECURITY.md`](SECURITY.md).

## Commits

Short imperative subject, a body that says why (not what), and the checks you ran. One logical change
per commit.
