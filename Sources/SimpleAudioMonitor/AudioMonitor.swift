import AVFoundation
import CoreAudio
import Foundation

struct InputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputChannels: Int
}

@MainActor
final class AudioMonitor: ObservableObject {
    @Published private(set) var devices: [InputDevice] = []
    @Published var selectedDeviceID: AudioDeviceID = 0 {
        didSet { saveSelectedDevice() }
    }
    @Published private(set) var availableChannels: [Int] = []
    @Published var selectedChannel = 1 {
        didSet { defaults.set(selectedChannel, forKey: PreferenceKey.selectedChannel) }
    }
    @Published var linkedStereo = false {
        didSet { defaults.set(linkedStereo, forKey: PreferenceKey.linkedStereo) }
    }
    @Published var volume: Float = 0.8 {
        didSet { defaults.set(volume, forKey: PreferenceKey.volume) }
    }
    @Published private(set) var leftOutputLevel: Float = 0
    @Published private(set) var rightOutputLevel: Float = 0
    @Published private(set) var isMonitoring = false
    @Published var showError = false
    @Published private(set) var errorMessage = ""

    private let engine = AVAudioEngine()
    private let monitorMixer = AVAudioMixerNode()
    private let meterState = MeterState()
    private var meterRefreshTimer: Timer?
    private let defaults = UserDefaults.standard

    init() {
        engine.attach(monitorMixer)
        if defaults.object(forKey: PreferenceKey.volume) != nil {
            volume = defaults.float(forKey: PreferenceKey.volume)
        }
        if defaults.object(forKey: PreferenceKey.selectedChannel) != nil {
            selectedChannel = max(1, defaults.integer(forKey: PreferenceKey.selectedChannel))
        }
        linkedStereo = defaults.bool(forKey: PreferenceKey.linkedStereo)
        meterRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMeter()
            }
        }
    }

    func refreshDevices() {
        devices = Self.inputDevices()
        let savedUID = defaults.string(forKey: PreferenceKey.deviceUID)
        let savedDevice = devices.first(where: { $0.uid == savedUID })
        let currentDevice = devices.first(where: { $0.id == selectedDeviceID })
        selectedDeviceID = savedDevice?.id ?? currentDevice?.id ?? Self.defaultInputDevice() ?? devices.first?.id ?? 0
        updateChannels()
    }

    func selectDevice() {
        let wasRunning = isMonitoring
        stop()
        updateChannels()
        if wasRunning { start() }
    }

    func applyChannelConfiguration() {
        if linkedStereo, selectedChannel >= (availableChannels.last ?? 1) {
            selectedChannel = max(1, (availableChannels.last ?? 2) - 1)
        }
        if isMonitoring {
            stop()
            start()
        }
    }

    func applyVolume() {
        monitorMixer.outputVolume = volume
    }

    func toggleMonitoring() {
        isMonitoring ? stop() : start()
    }

    private func start() {
        guard selectedDeviceID != 0 else {
            report("Connect an audio input device, then try again.")
            return
        }

        do {
            // This selects the hardware input for the app process. The graph below remains
            // intentionally short: input node → monitor mixer → selected output device.
            try setInputDevice(selectedDeviceID)
            let input = engine.inputNode
            try applyInputChannelMap(to: input)
            let hardwareFormat = input.inputFormat(forBus: 0)
            guard hardwareFormat.channelCount > 0 else {
                report("The selected device does not expose an input stream.")
                return
            }

            let outputChannels: AVAudioChannelCount = linkedStereo ? 2 : 1
            let monitorFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hardwareFormat.sampleRate,
                channels: outputChannels,
                interleaved: false
            )!

            engine.disconnectNodeOutput(input)
            engine.disconnectNodeInput(monitorMixer)
            engine.disconnectNodeOutput(monitorMixer)

            // AVAudioEngine's input node follows the chosen device. A connection to a
            // mono/stereo mixer establishes the channel layout; the device's native input
            // is used so Core Audio does not add a sample-rate conversion stage.
            engine.connect(input, to: monitorMixer, format: monitorFormat)
            engine.connect(monitorMixer, to: engine.outputNode, format: nil)
            monitorMixer.outputVolume = volume
            installLevelMeter(from: input)
            try engine.start()
            isMonitoring = true
        } catch {
            stop()
            report("Could not start monitoring: \(error.localizedDescription)")
        }
    }

    private func stop() {
        monitorMixer.removeTap(onBus: 0)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isMonitoring = false
        leftOutputLevel = 0
        rightOutputLevel = 0
        meterState.store(left: 0, right: 0)
    }

    private func installLevelMeter(from input: AVAudioInputNode) {
        // Tapping the input node keeps the mixer → output route completely untouched.
        // The displayed level is scaled with the monitor level below.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: nil, block: Self.makeMeterTap(state: meterState))
    }

    private func refreshMeter() {
        let measuredLevel = meterState.load()
        // Fast attack, slower release: a familiar analog meter response.
        leftOutputLevel = max(measuredLevel.left * volume, leftOutputLevel * 0.82)
        rightOutputLevel = max(measuredLevel.right * volume, rightOutputLevel * 0.82)
    }

    nonisolated private static func makeMeterTap(state: MeterState) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            func rms(_ channel: Int) -> Float {
                let samples = UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength))
                let meanSquare = samples.reduce(Float.zero) { $0 + ($1 * $1) } / Float(samples.count)
                return min(1, sqrt(meanSquare) * 2.2)
            }
            let left = rms(0)
            let right = buffer.format.channelCount > 1 ? rms(1) : left
            state.store(left: left, right: right)
        }
    }

    private func updateChannels() {
        let channelCount = devices.first(where: { $0.id == selectedDeviceID })?.inputChannels ?? 0
        availableChannels = Array(1...max(0, channelCount))
        if !availableChannels.contains(selectedChannel) {
            selectedChannel = availableChannels.first ?? 1
        }
        if channelCount < 2 { linkedStereo = false }
    }

    var canLinkStereo: Bool { availableChannels.count >= 2 }
    var selectedDeviceName: String {
        devices.first(where: { $0.id == selectedDeviceID })?.name ?? "No device selected"
    }

    private func report(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func saveSelectedDevice() {
        guard let device = devices.first(where: { $0.id == selectedDeviceID }) else { return }
        defaults.set(device.uid, forKey: PreferenceKey.deviceUID)
    }
}

private enum PreferenceKey {
    static let deviceUID = "preferredInputDeviceUID"
    static let linkedStereo = "linkedStereo"
    static let selectedChannel = "selectedChannel"
    static let volume = "monitorVolume"
}

private final class MeterState: @unchecked Sendable {
    private let lock = NSLock()
    private var left: Float = 0
    private var right: Float = 0

    func store(left: Float, right: Float) {
        lock.lock()
        self.left = left
        self.right = right
        lock.unlock()
    }

    func load() -> (left: Float, right: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (left, right)
    }
}

private extension AudioMonitor {
    static func defaultInputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    static func inputDevices() -> [InputDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let channels = inputChannelCount(id)
            let transportType = deviceTransportType(id)
            // Aggregate and virtual devices are often routing helpers (for example
            // loopback drivers), not an instrument input the user wants to monitor.
            guard channels > 0,
                  transportType != kAudioDeviceTransportTypeAggregate,
                  transportType != kAudioDeviceTransportTypeVirtual else { return nil }
            return InputDevice(id: id, uid: deviceUID(id), name: deviceName(id), inputChannels: channels)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList) == noErr else { return 0 }
        let list = bufferList.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func deviceTransportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transportType)
        return status == noErr ? transportType : 0
    }

    static func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (name?.takeUnretainedValue() as String? ?? "Audio Input") : "Audio Input"
    }

    static func deviceUID(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (uid?.takeUnretainedValue() as String? ?? "device-\(id)") : "device-\(id)"
    }

    func setInputDevice(_ id: AudioDeviceID) throws {
        var mutableID = id
        let status = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Core Audio error \(status)"])
        }
    }

    func applyInputChannelMap(to input: AVAudioInputNode) throws {
        // The AUHAL input node exposes captured channels on output scope / element 1.
        // A channel map keeps channel selection in Core Audio, before the monitor graph,
        // rather than adding an app-level buffer/copy in the render callback.
        let count = linkedStereo ? 2 : 1
        var map: [Int32] = linkedStereo
            ? [Int32(selectedChannel - 1), Int32(selectedChannel)]
            : [Int32(selectedChannel - 1)]
        let status = AudioUnitSetProperty(
            input.audioUnit!,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Output,
            1,
            &map,
            UInt32(count * MemoryLayout<Int32>.size)
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not select the requested input channel (Core Audio error \(status))."])
        }
    }
}
