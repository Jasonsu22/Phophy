import SwiftUI

/// Deep colour field behind the glass. Later this can sample colours from
/// the photos on screen.
struct AmbientBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: 0x131A44)
                Circle().fill(Color(hex: 0x5A3FD6))
                    .frame(width: 340).position(x: 80, y: 110)
                Circle().fill(Color(hex: 0x0F8F9C))
                    .frame(width: 330).position(x: proxy.size.width, y: proxy.size.height * 0.45)
                Circle().fill(Color(hex: 0xB4366F))
                    .frame(width: 380).position(x: 110, y: proxy.size.height)
            }
            .blur(radius: 70)
            .overlay(Color(hex: 0x0C1030).opacity(0.28))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
