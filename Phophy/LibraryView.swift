import SwiftUI

/// Home screen. Everything shown here is placeholder content until Phase 1
/// connects the real photo library.
struct LibraryView: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                chips
                recents
                DigestCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background { AmbientBackground() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Library")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Button {
            } label: {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Open assistant")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(SampleData.categories) { category in
                        Button {
                        } label: {
                            HStack(spacing: 6) {
                                Text(category.name).fontWeight(.semibold)
                                Text(category.count, format: .number).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recents").font(.title3.bold())
                Spacer()
                Button("See all") {}
                    .font(.subheadline.weight(.semibold))
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(SampleData.photos) { photo in
                    PlaceholderPhoto(photo: photo)
                        .frame(height: 84)
                }
            }
            .clipShape(.rect(cornerRadius: 22))
        }
    }
}

struct DigestCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("DIGEST READY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("Thursday's lecture")
                    .font(.headline)
                Text("14 slides → 1 page")
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Read") {}
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(Color(hex: 0x131A44))
                .fontWeight(.bold)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

#Preview {
    LibraryView()
        .preferredColorScheme(.dark)
}
