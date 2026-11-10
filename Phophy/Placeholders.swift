import SwiftUI

/// Stand-in content so the shell has something to show before the real
/// photo library is connected. Delete when Phase 1 lands.
enum SampleData {
    struct Category: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    struct Photo: Identifiable {
        enum Kind {
            case scene(top: UInt32, middle: UInt32, bottom: UInt32)
            case slide
        }

        let id: Int
        let label: String
        let kind: Kind
    }

    static let categories = [
        Category(name: "Slides", count: 126),
        Category(name: "Receipts", count: 41),
        Category(name: "Screenshots", count: 312),
        Category(name: "Places", count: 58),
    ]

    static let photos: [Photo] = [
        Photo(id: 0, label: "Sunset over hills", kind: .scene(top: 0xF3A65A, middle: 0xC5574A, bottom: 0x3B2A4D)),
        Photo(id: 1, label: "Lecture slide", kind: .slide),
        Photo(id: 2, label: "Green valley", kind: .scene(top: 0x8EC5EE, middle: 0x3F8F6A, bottom: 0x2C5E4A)),
        Photo(id: 3, label: "Desert road", kind: .scene(top: 0xF1C9A8, middle: 0xB9794F, bottom: 0x6D4A3A)),
        Photo(id: 4, label: "Lecture slide", kind: .slide),
        Photo(id: 5, label: "City at night", kind: .scene(top: 0x1D2452, middle: 0x31407F, bottom: 0x0F1430)),
        Photo(id: 6, label: "Autumn field", kind: .scene(top: 0xECE6D8, middle: 0xD94F3B, bottom: 0x7A3B24)),
        Photo(id: 7, label: "Beach", kind: .scene(top: 0xBFE3F2, middle: 0xE9D9B0, bottom: 0x5AA7C4)),
        Photo(id: 8, label: "Cherry blossom", kind: .scene(top: 0xF7D4DC, middle: 0xD98AA5, bottom: 0x6A8F5A)),
        Photo(id: 9, label: "Lecture slide", kind: .slide),
        Photo(id: 10, label: "Wheat at dusk", kind: .scene(top: 0xF6D36B, middle: 0xE98D3A, bottom: 0x7A3B24)),
        Photo(id: 11, label: "Mountain in fog", kind: .scene(top: 0x9FB7D9, middle: 0x6F7F96, bottom: 0x3C4656)),
    ]
}

struct PlaceholderPhoto: View {
    let photo: SampleData.Photo

    var body: some View {
        Group {
            switch photo.kind {
            case let .scene(top, middle, bottom):
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: top), location: 0),
                        .init(color: Color(hex: top), location: 0.52),
                        .init(color: Color(hex: middle), location: 0.52),
                        .init(color: Color(hex: middle), location: 0.74),
                        .init(color: Color(hex: bottom), location: 0.74),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .slide:
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color(hex: 0x2A3270)).frame(width: 44, height: 6)
                    Capsule().fill(Color(hex: 0xC3C9DD)).frame(height: 4)
                    Capsule().fill(Color(hex: 0xC3C9DD)).frame(width: 52, height: 4)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(hex: 0xF4F5F9))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(photo.label)
        .accessibilityAddTraits(.isImage)
    }
}

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
