import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: AudioMonitor
    @Binding var isCollapsed: Bool
    @State private var showsDevicePicker = false

    private var hasInput: Bool { !monitor.availableChannels.isEmpty }
    private var channelSummary: String {
        guard hasInput else { return "No input" }
        return monitor.linkedStereo ? "CH \(monitor.selectedChannel)–\(monitor.selectedChannel + 1)" : "CH \(monitor.selectedChannel)"
    }

    var body: some View {
        Group {
            if isCollapsed { compactPanel } else { expandedPanel }
        }
        .frame(width: isCollapsed ? MonitorLayout.collapsedWidth : MonitorLayout.expandedWidth, height: MonitorLayout.height)
        .background(MonitorTheme.background)
        .preferredColorScheme(.dark)
        .tint(MonitorTheme.accent)
        .task { monitor.refreshDevices() }
        .onChange(of: monitor.selectedDeviceID) { _, _ in monitor.selectDevice() }
        .onChange(of: monitor.volume) { _, _ in monitor.applyVolume() }
        .onChange(of: isCollapsed) { _, _ in showsDevicePicker = false }
        .alert("Audio unavailable", isPresented: $monitor.showError) {
            Button("OK", role: .cancel) { }
        } message: { Text(monitor.errorMessage) }
    }

    private var expandedPanel: some View {
        HStack(spacing: 0) {
            ZStack {
                MonitorTheme.inset.opacity(0.45)
                DockHandle(isCollapsed: false) { isCollapsed = true }
            }
            .frame(width: 18)
            .overlay(alignment: .trailing) { Rectangle().fill(MonitorTheme.border).frame(width: 1) }
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 20)
                inputSection
                Rectangle().fill(MonitorTheme.border).frame(height: 1).padding(.vertical, 18)
                outputSection
                Spacer(minLength: 16)
                monitoringButton
                footer.padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)
        }
        .background(LinearGradient(colors: [MonitorTheme.surface.opacity(0.55), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("SIMPLE AUDIO")
                    .font(MonitorTheme.label(8)).tracking(2.2).foregroundStyle(MonitorTheme.secondary)
                Text("Monitor")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .tracking(-0.7).foregroundStyle(MonitorTheme.text)
            }
            Spacer(minLength: 6)
            Image(systemName: "waveform")
                .font(.system(size: 21, weight: .light)).foregroundStyle(MonitorTheme.accent)
                .frame(width: 38, height: 38)
                .background(MonitorTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(MonitorTheme.accent.opacity(0.16), lineWidth: 1) }
                .accessibilityHidden(true)
        }
        .frame(height: 48)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(title: "INPUT", number: "01")
                Spacer()
                Button { monitor.refreshDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(MonitorTheme.secondary)
                        .frame(width: 26, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(MonitorButtonStyle())
                .help("Refresh input devices").accessibilityLabel("Refresh input devices")
            }
            .padding(.bottom, 8)
            deviceMenu
            HStack(spacing: 3) {
                modeButton("Mono", icon: "circle", stereo: false)
                modeButton("Stereo", icon: "circle.lefthalf.filled", stereo: true)
            }
            .padding(3)
            .background(MonitorTheme.inset, in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 12)
            HStack {
                Text(monitor.linkedStereo ? "CHANNEL PAIR" : "CHANNEL")
                    .foregroundStyle(MonitorTheme.secondary)
                Spacer()
                Text(monitor.linkedStereo ? "LINKED" : "MONO").foregroundStyle(MonitorTheme.accent)
            }
            .font(MonitorTheme.label(8)).tracking(1)
            .padding(.top, 16).padding(.bottom, 8)
            if hasInput {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 5) {
                        ForEach(monitor.availableChannels, id: \.self) { channel in channelButton(channel) }
                    }
                    .padding(.bottom, 3)
                }
                .frame(height: 34)
            } else {
                Text("Connect a device, then refresh.")
                    .font(.system(size: 10)).foregroundStyle(MonitorTheme.secondary).frame(height: 34)
            }
        }
    }

    private var deviceMenu: some View {
        Button { showsDevicePicker.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker")
                    .font(.system(size: 13)).foregroundStyle(MonitorTheme.accent)
                Text(hasInput ? monitor.selectedDeviceName : "Connect an input")
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .multilineTextAlignment(.leading).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(MonitorTheme.secondary)
            }
            .foregroundStyle(MonitorTheme.text).padding(.horizontal, 11).frame(height: 48)
            .background(MonitorTheme.inset, in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(MonitorTheme.border, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(MonitorButtonStyle())
        .popover(isPresented: $showsDevicePicker, arrowEdge: .leading) { devicePicker }
        .help(monitor.selectedDeviceName)
        .accessibilityLabel("Input device").accessibilityValue(monitor.selectedDeviceName)
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input device").font(.system(size: 13, weight: .semibold))
            if monitor.devices.isEmpty {
                Text("Connect an audio input device, then use Refresh.")
                    .font(.system(size: 12)).foregroundStyle(MonitorTheme.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(monitor.devices) { device in
                            Button {
                                monitor.selectedDeviceID = device.id
                                showsDevicePicker = false
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(device.name).frame(maxWidth: .infinity, alignment: .leading)
                                    if device.id == monitor.selectedDeviceID {
                                        Image(systemName: "checkmark").foregroundStyle(MonitorTheme.accent)
                                    }
                                }
                                .font(.system(size: 12)).multilineTextAlignment(.leading)
                                .foregroundStyle(MonitorTheme.text).padding(10)
                                .background(device.id == monitor.selectedDeviceID ? MonitorTheme.accent.opacity(0.1) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(MonitorButtonStyle())
                            .accessibilityAddTraits(device.id == monitor.selectedDeviceID ? .isSelected : [])
                        }
                    }
                }
                .frame(height: min(260, CGFloat(monitor.devices.count) * 54))
            }
        }
        .padding(16).frame(width: 270).background(MonitorTheme.background)
    }

    private func modeButton(_ title: String, icon: String, stereo: Bool) -> some View {
        let selected = monitor.linkedStereo == stereo
        return Button {
            monitor.linkedStereo = stereo
            monitor.applyChannelConfiguration()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? MonitorTheme.accent : MonitorTheme.secondary)
            .frame(maxWidth: .infinity).frame(height: 28)
            .background(selected ? MonitorTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(selected ? MonitorTheme.border : .clear, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(MonitorButtonStyle()).disabled(stereo && !monitor.canLinkStereo)
        .help(stereo && !monitor.canLinkStereo ? "Stereo requires at least two input channels" : "Monitor in \(title.lowercased())")
        .accessibilityLabel("\(title) input mode").accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func channelButton(_ channel: Int) -> some View {
        let selected = channel == monitor.selectedChannel || (monitor.linkedStereo && channel == monitor.selectedChannel + 1)
        return Button {
            monitor.selectedChannel = channel
            monitor.applyChannelConfiguration()
        } label: {
            Text("\(channel)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(selected ? MonitorTheme.accent : MonitorTheme.secondary)
                .frame(width: 31, height: 29)
                .background(selected ? MonitorTheme.accent.opacity(0.12) : MonitorTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(selected ? MonitorTheme.accent.opacity(0.4) : MonitorTheme.border, lineWidth: 1) }
        }
        .buttonStyle(MonitorButtonStyle(dimWhenDisabled: false))
        .disabled(monitor.linkedStereo)
        .help(monitor.linkedStereo ? "Linked pair. Switch to Mono to select a different starting channel." : "Monitor channel \(channel)")
        .accessibilityLabel("Input channel \(channel)").accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var outputSection: some View {
        VStack(spacing: 12) {
            HStack {
                SectionLabel(title: "MONITOR", number: "02")
                Spacer(minLength: 4)
                Text(monitor.volume, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit().foregroundStyle(MonitorTheme.text).accessibilityLabel("Monitor volume")
            }
            HStack(alignment: .top, spacing: 12) {
                StereoMeters(left: monitor.leftOutputLevel, right: monitor.rightOutputLevel).frame(width: 69)
                Rectangle().fill(MonitorTheme.border).frame(width: 1, height: 164)
                MixerFader(value: $monitor.volume).frame(maxWidth: .infinity)
            }
            .frame(height: 184)
        }
    }

    private var monitoringButton: some View {
        Button { monitor.toggleMonitoring() } label: {
            HStack(spacing: 8) {
                Image(systemName: monitor.isMonitoring ? "stop.fill" : "power").font(.system(size: 12, weight: .semibold))
                Text(monitor.isMonitoring ? "Stop monitor" : "Enable monitor").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(monitor.isMonitoring ? MonitorTheme.red : MonitorTheme.inset)
            .frame(maxWidth: .infinity).frame(height: 43)
            .background(monitor.isMonitoring ? MonitorTheme.red.opacity(0.12) : MonitorTheme.accent, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(monitor.isMonitoring ? MonitorTheme.red.opacity(0.35) : MonitorTheme.accent, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(MonitorButtonStyle(prominent: true)).disabled(!hasInput && !monitor.isMonitoring)
        .help(monitor.isMonitoring ? "Stop routing input audio" : "Route input audio to the output")
    }

    private var footer: some View {
        HStack(spacing: 5) {
            StatusDot(isLive: monitor.isMonitoring)
            Text(monitor.isMonitoring ? "LIVE" : "STANDBY")
                .foregroundStyle(monitor.isMonitoring ? MonitorTheme.live : MonitorTheme.secondary)
            Spacer(minLength: 2)
            Text(channelSummary).foregroundStyle(MonitorTheme.secondary)
        }
        .font(MonitorTheme.label(8)).tracking(0.6).frame(height: 14)
    }

    private var compactPanel: some View {
        VStack(spacing: 0) {
            StatusDot(isLive: monitor.isMonitoring).padding(.top, 22)
            Text(monitor.isMonitoring ? "LIVE" : "IDLE").font(MonitorTheme.label(6))
                .foregroundStyle(monitor.isMonitoring ? MonitorTheme.live : MonitorTheme.secondary).padding(.top, 9)
            Spacer()
            DockHandle(isCollapsed: true) { isCollapsed = false }
            Spacer()
            HStack(alignment: .bottom, spacing: 3) {
                CompactMeter(level: monitor.leftOutputLevel)
                CompactMeter(level: monitor.rightOutputLevel)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Left and right monitor levels")
            .accessibilityValue("\(Int(monitor.leftOutputLevel * 100)), \(Int(monitor.rightOutputLevel * 100)) percent")
            Image(systemName: "waveform").font(.system(size: 11, weight: .medium))
                .foregroundStyle(MonitorTheme.secondary).padding(.top, 14).padding(.bottom, 22)
        }
        .frame(width: MonitorLayout.collapsedWidth, height: MonitorLayout.height)
        .background(LinearGradient(colors: [MonitorTheme.surface, MonitorTheme.background], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .leading) { Rectangle().fill(MonitorTheme.accent.opacity(0.24)).frame(width: 1) }
    }
}

private struct SectionLabel: View {
    let title: String
    let number: String
    var body: some View {
        HStack(spacing: 7) {
            Text(number).foregroundStyle(MonitorTheme.accent.opacity(0.8))
            Text(title).foregroundStyle(MonitorTheme.secondary)
        }
        .font(MonitorTheme.label(9)).tracking(1.1)
        .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityAddTraits(.isHeader)
    }
}

private struct StatusDot: View {
    let isLive: Bool
    var body: some View {
        Circle().fill(isLive ? MonitorTheme.live : MonitorTheme.secondary.opacity(0.5))
            .frame(width: 5, height: 5)
            .shadow(color: isLive ? MonitorTheme.live.opacity(0.4) : .clear, radius: 3)
            .accessibilityHidden(true)
    }
}

private struct DockHandle: View {
    let isCollapsed: Bool
    let action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: isCollapsed ? "chevron.left" : "chevron.right").font(.system(size: 9, weight: .bold))
                VStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(MonitorTheme.secondary.opacity(0.6)).frame(width: 7, height: 2)
                    }
                }
            }
            .foregroundStyle(isHovered ? MonitorTheme.text : MonitorTheme.accent)
            .frame(width: isCollapsed ? 24 : 17, height: 76)
            .background(MonitorTheme.accent.opacity(isHovered ? 0.17 : 0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(MonitorTheme.accent.opacity(isHovered ? 0.45 : 0.15), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(MonitorButtonStyle()).onHover { isHovered = $0 }
        .help(isCollapsed ? "Expand monitor" : "Collapse monitor · audio keeps playing")
        .accessibilityLabel(isCollapsed ? "Expand monitor" : "Collapse monitor")
    }
}

private struct StereoMeters: View {
    let left: Float
    let right: Float
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                LEDLevelMeter(level: left)
                LEDLevelMeter(level: right)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(MonitorTheme.inset, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(MonitorTheme.border, lineWidth: 1) }
            HStack(spacing: 18) { Text("L"); Text("R") }
                .font(MonitorTheme.label(8)).foregroundStyle(MonitorTheme.secondary)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Left and right monitor levels")
        .accessibilityValue("\(Int(left * 100)), \(Int(right * 100)) percent")
    }
}

private struct LEDLevelMeter: View {
    let level: Float
    private let segments = 18
    var body: some View {
        VStack(spacing: 2) {
            ForEach((0..<segments).reversed(), id: \.self) { index in
                // Relative signal indicators; these are not calibrated dBFS meters.
                let lit = level >= Float(index + 1) / Float(segments)
                let color = index >= 16 ? MonitorTheme.red : (index >= 13 ? MonitorTheme.amber : MonitorTheme.accent)
                RoundedRectangle(cornerRadius: 1).fill(color.opacity(lit ? 1 : 0.12))
                    .frame(width: 14, height: 6)
                    .shadow(color: lit ? color.opacity(0.2) : .clear, radius: 2)
            }
        }
    }
}

private struct CompactMeter: View {
    let level: Float
    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(MonitorTheme.accent.opacity(0.08))
            Capsule().fill(MonitorTheme.accent).frame(height: max(0, min(1, CGFloat(level))) * 52)
        }
        .frame(width: 3, height: 52)
    }
}

private struct MixerFader: View {
    @Binding var value: Float
    @State private var startValue: Float?
    @FocusState private var isFocused: Bool
    private let trackHeight: CGFloat = 138

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { index in
                        let y = 12 + CGFloat(index) * trackHeight / 4
                        Path { path in
                            path.move(to: CGPoint(x: 2, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width - 23, y: y))
                        }
                        .stroke(MonitorTheme.secondary.opacity(0.18), lineWidth: 1)
                        Text(["100", "75", "50", "25", "0"][index])
                            .font(MonitorTheme.label(7)).foregroundStyle(MonitorTheme.secondary)
                            .frame(width: 20, alignment: .trailing)
                            .position(x: geometry.size.width - 10, y: y)
                    }
                    Capsule().fill(MonitorTheme.inset).frame(width: 6, height: trackHeight + 8)
                        .position(x: 26, y: 12 + trackHeight / 2)
                    Capsule().fill(MonitorTheme.accent.opacity(0.35))
                        .frame(width: 2, height: CGFloat(value) * trackHeight)
                        .position(x: 26, y: 12 + trackHeight - CGFloat(value) * trackHeight / 2)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [Color(white: 0.79), Color(white: 0.48), Color(white: 0.66)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 42, height: 23)
                        .overlay {
                            VStack(spacing: 3) {
                                Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1)
                                Rectangle().fill(MonitorTheme.inset).frame(height: 2)
                                Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1)
                            }
                            .padding(.horizontal, 5)
                        }
                        .overlay { RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.4), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                        .position(x: 26, y: 12 + (1 - CGFloat(value)) * trackHeight)
                }
            }
            .frame(height: 162).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                if startValue == nil { startValue = value }
                value = min(1, max(0, (startValue ?? value) - Float(gesture.translation.height / trackHeight)))
            }.onEnded { _ in startValue = nil })
            Text("VOLUME").font(MonitorTheme.label(8)).tracking(0.7).foregroundStyle(MonitorTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 7)
        }
        .focusable().focused($isFocused)
        .onKeyPress(.upArrow) { adjust(0.01); return .handled }
        .onKeyPress(.downArrow) { adjust(-0.01); return .handled }
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(isFocused ? MonitorTheme.accent.opacity(0.6) : .clear, lineWidth: 1)
                .padding(-3).allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Monitor volume")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in adjust(direction == .increment ? 0.05 : -0.05) }
        .help("Drag to adjust volume. Arrow keys adjust by 1%.")
    }

    private func adjust(_ amount: Float) { value = min(1, max(0, value + amount)) }
}
