import SwiftUI

enum MonitorLayout {
    static let expandedWidth: CGFloat = 240
    static let collapsedWidth: CGFloat = 28
    static let height: CGFloat = 700
}

enum MonitorTheme {
    static let background = Color(red: 0.065, green: 0.078, blue: 0.092)
    static let surface = Color(red: 0.105, green: 0.122, blue: 0.139)
    static let inset = Color(red: 0.038, green: 0.049, blue: 0.059)
    static let text = Color(red: 0.93, green: 0.95, blue: 0.96)
    static let secondary = Color(red: 0.61, green: 0.66, blue: 0.70)
    static let accent = Color(red: 0.39, green: 0.87, blue: 0.84)
    static let live = Color(red: 0.57, green: 0.88, blue: 0.53)
    static let amber = Color(red: 0.97, green: 0.73, blue: 0.36)
    static let red = Color(red: 1.0, green: 0.43, blue: 0.40)
    static let border = Color.white.opacity(0.09)

    static func label(_ size: CGFloat = 9) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

struct MonitorButtonStyle: ButtonStyle {
    var prominent = false
    var dimWhenDisabled = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(!isEnabled && dimWhenDisabled ? 0.4 : (configuration.isPressed ? 0.72 : 1))
            .scaleEffect(configuration.isPressed && prominent ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
