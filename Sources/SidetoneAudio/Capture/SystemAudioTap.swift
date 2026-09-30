import Foundation
import SidetoneCore
import AVFoundation
import CoreAudio
import AudioToolbox
import os

/// Core Audio process tap (global system mix) -> `desktop.caf`.
///
/// Captures the entire system-output mix via a `CATapDescription` process tap wrapped in a
/// private, **tap-only** aggregate device (the canonical AudioCap pattern: default output as the
/// `"master"` sub-device, the tap in the tap-list with drift compensation). The IOProc downmixes
/// each buffer to mono, meters it, and hands it to a `MonoFileWriter`, which owns the ring buffer
/// and the disk thread. The IOProc itself NEVER allocates or touches the disk: doing so overran
/// the ~10 ms realtime deadline and tore the stream (audible as clicks).
///
/// macOS 26 has a confirmed regression where `AudioHardwareCreateProcessTap` + aggregate silently
/// delivers all-zero PCM after extended uptime / sample-rate / Bluetooth changes while the IOProc
/// keeps firing. A WATCHDOG detects "output is running but the tap is silent for ~3 s", tears down
/// BOTH the tap and the aggregate, rebuilds them, and keeps appending to the SAME file (the writer
/// resamples if the tap came back at a different rate).
public final class SystemAudioTap: AudioCapturing {

    // MARK: - Callbacks (audio / arbitrary threads)

    public var onLevelDB: ((Float) -> Void)?
    public var onFatalError: ((Error) -> Void)?

    public init() {}

    // MARK: - Errors

    enum TapError: LocalizedError {
        case createTapFailed(OSStatus)
        case noDefaultOutputDevice(OSStatus)
        case readDeviceUIDFailed(OSStatus)
        case createAggregateFailed(OSStatus)
        case readTapFormatFailed(OSStatus)
        case invalidTapFormat
        case createIOProcFailed(OSStatus)
        case startDeviceFailed(OSStatus)
        case fileOpenFailed(String)

        var errorDescription: String? {
            switch self {
            case .createTapFailed(let s):
                return "AudioHardwareCreateProcessTap failed (OSStatus \(s)). System Audio Recording permission may be denied."
            case .noDefaultOutputDevice(let s):
                return "Could not read the default system output device (OSStatus \(s))."
            case .readDeviceUIDFailed(let s):
                return "Could not read the output device UID (OSStatus \(s))."
            case .createAggregateFailed(let s):
                return "AudioHardwareCreateAggregateDevice failed (OSStatus \(s))."
            case .readTapFormatFailed(let s):
                return "Could not read kAudioTapPropertyFormat (OSStatus \(s))."
            case .invalidTapFormat:
                return "The tap returned an unusable audio format."
            case .createIOProcFailed(let s):
                return "AudioDeviceCreateIOProcIDWithBlock failed (OSStatus \(s))."
            case .startDeviceFailed(let s):
                return "AudioDeviceStart failed (OSStatus \(s))."
            case .fileOpenFailed(let m):
                return "Could not open the desktop capture file: \(m)"
            }
        }
    }

    // MARK: - State guarded by `lock`

    /// Guards the Core Audio handles and lifecycle flags below. Never taken on the audio thread:
    /// stop()/rebuild hold it across `AudioDeviceStop`, which waits for the IOProc to return.
    private let lock = OSAllocatedUnfairLock()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapUUID = UUID()
    private var started = false
    private var rebuilding = false

    /// Owns the ring + disk thread; stays open across watchdog rebuilds, finished only in `stop()`.
    private var writer: MonoFileWriter?
    /// Preallocated mono scratch for the multi-channel downmix (no per-callback allocation).
    private var scratch: UnsafeMutablePointer<Float>?
    private let scratchCapacity = 16_384
    private var capturedResult = CaptureResult()

    private static let log = Logger(subsystem: "com.mariocodarin.Sidetone", category: "SystemAudioTap")

    // MARK: - Realtime-path flags (separate locks so the IOProc never waits on `lock`)

    private let paused = OSAllocatedUnfairLock<Bool>(initialState: false)
    /// Host time of the last buffer the IOProc saw above the "loud" floor (watchdog input).
    private let lastLoudHostTime = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    // MARK: - Watchdog

    private var watchdogTimer: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "systemaudiotap.watchdog")
    /// If output is audibly running but the tap delivers ~silence for this long, rebuild.
    private let watchdogSilenceThreshold: TimeInterval = 3.0
    /// Anything above this counts as "the tap is alive" for the watchdog (~ -90 dBFS).
    private static let aliveFloorDB: Float = -90

    // Throttle the meter callback to ~15 Hz (touched only by the IOProc).
    private var lastMeterPostHostTime: UInt64 = 0
    private static let meterIntervalNanos: UInt64 = 66_000_000

    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    private static func hostTimeToNanos(_ hostTime: UInt64) -> UInt64 {
        let tb = timebase
        // Split the multiply to avoid overflow on large host times.
        return hostTime / UInt64(tb.denom) * UInt64(tb.numer)
            + (hostTime % UInt64(tb.denom)) * UInt64(tb.numer) / UInt64(tb.denom)
    }

    // MARK: - Public API

    /// Build the tap + aggregate, open the file, install the IOProc and start the device.
    public func start(writingTo url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }

        tapUUID = UUID()
        capturedResult = CaptureResult()

        do {
            try startLocked(url: url)
        } catch TapError.createTapFailed {
            throw CaptureError.permissionDenied(.desktop)
        }
    }

    private func startLocked(url: URL) throws {
        // 1) Tap + aggregate, and the format the tap delivers.
        let tapFormat = try buildTapAndAggregateLocked()

        // 2) Writer (ring + disk thread) BEFORE the IOProc starts producing.
        let newWriter: MonoFileWriter
        do {
            newWriter = try MonoFileWriter(url: url, sampleRate: tapFormat.sampleRate)
        } catch {
            destroyTapAndAggregateLocked()
            throw TapError.fileOpenFailed(error.localizedDescription)
        }
        newWriter.onError = { [weak self] in self?.onFatalError?($0) }
        writer = newWriter
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        capturedResult.sampleRate = tapFormat.sampleRate

        // 3) IOProc + start the aggregate device.
        do {
            try installIOProcAndStartLocked(tapFormat: tapFormat)
        } catch {
            releaseWriterLocked()
            destroyTapAndAggregateLocked()
            throw error
        }

        started = true
        lastLoudHostTime.withLock { $0 = mach_absolute_time() }
        startWatchdog()
    }

    /// Gate writes. Device keeps running, meters keep updating. Thread-safe.
    public func setPaused(_ isPaused: Bool) {
        paused.withLock { $0 = isPaused }
    }

    /// Stop the IOProc, destroy the aggregate + tap, finalize the file.
    public func stop() -> CaptureResult {
        stopWatchdog()

        lock.lock()
        defer { lock.unlock() }

        guard started else { return capturedResult }
        started = false

        // AudioDeviceStop blocks until the last IOProc callback returns, so the producer is fully
        // stopped after this; only then is it safe to drain and close the writer.
        destroyTapAndAggregateLocked()
        releaseWriterLocked()
        return capturedResult
    }

    /// Drain + close the writer and remember what it captured. Caller holds `lock`.
    private func releaseWriterLocked() {
        if let summary = writer?.finish() {
            capturedResult.firstHostTime = summary.firstHostTime
            capturedResult.frameCount = AVAudioFramePosition(summary.framesWritten)
        }
        writer = nil
        scratch?.deallocate()
        scratch = nil
    }

    // MARK: - Build / teardown (caller must hold `lock`)

    /// Create the process tap and the private tap-only aggregate device; return the tap's format.
    /// On any failure, partially-created objects are destroyed and the error is thrown.
    private func buildTapAndAggregateLocked() throws -> AVAudioFormat {
        // 1. Process tap: global stereo mix, passthrough, private.
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = tapUUID
        desc.muteBehavior = .unmuted   // passthrough: the user still hears their audio
        desc.isPrivate = true          // do not advertise this tap system-wide

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard tapStatus == noErr, newTapID != kAudioObjectUnknown else {
            throw TapError.createTapFailed(tapStatus)
        }
        tapID = newTapID

        do {
            // 2. Default output device UID = the aggregate's master clock.
            let outputUID = try Self.deviceUID(try Self.defaultSystemOutputDevice())

            // 3. Private, tap-only aggregate. Output = master (drift comp off); tap in the
            //    tap-list with drift compensation on. The mic is NOT part of this aggregate.
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Sidetone System Tap",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID, kAudioSubDeviceDriftCompensationKey: 0]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: tapUUID.uuidString, kAudioSubTapDriftCompensationKey: 1]
                ]
            ]

            var newAggregateID = AudioObjectID(kAudioObjectUnknown)
            let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
            guard aggStatus == noErr, newAggregateID != kAudioObjectUnknown else {
                throw TapError.createAggregateFailed(aggStatus)
            }
            aggregateID = newAggregateID

            // 4. The tap's actual stream format.
            return try Self.tapStreamFormat(newTapID)
        } catch {
            destroyTapAndAggregateLocked()
            throw error
        }
    }

    /// Install the IOProc on the aggregate and start it. Caller MUST hold `lock`.
    private func installIOProcAndStartLocked(tapFormat: AVAudioFormat) throws {
        guard aggregateID != kAudioObjectUnknown else {
            throw TapError.createIOProcFailed(kAudioHardwareBadObjectError)
        }
        guard let writer, let scratch else { throw TapError.invalidTapFormat }

        // Everything the realtime callback needs is captured here so it never reads `self`'s
        // mutable state. The proc is torn down (synchronously) before any of it is released.
        let context = IOContext(format: tapFormat, writer: writer, scratch: scratch, scratchCapacity: scratchCapacity)
        var newProcID: AudioDeviceIOProcID?
        let ioBlock: AudioDeviceIOBlock = { [weak self] _, inInputData, inInputTime, _, _ in
            self?.handleIO(inputData: inInputData, inputTime: inInputTime, context: context)
        }

        let createStatus = AudioDeviceCreateIOProcIDWithBlock(&newProcID, aggregateID, nil, ioBlock)
        guard createStatus == noErr, let procID = newProcID else {
            throw TapError.createIOProcFailed(createStatus)
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
            throw TapError.startDeviceFailed(startStatus)
        }
    }

    /// Destroy the IOProc, aggregate device, and tap. Caller MUST hold `lock`. Best-effort; safe when
    /// partially built. Does NOT touch the writer (so a watchdog rebuild keeps appending).
    private func destroyTapAndAggregateLocked() {
        if let procID = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    // MARK: - IO callback (realtime thread)

    private struct IOContext {
        let format: AVAudioFormat
        let writer: MonoFileWriter
        let scratch: UnsafeMutablePointer<Float>
        let scratchCapacity: Int
    }

    private func handleIO(
        inputData: UnsafePointer<AudioBufferList>,
        inputTime: UnsafePointer<AudioTimeStamp>,
        context: IOContext
    ) {
        let now = mach_absolute_time()

        // Wrap the incoming buffer list without copying.
        guard let pcm = AVAudioPCMBuffer(pcmFormat: context.format, bufferListNoCopy: inputData, deallocator: nil),
              pcm.frameLength > 0,
              let channelData = pcm.floatChannelData else { return }

        let frames = Int(pcm.frameLength)
        let channelCount = Int(context.format.channelCount)

        // Meter + watchdog input (channel 0 is cheap and representative).
        let db = RMSMeter.dBFS(samples: channelData[0], count: frames)
        if db > Self.aliveFloorDB {
            lastLoudHostTime.withLock { $0 = now }
        }
        if Self.hostTimeToNanos(now &- lastMeterPostHostTime) >= Self.meterIntervalNanos {
            lastMeterPostHostTime = now
            onLevelDB?(db)
        }

        // Pause gate: meters keep updating above; only the write is skipped.
        if paused.withLock({ $0 }) { return }

        // REALTIME-SAFE ONLY below: downmix into preallocated scratch, memcpy into the ring.
        let hostTime = inputTime.pointee.mHostTime
        if channelCount <= 1 {
            context.writer.write(channelData[0], count: frames, hostTime: hostTime)
            return
        }
        // IO buffers are tiny, so this loop runs once in practice.
        var offset = 0
        while offset < frames {
            let chunk = min(frames - offset, context.scratchCapacity)
            Downmix.toMono(
                channels: channelData, channelCount: channelCount,
                offset: offset, frames: chunk, into: context.scratch
            )
            context.writer.write(context.scratch, count: chunk, hostTime: hostTime)
            offset += chunk
        }
    }

    // MARK: - Watchdog (macOS 26 zero-buffer regression)

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        watchdogTimer = timer
        timer.resume()
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        // Silence is expected while paused.
        if paused.withLock({ $0 }) { return }

        lock.lock()
        let isRunning = started && !rebuilding
        lock.unlock()
        guard isRunning else { return }

        // Only rebuild if the system output is actually doing something — otherwise silence is
        // legitimately silence and a rebuild would be pointless churn.
        guard let outDevice = try? Self.defaultSystemOutputDevice(),
              Self.deviceIsRunningSomewhere(outDevice) else { return }

        let silentFor = Self.hostTimeToNanos(mach_absolute_time() &- lastLoudHostTime.withLock { $0 })
        if Double(silentFor) / 1_000_000_000 >= watchdogSilenceThreshold {
            rebuildTapAndAggregate()
        }
    }

    /// Tear down and rebuild BOTH the tap and the aggregate, reinstall the IOProc, and keep writing
    /// to the SAME file. Rebuilding only one is insufficient per the regression report.
    private func rebuildTapAndAggregate() {
        lock.lock()
        guard started, !rebuilding else {
            lock.unlock()
            return
        }
        rebuilding = true
        defer {
            rebuilding = false
            lock.unlock()
        }

        // The device is stopped after this, so the producer is quiescent.
        destroyTapAndAggregateLocked()
        tapUUID = UUID()

        do {
            let tapFormat = try buildTapAndAggregateLocked()
            // If the tap came back at a different rate, have the writer resample to the file's rate.
            writer?.setSourceRate(tapFormat.sampleRate)
            try installIOProcAndStartLocked(tapFormat: tapFormat)
        } catch {
            // Fatal for the desktop stream: surface it. The mic and the desktop audio captured so
            // far stay intact on disk.
            onFatalError?(error)
            return
        }

        // Give the fresh tap a fair window before judging it again.
        lastLoudHostTime.withLock { $0 = mach_absolute_time() }
    }

    // MARK: - Core Audio property helpers

    /// Read the default system output device ID.
    private static func defaultSystemOutputDevice() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw TapError.noDefaultOutputDevice(status)
        }
        return deviceID
    }

    /// Read a device's UID string.
    private static func deviceUID(_ deviceID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // CoreAudio writes a retained CFString into the pointer; bridge it to Swift afterward.
        var cfUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfUID)
        guard status == noErr, let uid = cfUID?.takeRetainedValue() else {
            throw TapError.readDeviceUIDFailed(status)
        }
        return uid as String
    }

    /// Read `kAudioTapPropertyFormat` ('tfmt') and build an `AVAudioFormat`.
    private static func tapStreamFormat(_ tapID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else {
            throw TapError.readTapFormatFailed(status)
        }
        guard asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0,
              let format = AVAudioFormat(streamDescription: &asbd) else {
            throw TapError.invalidTapFormat
        }
        return format
    }

    /// Is the device currently running an IO stream somewhere on the system?
    private static func deviceIsRunningSomewhere(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
        guard status == noErr else { return false }
        return running != 0
    }
}
