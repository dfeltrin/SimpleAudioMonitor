import AppKit
import CoreAudio
import os

/// Owns only the other-apps route. Never changes hardware volume or the monitor engine.
@MainActor
final class OtherAppsAudio: ObservableObject {
    @Published var volume: Float = UserDefaults.standard.object(forKey: "otherAppsVolume") == nil
        ? 1 : UserDefaults.standard.float(forKey: "otherAppsVolume") {
        didSet {
            let level = volume
            route?.gain.withLock { $0 = level }
            UserDefaults.standard.set(volume, forKey: "otherAppsVolume")
        }
    }
    @Published private(set) var isEnabled = false
    @Published var errorMessage: String?
    var isSupported: Bool { if #available(macOS 14.2, *) { true } else { false } }
    private var route: OtherAppsRoute?
    private var watchdog: Timer?
    private var checksWithoutAudio = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.stop() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } })
    }

    func toggle() {
        if isEnabled { stop(); return }
        guard #available(macOS 14.2, *) else { return }
        do {
            let newRoute = OtherAppsRoute(gain: volume)
            route = newRoute
            try newRoute.start()
            isEnabled = true
            // Also catches unplugged devices, output changes, and denied capture access.
            checksWithoutAudio = 0
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let route = self.route else { return }
                    if !route.outputIsUnchanged() {
                        self.stop()
                        self.errorMessage = "The audio output changed. Other-apps control was disabled; enable it again for the new output."
                    } else if !route.didRender.withLock({ value in
                        let rendered = value
                        value = false
                        return rendered
                    }) {
                        self.checksWithoutAudio += 1
                        if self.checksWithoutAudio >= 15 {
                            self.stop()
                            self.errorMessage = "System audio is unavailable. Allow Simple Audio Monitor in System Settings → Privacy & Security → Screen & System Audio Recording, then enable Other apps again."
                        }
                    } else {
                        self.checksWithoutAudio = 0
                    }
                }
            }
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        route?.stop()
        route = nil
        isEnabled = false
    }
}

/// The hardware output and tap share one clock and IO callback: no queued player buffers.
private final class OtherAppsRoute {
    let gain: OSAllocatedUnfairLock<Float>
    let didRender = OSAllocatedUnfairLock(initialState: false)
    private var tap: AudioObjectID = 0
    private var aggregate: AudioDeviceID = 0
    private var output: AudioDeviceID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var sampleRate: Double = 0

    init(gain: Float) { self.gain = OSAllocatedUnfairLock(initialState: gain) }

    @available(macOS 14.2, *)
    func start() throws {
        output = try Self.read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioDeviceID(0))
        guard output != 0 else { throw failure("No audio output is available.") }
        var uid: CFString = "" as CFString
        uid = try Self.read(output, kAudioDevicePropertyDeviceUID, initial: uid)
        var pid = ProcessInfo.processInfo.processIdentifier
        var process: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process), "identify this app")
        guard process != 0 else { throw failure("Could not exclude the monitor from system audio.") }

        // Device-specific capture preserves its stream layout and avoids stereo mixdown attenuation.
        let description = CATapDescription(excludingProcesses: [process], deviceUID: uid as String, stream: 0)
        description.name = "Simple Audio Monitor — Other apps"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(description, &tap), "create system audio capture")
        let format = try Self.read(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else {
            throw failure("This output's audio format is not supported for other-apps control.")
        }
        sampleRate = format.mSampleRate
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Simple Audio Monitor Other Apps",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                             kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]
        try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "create audio route")
        try validateStreamFormats()
        // Core Audio appends the tap's input buffers after the physical device's inputs.
        let tapChannels = Int(format.mChannelsPerFrame)
        let volume = gain
        let rendered = didRender
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil) { _, input, _, output, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)
            for buffer in outputs {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            var firstTapBuffer = inputs.count
            var channels = 0
            while firstTapBuffer > 0 && channels < tapChannels {
                firstTapBuffer -= 1
                channels += Int(inputs[firstTapBuffer].mNumberChannels)
            }
            guard channels == tapChannels else { return }
            let level = volume.withLock { $0 }
            var sourceChannel = 0
            for index in firstTapBuffer..<inputs.count {
                let source = inputs[index]
                guard let data = source.mData else { continue }
                let sourceChannels = Int(source.mNumberChannels)
                guard sourceChannels > 0 else { continue }
                let frames = Int(source.mDataByteSize) / (MemoryLayout<Float>.size * sourceChannels)
                let samples = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<sourceChannels {
                    var destinationChannel = sourceChannel + channel
                    for destination in outputs {
                        let destinationChannels = Int(destination.mNumberChannels)
                        if destinationChannel >= destinationChannels {
                            destinationChannel -= destinationChannels
                            continue
                        }
                        if let destinationData = destination.mData, destinationChannels > 0 {
                            let count = min(frames, Int(destination.mDataByteSize) / (MemoryLayout<Float>.size * destinationChannels))
                            let target = destinationData.assumingMemoryBound(to: Float.self)
                            for frame in 0..<count {
                                target[frame * destinationChannels + destinationChannel] = samples[frame * sourceChannels + channel] * level
                            }
                        }
                        break
                    }
                }
                sourceChannel += sourceChannels
            }
            rendered.withLock { $0 = true }
        }, "prepare audio playback")
        try check(AudioDeviceStart(aggregate, ioProc), "start system audio playback")
    }

    private func validateStreamFormats() throws {
        for scope in [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            try check(AudioObjectGetPropertyDataSize(aggregate, &address, 0, nil, &size), "inspect route streams")
            var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
            try check(AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, &streams), "read route streams")
            guard !streams.isEmpty else { throw failure("The audio route has no usable streams.") }
            for stream in streams {
                let format = try Self.read(stream, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
                guard format.mFormatID == kAudioFormatLinearPCM,
                      format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                      format.mBitsPerChannel == 32,
                      format.mSampleRate == sampleRate else {
                    throw failure("This output's stream format is not supported for other-apps control.")
                }
            }
        }
    }

    func outputIsUnchanged() -> Bool {
        guard let current = try? Self.read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioDeviceID(0)), current == output,
              let alive = try? Self.read(output, kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)), alive != 0,
              let rate = try? Self.read(output, kAudioDevicePropertyNominalSampleRate, initial: Double(0)) else { return false }
        return rate == sampleRate
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
            self.ioProc = nil
        }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 {
            if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }
            tap = 0
        }
    }

    deinit { stop() }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        var address = address(selector)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return value
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "OtherAppsAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else {
            throw failure("Could not \(action) (Core Audio \(status)). Check the system audio recording permission in System Settings.")
        }
    }
}
