import Foundation
import SidetoneCore
import AVFoundation
import os

/// Microphone capture via `AVAudioEngine`'s input node, written MONO to `mic.caf`.
///
/// Design notes:
/// - An *independent* engine from the system-audio tap. `StereoMixer` aligns the two raw files
///   afterwards from each stream's first-sample host time, which is why the first delivered
///   buffer's `AVAudioTime` is recorded.
/// - The input format is read LIVE from the hardware — never hardcoded — or AVAudioEngine asserts
///   on a rate mismatch (Bluetooth mics / AirPods commonly run 16 kHz mono input).
/// - The tap block never touches the disk: it downmixes into preallocated scratch and hands the
///   samples to a `MonoFileWriter` (ring + writer thread), like the desktop tap.
/// - When the audio route changes mid-recording (AirPods connect, default input switches) the
///   engine stops itself and posts `AVAudioEngineConfigurationChange`; we reinstall the tap on the
///   new format and keep appending to the same file (the writer resamples to the file's rate).
/// - The engine exists only between `start()` and `stop()` so an idle Sidetone doesn't hold the
///   mic (which would keep AirPods in call mode).
public final class MicCapture: AudioCapturing {

    public var onLevelDB: ((Float) -> Void)?
    public var onFatalError: ((Error) -> Void)?

    public init() {}

    // MARK: - Errors

    enum MicError: LocalizedError {
        case couldNotCreateFile(URL, underlying: Error)
        case invalidInputFormat

        var errorDescription: String? {
            switch self {
            case .couldNotCreateFile(let url, let underlying):
                return "Could not open mic file at \(url.lastPathComponent): \(underlying.localizedDescription)"
            case .invalidInputFormat:
                return "Microphone reported an unusable input format (0 channels or 0 Hz)."
            }
        }
    }

    // MARK: - State

    private var engine: AVAudioEngine?
    private var writer: MonoFileWriter?
    private var configObserver: NSObjectProtocol?
    private var result = CaptureResult()

    /// Serializes start/stop against route-change restarts.
    private let controlQueue = DispatchQueue(label: "com.mariocodarin.Sidetone.micControl")

    /// Read on the audio thread, written from control paths — hence the lock.
    private let paused = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let running = OSAllocatedUnfairLock<Bool>(initialState: false)

    private let scratchCapacity = 16_384
    private var scratch: UnsafeMutablePointer<Float>?

    // MARK: - Start

    /// Begin capturing the microphone, writing MONO Float32 to `url` (CAF).
    public func start(writingTo url: URL) throws {
        try controlQueue.sync { try startOnQueue(url: url) }
    }

    private func startOnQueue(url: URL) throws {
        tearDownEngine()
        result = CaptureResult()

        let engine = AVAudioEngine()
        self.engine = engine
        let inputFormat: AVAudioFormat
        do {
            // AirPods HFP settle can report 0 ch / 0 Hz for a few hundred ms.
            inputFormat = try Self.waitForValidInputFormat(engine.inputNode)
        } catch {
            tearDownEngine()
            throw error
        }

        let newWriter: MonoFileWriter
        do {
            newWriter = try MonoFileWriter(url: url, sampleRate: inputFormat.sampleRate)
        } catch {
            tearDownEngine()
            throw MicError.couldNotCreateFile(url, underlying: error)
        }
        newWriter.onError = { [weak self] error in
            self?.running.withLock { $0 = false }
            self?.onFatalError?(error)
        }
        writer = newWriter
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        result.sampleRate = inputFormat.sampleRate
        paused.withLock { $0 = false }
        running.withLock { $0 = true }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.controlQueue.async { self?.restartAfterRouteChange() }
        }

        installTap(on: engine, format: inputFormat, writer: newWriter)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            running.withLock { $0 = false }
            tearDownEngine()
            releaseWriter()
            throw error
        }
    }

    private func installTap(on engine: AVAudioEngine, format: AVAudioFormat, writer: MonoFileWriter) {
        guard let scratch else { return }
        let capacity = scratchCapacity
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
            self?.handleBuffer(buffer, when: when, writer: writer, scratch: scratch, scratchCapacity: capacity)
        }
    }

    /// Wait briefly for HAL to publish a real input format (Bluetooth headset profile switch).
    private static func waitForValidInputFormat(_ inputNode: AVAudioInputNode) throws -> AVAudioFormat {
        var format = inputNode.inputFormat(forBus: 0)
        if format.channelCount > 0, format.sampleRate > 0 { return format }
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.05)
            format = inputNode.inputFormat(forBus: 0)
            if format.channelCount > 0, format.sampleRate > 0 { return format }
        }
        throw MicError.invalidInputFormat
    }

    // MARK: - Route changes

    /// The engine has stopped itself after a route/format change: rebuild the tap on the new
    /// input format and carry on appending to the same file. Runs on `controlQueue`.
    private func restartAfterRouteChange() {
        guard running.withLock({ $0 }), let engine, let writer else { return }

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }

        do {
            let format = try Self.waitForValidInputFormat(engine.inputNode)
            // The tap is removed, so the producer is quiescent: safe to switch the writer's rate.
            writer.setSourceRate(format.sampleRate)
            installTap(on: engine, format: format, writer: writer)
            engine.prepare()
            try engine.start()
        } catch {
            running.withLock { $0 = false }
            onFatalError?(error)
        }
    }

    // MARK: - Tap block (audio thread)

    private func handleBuffer(
        _ buffer: AVAudioPCMBuffer,
        when: AVAudioTime,
        writer: MonoFileWriter,
        scratch: UnsafeMutablePointer<Float>,
        scratchCapacity: Int
    ) {
        // Always meter, even while paused, so the UI keeps moving.
        onLevelDB?(RMSMeter.dBFS(buffer))

        guard running.withLock({ $0 }), !paused.withLock({ $0 }) else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0, let channels = buffer.floatChannelData else { return }

        let hostTime = when.isHostTimeValid ? when.hostTime : mach_absolute_time()
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            writer.write(channels[0], count: frames, hostTime: hostTime)
            return
        }
        var offset = 0
        while offset < frames {
            let chunk = min(frames - offset, scratchCapacity)
            Downmix.toMono(channels: channels, channelCount: channelCount, offset: offset, frames: chunk, into: scratch)
            // Host time only matters for the first frame; later chunks reuse it harmlessly.
            writer.write(scratch, count: chunk, hostTime: hostTime)
            offset += chunk
        }
    }

    // MARK: - Pause / Stop

    /// Gate writes without tearing down the engine; meters keep updating while paused.
    public func setPaused(_ isPaused: Bool) {
        paused.withLock { $0 = isPaused }
    }

    /// Stop the engine, finalize the file, and return what was captured.
    public func stop() -> CaptureResult {
        controlQueue.sync {
            running.withLock { $0 = false }
            tearDownEngine()
            releaseWriter()
            return result
        }
    }

    private func releaseWriter() {
        if let summary = writer?.finish() {
            result.firstHostTime = summary.firstHostTime
            result.frameCount = AVAudioFramePosition(summary.framesWritten)
        }
        writer = nil
        scratch?.deallocate()
        scratch = nil
    }

    /// Drop the I/O unit so an idle Sidetone does not keep an AirPods HAL aggregate.
    private func tearDownEngine() {
        if let token = configObserver {
            NotificationCenter.default.removeObserver(token)
            configObserver = nil
        }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
            engine.reset()
        }
        engine = nil
    }
}
