import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: AudioMonitor
    @Binding var isCollapsed: Bool
    @State private var showsDevicePicker = false
    @StateObject private var otherApps = OtherAppsAudio()

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
        .alert("Other apps audio", isPresented: Binding(
            get: { otherApps.errorMessage != nil },
            set: { if !$0 { otherApps.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { otherApps.errorMessage = nil }
        } message: { Text(otherApps.errorMessage ?? "") }
        .alert("Audio unavailable", isPresented: $monitor.showError) {
            Button("OK", role: .cancel) { }
        } message: { Text(monitor.errorMessage) }
    }

    private var expandedPanel: some View {
        HStack(spacing: 0) {
            DockHandle(isCollapsed: false) { isCollapsed = true }
                .frame(width: 18, height: MonitorLayout.height)
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 22)
                inputSection
                outputSection.padding(.top, 24)
                Spacer(minLength: 16)
                footer
            }
            .padding(.leading, 10)
            .padding(.trailing, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(LinearGradient(colors: [MonitorTheme.surface.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(MonitorTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(MonitorTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("SIMPLE AUDIO").font(MonitorTheme.label(8)).tracking(1.6)
                        .foregroundStyle(MonitorTheme.secondary)
                    Text("Monitor").font(.system(size: 24, weight: .semibold))
                        .tracking(-0.7).foregroundStyle(MonitorTheme.text)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                StatusDot(isLive: monitor.isMonitoring)
                Text(monitor.isMonitoring ? "LIVE" : "READY")
                    .font(MonitorTheme.label(9))
            }
            .foregroundStyle(monitor.isMonitoring ? MonitorTheme.accent : MonitorTheme.secondary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(MonitorTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(MonitorTheme.border, lineWidth: 1) }
        }
        .frame(height: 44)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(title: "Audio input")
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
            HStack(spacing: 10) {
                Text(monitor.linkedStereo ? "Linked pair" : "Channel")
                    .font(.system(size: 11)).foregroundStyle(MonitorTheme.secondary)
                Spacer(minLength: 0)
                if hasInput {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(monitor.availableChannels, id: \.self) { channel in channelButton(channel) }
                        }
                    }
                    .frame(maxWidth: 160).frame(height: 29)
                } else {
                    Text("No input connected").font(.system(size: 11)).foregroundStyle(MonitorTheme.secondary)
                }
            }
            .padding(.top, 12)
        }
    }

    private var deviceMenu: some View {
        Button { showsDevicePicker.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 13)).foregroundStyle(MonitorTheme.accent)
                Text(hasInput ? monitor.selectedDeviceName : "Connect an input")
                    .font(.system(size: 13, weight: .medium)).lineLimit(2)
                    .multilineTextAlignment(.leading).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(MonitorTheme.secondary)
            }
            .foregroundStyle(MonitorTheme.text).padding(.horizontal, 11).frame(height: 48)
            .background(MonitorTheme.surface, in: RoundedRectangle(cornerRadius: 9))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "Listening mix")
                Spacer()
                Text("Independent levels").font(.system(size: 10)).foregroundStyle(MonitorTheme.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                volumeStrip(title: "Monitor", subtitle: "Your instrument", icon: "waveform",
                            value: $monitor.volume, color: MonitorTheme.accent,
                            enabled: true, active: monitor.isMonitoring,
                            canToggle: hasInput || monitor.isMonitoring,
                            action: { monitor.toggleMonitoring() })
                volumeStrip(title: "Other apps", subtitle: "Music & playback", icon: "music.note",
                            value: $otherApps.volume, color: MonitorTheme.apps,
                            enabled: otherApps.isEnabled, active: otherApps.isEnabled,
                            canToggle: otherApps.isSupported,
                            action: { otherApps.toggle() })
            }
        }
    }

    private func volumeStrip(title: String, subtitle: String, icon: String, value: Binding<Float>,
                             color: Color, enabled: Bool, active: Bool, canToggle: Bool,
                             action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(MonitorTheme.text)
            }
            Text(subtitle).font(.system(size: 10)).foregroundStyle(MonitorTheme.secondary).padding(.top, 5)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int((value.wrappedValue * 100).rounded()))")
                    .font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 12, weight: .medium)).foregroundStyle(MonitorTheme.secondary)
            }
            .foregroundStyle(enabled ? MonitorTheme.text : MonitorTheme.secondary)
            .padding(.top, 16).padding(.bottom, 14)
            MixerFader(value: value, accessibilityTitle: title + " volume", color: color)
                .disabled(!enabled).opacity(enabled ? 1 : 0.45)
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: active ? "pause.fill" : "power").font(.system(size: 9, weight: .bold))
                    Text(active ? "Enabled" : "Enable").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(active ? color : MonitorTheme.text)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(active ? color.opacity(0.13) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(active ? color.opacity(0.25) : MonitorTheme.border, lineWidth: 1) }
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(MonitorButtonStyle()).disabled(!canToggle)
            .padding(.top, 16)
            .accessibilityLabel((active ? "Disable " : "Enable ") + title.lowercased())
            .accessibilityAddTraits(active ? .isSelected : [])
            .help(!canToggle && title == "Other apps" ? "Requires macOS 14.2 or later" : (active ? "Disable " : "Enable ") + title.lowercased())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [color.opacity(0.055), MonitorTheme.surface], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(active ? color.opacity(0.28) : MonitorTheme.border, lineWidth: 1) }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("SIGNAL").font(MonitorTheme.label(8)).tracking(0.7).foregroundStyle(MonitorTheme.secondary)
                SignalMeter(label: "L", level: monitor.leftOutputLevel)
                SignalMeter(label: "R", level: monitor.rightOutputLevel)
            }
            HStack(spacing: 4) {
                Text(monitor.selectedDeviceName).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                Text(channelSummary)
            }
            .font(.system(size: 10)).foregroundStyle(MonitorTheme.secondary)
        }
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
    var body: some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(MonitorTheme.text)
            .accessibilityAddTraits(.isHeader)
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

private struct SignalMeter: View {
    let label: String
    let level: Float
    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(MonitorTheme.label(8)).foregroundStyle(MonitorTheme.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(MonitorTheme.accent.opacity(0.1))
                    Capsule().fill(level > 0.9 ? MonitorTheme.amber : MonitorTheme.accent)
                        .frame(width: max(0, min(1, CGFloat(level))) * geometry.size.width)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(label + " monitor level")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
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
    var accessibilityTitle = "Monitor volume"
    var color = MonitorTheme.accent
    @State private var startValue: Float?
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    private let trackHeight: CGFloat = 144

    var body: some View {
        GeometryReader { geometry in
            let trackX = (geometry.size.width - 22) / 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<5, id: \.self) { index in
                    let y = 14 + CGFloat(index) * trackHeight / 4
                    Path { path in
                        path.move(to: CGPoint(x: 3, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width - 25, y: y))
                    }
                    .stroke(MonitorTheme.secondary.opacity(0.14), lineWidth: 1)
                    Text(["100", "75", "50", "25", "0"][index])
                        .font(MonitorTheme.label(8)).foregroundStyle(MonitorTheme.secondary)
                        .frame(width: 22, alignment: .trailing)
                        .position(x: geometry.size.width - 10, y: y)
                }
                Capsule().fill(MonitorTheme.inset).frame(width: 8, height: trackHeight + 4)
                    .position(x: trackX, y: 14 + trackHeight / 2)
                Capsule().fill(color.opacity(0.65))
                    .frame(width: 3, height: CGFloat(value) * trackHeight)
                    .position(x: trackX, y: 14 + trackHeight - CGFloat(value) * trackHeight / 2)
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.69)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 27)
                    .overlay {
                        Capsule().fill(color.opacity(0.95)).frame(width: 24, height: 3)
                            .shadow(color: color.opacity(0.35), radius: 3)
                    }
                    .overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.6), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.45), radius: isHovered ? 6 : 3, y: 3)
                    .position(x: trackX, y: 14 + (1 - CGFloat(value)) * trackHeight)
            }
        }
        .frame(height: 172).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
            if startValue == nil { startValue = value }
            value = min(1, max(0, (startValue ?? value) - Float(gesture.translation.height / trackHeight)))
        }.onEnded { _ in startValue = nil })
        .onHover { isHovered = $0 }
        .focusable().focused($isFocused)
        .onKeyPress(.upArrow) { adjust(0.01); return .handled }
        .onKeyPress(.downArrow) { adjust(-0.01); return .handled }
        .overlay {
            RoundedRectangle(cornerRadius: 9).stroke(isFocused ? color.opacity(0.65) : .clear, lineWidth: 1)
                .padding(-4).allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(accessibilityTitle)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in adjust(direction == .increment ? 0.05 : -0.05) }
        .help("Drag to adjust volume. Arrow keys adjust by 1%.")
    }

    private func adjust(_ amount: Float) { value = min(1, max(0, value + amount)) }
}
