import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: AudioMonitor

    var body: some View {
        ZStack {
            RackBackground()
            VStack(spacing: 0) {
                topRail
                Divider().overlay(Color.white.opacity(0.12))
                inputStrip
                    .padding(.horizontal, 18).padding(.vertical, 20)
                Divider().overlay(Color.white.opacity(0.1))
                levelSection
                    .padding(.horizontal, 18).padding(.vertical, 17)
                Spacer(minLength: 0)
                routingReadout
                Divider().overlay(Color.black.opacity(0.55))
                bottomRail
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .padding(.top, 16)
        }
        .frame(width: 210, height: 700)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { ConsoleRailScrews().allowsHitTesting(false) }
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1) }
        .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
        .task { monitor.refreshDevices() }
        .alert("Audio unavailable", isPresented: $monitor.showError) { Button("OK", role: .cancel) { } } message: { Text(monitor.errorMessage) }
    }

    private var topRail: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SIMPLE MONITOR").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1.2).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(.white.opacity(0.94))
                Text("LOW LATENCY MONITOR").font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(0.7).lineLimit(1).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            HStack(spacing: 7) {
                StatusLight(isOn: monitor.isMonitoring, label: "SIG")
                StatusLight(isOn: true, label: "PWR", color: .orange)
            }
        }
        .padding(.horizontal, 14).frame(height: 51)
    }

    private var inputStrip: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionLabel("INPUT SOURCE")
            VStack(alignment: .leading, spacing: 8) {
                controlLabel("DEVICE")
                HStack(spacing: 7) {
                    Picker("Input device", selection: $monitor.selectedDeviceID) {
                        ForEach(monitor.devices) { device in Text(device.name).tag(device.id) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(.white.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: monitor.selectedDeviceID) { _, _ in monitor.selectDevice() }

                    Button {
                        monitor.refreshDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.cyan.opacity(0.95))
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 5))
                            .overlay { RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.16), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .help("Refresh audio input devices")
                }
                .padding(.horizontal, 10).padding(.vertical, 7).background(insetMetal, in: RoundedRectangle(cornerRadius: 5))
                Text(monitor.selectedDeviceName)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white.opacity(0.42))
                    .help(monitor.selectedDeviceName)
            }
            VStack(alignment: .leading, spacing: 9) {
                controlLabel("INPUT MODE")
                HStack(spacing: 8) {
                    modeIconButton(icon: "1.circle", label: "Mono", selected: !monitor.linkedStereo) { monitor.linkedStereo = false; monitor.applyChannelConfiguration() }
                    modeIconButton(icon: "rectangle.split.2x1", label: "Stereo", selected: monitor.linkedStereo, disabled: !monitor.canLinkStereo) { monitor.linkedStereo = true; monitor.applyChannelConfiguration() }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                controlLabel("CHANNEL SELECT")
                if monitor.availableChannels.isEmpty {
                    Text("NO INPUT DETECTED").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(monitor.availableChannels, id: \.self) { channel in channelButton(channel) } }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var levelSection: some View {
        VStack(spacing: 9) {
            sectionLabel("MONITOR LEVEL")
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 8) {
                    LEDLevelMeter(level: monitor.leftOutputLevel, channel: "L")
                    LEDLevelMeter(level: monitor.rightOutputLevel, channel: "R")
                }
                .frame(height: 175)
                MixerFader(value: $monitor.volume)
                    .frame(width: 96, height: 175)
                    .onChange(of: monitor.volume) { _, _ in monitor.applyVolume() }
            }
            Button { monitor.toggleMonitoring() } label: {
                HStack(spacing: 8) {
                    Image(systemName: monitor.isMonitoring ? "stop.fill" : "power")
                        .font(.system(size: 10, weight: .black))
                        .frame(width: 12)
                    Text(monitor.isMonitoring ? "STOP MONITOR" : "ENABLE MONITOR").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.8)
                }
                .foregroundStyle(.white.opacity(0.93)).frame(maxWidth: .infinity).frame(height: 37)
                .background(monitor.isMonitoring ? Color.red.opacity(0.38) : Color.green.opacity(0.28), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.2), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }.frame(maxWidth: .infinity)
    }

    private var routingReadout: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.cyan.opacity(0.82))
            Text("DIRECT INPUT MONITORING")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(monitor.linkedStereo ? "L/R" : "MONO")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.82))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var bottomRail: some View {
        HStack {
            Text(monitor.linkedStereo ? "CH \(monitor.selectedChannel)+\(monitor.selectedChannel + 1)  •  ST" : "CH \(monitor.selectedChannel)  •  M")
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.8).foregroundStyle(.cyan.opacity(0.9))
            Spacer()
            Text(monitor.isMonitoring ? "● LIVE" : "○ STD").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(monitor.isMonitoring ? .green : .white.opacity(0.38))
        }.padding(.horizontal, 17).frame(height: 44)
    }

    private var insetMetal: LinearGradient { LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom) }
    private func sectionLabel(_ title: String) -> some View { Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(.cyan.opacity(0.9)) }
    private func controlLabel(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(.white.opacity(0.45)) }
    private func modeIconButton(icon: String, label: String, selected: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(label.uppercased()).font(.system(size: 6, weight: .black, design: .monospaced)).tracking(0.3)
            }
            .foregroundStyle(selected ? .black : .white.opacity(disabled ? 0.22 : 0.66))
                .frame(width: 48, height: 38).background(selected ? Color.cyan.opacity(0.92) : Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(selected ? .cyan.opacity(0.8) : .white.opacity(0.13), lineWidth: 1) }
        }.buttonStyle(.plain).disabled(disabled).help(label)
    }
    private func channelButton(_ channel: Int) -> some View {
        let selected = monitor.selectedChannel == channel
        return Button { monitor.selectedChannel = channel; monitor.applyChannelConfiguration() } label: {
            Text("\(channel)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(selected ? .black : .white.opacity(0.68))
                .frame(width: 30, height: 28).background(selected ? Color.cyan : Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(selected ? 0.25 : 0.12), lineWidth: 1) }
        }.buttonStyle(.plain).disabled(monitor.linkedStereo)
    }
}

private struct RackBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.20), Color(red: 0.055, green: 0.065, blue: 0.075)], startPoint: .top, endPoint: .bottom)
            .overlay { LinearGradient(colors: [.white.opacity(0.13), .clear, .black.opacity(0.42)], startPoint: .top, endPoint: .bottom) }
    }
}
private struct ConsoleRailScrews: View {
    var body: some View {
        GeometryReader { proxy in
            let rightEdge = proxy.size.width - 10
            // Centre the lower screw pair on the enable button.
            let lowerRail = proxy.size.height - 102
            ZStack {
                ConsoleScrew(angle: -32).position(x: 10, y: 74)
                ConsoleScrew(angle: 32).position(x: rightEdge, y: 74)
                ConsoleScrew(angle: 32, emphasized: true).position(x: 10, y: lowerRail)
                ConsoleScrew(angle: -32, emphasized: true).position(x: rightEdge, y: lowerRail)
            }
        }
    }
}

private struct ConsoleScrew: View {
    let angle: Double
    var emphasized = false

    var body: some View {
        ZStack {
            if emphasized {
                Circle().fill(.white.opacity(0.16)).frame(width: 17, height: 17)
            }
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(emphasized ? 0.62 : 0.34), .gray.opacity(emphasized ? 0.8 : 0.55), .black.opacity(0.92)], center: .topLeading, startRadius: 1, endRadius: 8))
            Circle().stroke(emphasized ? .white.opacity(0.4) : .black.opacity(0.85), lineWidth: 1.5)
            Capsule()
                .fill(.black.opacity(0.85))
                .frame(width: 10, height: 2.2)
                .rotationEffect(.degrees(angle))
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: 7, height: 0.7)
                .rotationEffect(.degrees(angle - 1))
        }
        .frame(width: 15, height: 15)
        .shadow(color: .black.opacity(0.85), radius: 1.5, y: 1)
    }
}
private struct StatusLight: View {
    let isOn: Bool; let label: String; var color: Color = .green
    var body: some View { VStack(spacing: 3) { Circle().fill(isOn ? color : .black.opacity(0.7)).shadow(color: isOn ? color.opacity(0.9) : .clear, radius: 5).frame(width: 7, height: 7); Text(label).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.38)) } }
}
private struct LEDLevelMeter: View {
    let level: Float
    let channel: String

    private let segments = 12

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 2) {
                ForEach((0..<segments).reversed(), id: \.self) { index in
                    let threshold = Float(index + 1) / Float(segments)
                    let isLit = level >= threshold * 0.68
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(segmentColor(index, isLit: isLit))
                        .frame(width: 20, height: 8)
                        .shadow(color: isLit ? segmentBaseColor(index).opacity(0.8) : .clear, radius: 4)
                }
            }
            Text(channel).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.72))
        }
        .accessibilityLabel("\(channel) output level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private func segmentBaseColor(_ index: Int) -> Color {
        index >= 10 ? .red : (index >= 8 ? .orange : .green)
    }

    private func segmentColor(_ index: Int, isLit: Bool) -> Color {
        isLit ? segmentBaseColor(index) : segmentBaseColor(index).opacity(0.24)
    }
}
private struct MixerFader: View {
    @Binding var value: Float
    @State private var startValue: Float?

    private let trackHeight: CGFloat = 126
    private var handleOffset: CGFloat { (0.5 - CGFloat(value)) * trackHeight }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [.black.opacity(0.64), .white.opacity(0.06)], startPoint: .leading, endPoint: .trailing))
                .overlay { RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.14), lineWidth: 1) }
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        Rectangle().fill(.white.opacity(index == 3 ? 0.52 : 0.25)).frame(width: index == 3 ? 12 : 7, height: 1)
                    }
                }
                ZStack {
                    Capsule().fill(.black.opacity(0.88)).frame(width: 10, height: trackHeight + 9)
                    Capsule().fill(LinearGradient(colors: [.cyan.opacity(0.8), .cyan.opacity(0.08)], startPoint: .bottom, endPoint: .top)).frame(width: 3, height: max(3, CGFloat(value) * trackHeight)).offset(y: (trackHeight - max(3, CGFloat(value) * trackHeight)) / 2)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.white.opacity(0.88), .cyan.opacity(0.70), .white.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 44, height: 17)
                        .overlay { RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.58), lineWidth: 1) }
                        .shadow(color: .cyan.opacity(0.45), radius: 4)
                        .offset(y: handleOffset)
                }
                VStack(spacing: 8) {
                    Text("+6"); Text("0"); Text("−6"); Text("−∞")
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.vertical, 12)
            .offset(y: -10)
            VStack(spacing: 1) {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.94))
                Text("OUTPUT").font(.system(size: 6, weight: .bold, design: .monospaced)).tracking(0.7).foregroundStyle(.white.opacity(0.45))
            }
            .offset(y: 75)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
            if startValue == nil { startValue = value }
            value = min(1, max(0, (startValue ?? value) + Float(-gesture.translation.height / trackHeight)))
        }.onEnded { _ in startValue = nil })
        .accessibilityLabel("Monitor output level")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in value = min(1, max(0, value + (direction == .increment ? 0.05 : -0.05))) }
    }
}
private struct AnalogVUMeter: View {
    let level: Float
    let channel: String

    private var needleAngle: Double { -47 + Double(level) * 94 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(red: 0.90, green: 0.83, blue: 0.60), Color(red: 0.67, green: 0.60, blue: 0.42)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.7), lineWidth: 4)
            VStack(spacing: 1) {
                Text("VU  \(channel)").font(.system(size: 10, weight: .black, design: .serif)).foregroundStyle(.black.opacity(0.78))
                Text("OUTPUT").font(.system(size: 6, weight: .bold, design: .monospaced)).tracking(0.7).foregroundStyle(.black.opacity(0.62))
            }.offset(y: 15)
            meterScale
            Rectangle().fill(.red.opacity(0.85)).frame(width: 2, height: 47).offset(y: -10).rotationEffect(.degrees(needleAngle), anchor: .bottom)
            Circle().fill(.black).frame(width: 9, height: 9).offset(y: 14)
        }
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        .accessibilityLabel("Monitor level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private var meterScale: some View {
        HStack(spacing: 0) {
            ForEach(0..<13, id: \.self) { index in
                VStack(spacing: 2) {
                    Rectangle().fill(index > 9 ? Color.red.opacity(0.8) : .black.opacity(0.72))
                        .frame(width: index.isMultiple(of: 2) ? 1 : 0.5, height: index.isMultiple(of: 2) ? 7 : 4)
                    if [0, 3, 6, 9, 12].contains(index) {
                        Text(index == 12 ? "+3" : "\(index - 9)")
                            .font(.system(size: 5, weight: .bold, design: .monospaced)).foregroundStyle(.black.opacity(0.74))
                    } else { Text(" ").font(.system(size: 5)) }
                }
                .frame(width: 7)
            }
        }
        .offset(y: -15)
    }
}
private struct Knob: View {
    @Binding var value: Float
    @State private var startValue: Float?
    private var angle: Double { -135 + Double(value) * 270 }
    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.68)).padding(7)
            Circle().stroke(AngularGradient(colors: [.cyan.opacity(0.85), .cyan.opacity(0.12), .white.opacity(0.2), .cyan.opacity(0.85)], center: .center), lineWidth: 5).rotationEffect(.degrees(-135)).mask(Circle().trim(from: 0, to: 0.75).stroke(lineWidth: 5)).padding(4)
            Circle().fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay { Circle().stroke(.white.opacity(0.24), lineWidth: 1) }.padding(18)
            Capsule().fill(Color.cyan.opacity(0.95)).frame(width: 4, height: 23).offset(y: -52).rotationEffect(.degrees(angle)).shadow(color: .cyan.opacity(0.8), radius: 3)
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in if startValue == nil { startValue = value }; value = min(1, max(0, (startValue ?? value) + Float(-gesture.translation.height / 150))) }.onEnded { _ in startValue = nil })
        .accessibilityAdjustableAction { direction in value = min(1, max(0, value + (direction == .increment ? 0.05 : -0.05))) }
    }
}
