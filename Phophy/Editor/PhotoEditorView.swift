import Photos
import SwiftUI

/// Full-screen photo editor. Everything except "AI edit" runs on the iPhone
/// for free; an AI edit only happens after the user confirms it.
struct PhotoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PhotoEditorModel
    @State private var tool: Tool = .describe
    @State private var request = ""
    @State private var pendingAI: String?
    @State private var showingOriginal = false
    @State private var confirmDiscard = false
    @FocusState private var requestFocused: Bool

    private let suggestions = ["Brighter", "Remove the background", "Warmer", "Black and white", "Blur the background", "Enhance"]

    enum Tool: String, CaseIterable, Identifiable {
        case describe, adjust, looks, crop, background
        var id: Self { self }
        var title: String {
            switch self {
            case .describe: "Describe"
            case .adjust: "Adjust"
            case .looks: "Looks"
            case .crop: "Crop"
            case .background: "Subject"
            }
        }
        var symbol: String {
            switch self {
            case .describe: "sparkles"
            case .adjust: "dial.medium"
            case .looks: "camera.filters"
            case .crop: "crop.rotate"
            case .background: "person.crop.rectangle"
            }
        }
    }

    init(asset: PHAsset) {
        _model = State(initialValue: PhotoEditorModel(asset: asset))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
            if let pendingAI {
                aiConfirmation(pendingAI)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            toolPanel
                .frame(height: 150)
                .padding(.top, 10)
            toolPicker
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .tint(Color(hex: 0x8FE3EA))
        .animation(.easeInOut(duration: 0.2), value: model.message)
        .animation(.easeInOut(duration: 0.2), value: pendingAI)
        .task { await model.load() }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                if model.hasChanges { confirmDiscard = true } else { dismiss() }
            }
            .buttonStyle(.glass)

            Spacer()

            Menu {
                Button("Reset Changes", systemImage: "arrow.uturn.backward") { model.resetAll() }
                    .disabled(!model.hasChanges)
                if model.hasSavedEdits {
                    Button("Revert to Original", systemImage: "photo", role: .destructive) {
                        Task { if await model.revertToOriginal() { dismiss() } }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("More")

            Button(model.recipe.background.needsTransparency ? "Save Copy" : "Done") {
                Task {
                    if await model.save() != nil { dismiss() }
                }
            }
            .buttonStyle(.glassProminent)
            .fontWeight(.semibold)
            .disabled(!model.hasChanges || model.isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Picture

    private var canvas: some View {
        ZStack {
            if model.recipe.background.needsTransparency && !showingOriginal {
                Checkerboard().opacity(0.35)
            }
            if let image = showingOriginal ? model.originalPreview : (model.preview ?? model.originalPreview) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(showingOriginal ? "Original photo" : "Edited photo")
            }
            switch model.phase {
            case .loading:
                ProgressView("Opening photo…")
            case let .working(text):
                ProgressView(text)
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            case let .failed(text):
                ContentUnavailableView("Can't edit this photo", systemImage: "exclamationmark.triangle", description: Text(text))
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if showingOriginal {
                Text("ORIGINAL")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                    .padding(12)
            }
        }
        // Press and hold to compare with the original.
        .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 40) {
        } onPressingChanged: { pressing in
            showingOriginal = pressing
        }
        .accessibilityHint("Press and hold to see the original")
    }

    // MARK: Tools

    private var toolPicker: some View {
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(Tool.allCases) { item in
                    Button {
                        tool = item
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.symbol).font(.body)
                            Text(item.title).font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(tool == item ? Color(hex: 0x8FE3EA) : .white.opacity(0.8))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tool == item ? .isSelected : [])
                }
            }
            .padding(5)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .disabled(model.phase == .loading)
    }

    @ViewBuilder
    private var toolPanel: some View {
        Group {
            switch tool {
            case .describe: describePanel
            case .adjust: adjustPanel
            case .looks: looksPanel
            case .crop: cropPanel
            case .background: backgroundPanel
            }
        }
        .disabled(model.isBusy)
    }

    private var describePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Describe an edit, e.g. “brighter and blur the background”", text: $request)
                    .focused($requestFocused)
                    .submitLabel(.go)
                    .onSubmit(runRequest)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .glassEffect(.regular.interactive(), in: .capsule)
                Button(action: runRequest) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Apply")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if model.canUndoGenerated {
                        Button("Undo AI edit", systemImage: "arrow.uturn.backward") { model.undoGenerated() }
                            .buttonStyle(.glass)
                    }
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            request = suggestion
                            runRequest()
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            Text(EditRequestReader.canUseAppleIntelligence
                 ? "Read by Apple Intelligence on this iPhone. Anything it can't do here is offered to your AI image service first."
                 : "Light, colour, crop and background are done on your iPhone. Anything else is offered to your AI image service first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private func runRequest() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        requestFocused = false
        request = ""
        Task {
            let leftover = await model.applyRequest(text)
            pendingAI = leftover.isEmpty ? nil : leftover.joined(separator: ", ")
        }
    }

    private func aiConfirmation(_ instruction: String) -> some View {
        let provider = AppSettings.imageProvider
        return VStack(alignment: .leading, spacing: 10) {
            Text("“\(instruction)” needs an AI image service.")
                .font(.subheadline.weight(.semibold))
            Text(provider == .custom
                 ? "Sends this photo to the image service set in Settings, which may charge per edit. The result comes back at about 1.5 megapixels."
                 : "Sends this photo to \(provider.title). Each edit is billed to your \(provider.title) account, usually a few cents, and comes back at about 1.5 megapixels.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Not now") { pendingAI = nil }
                    .buttonStyle(.glass)
                Spacer()
                Button(provider == .custom ? "Send" : "Edit with \(provider.title)") {
                    pendingAI = nil
                    Task { await model.generate(instruction) }
                }
                .buttonStyle(.glassProminent)
                .fontWeight(.semibold)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var adjustPanel: some View {
        ScrollView {
            VStack(spacing: 10) {
                Toggle(isOn: $model.recipe.autoEnhance) {
                    Label("Auto Enhance", systemImage: "wand.and.stars")
                }
                AdjustSlider(title: "Exposure", symbol: "plusminus.circle", value: $model.recipe.exposure, range: -2...2)
                AdjustSlider(title: "Contrast", symbol: "circle.lefthalf.filled", value: $model.recipe.contrast, range: -1...1)
                AdjustSlider(title: "Saturation", symbol: "drop.halffull", value: $model.recipe.saturation, range: -1...1)
                AdjustSlider(title: "Warmth", symbol: "thermometer.medium", value: $model.recipe.warmth, range: -1...1)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var looksPanel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(EditRecipe.Look.allCases) { look in
                    Button(look.title) { model.recipe.look = look }
                        .buttonStyle(ChipStyle(selected: model.recipe.look == look))
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var cropPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button("Rotate Left", systemImage: "rotate.left") {
                    model.recipe.quarterTurns = (model.recipe.quarterTurns + 3) % 4
                }
                Button("Rotate Right", systemImage: "rotate.right") {
                    model.recipe.quarterTurns = (model.recipe.quarterTurns + 1) % 4
                }
            }
            .buttonStyle(.glass)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(EditRecipe.CropAspect.allCases) { aspect in
                        Button(aspect.title) { model.recipe.aspect = aspect }
                            .buttonStyle(ChipStyle(selected: model.recipe.aspect == aspect))
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var backgroundPanel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(EditRecipe.BackgroundMode.allCases) { mode in
                        Button(mode.title) { model.recipe.background = mode }
                            .buttonStyle(ChipStyle(selected: model.recipe.background == mode))
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            Text(model.recipe.background.needsTransparency
                 ? "A cut-out is saved as a new photo with a see-through background. The original stays as it is."
                 : "Phophy finds the people, pets or objects in the photo on your iPhone and changes what's behind them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private struct AdjustSlider: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .frame(width: 84, alignment: .leading)
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
            Text(value, format: .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        // Double-tap a row to put it back to zero.
        .contentShape(.rect)
        .onTapGesture(count: 2) { value = 0 }
    }
}

private struct ChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .foregroundStyle(selected ? Color(hex: 0x131A44) : .white)
            .background(selected ? Color(hex: 0x8FE3EA) : .white.opacity(0.12), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The grey squares that show where a cut-out is see-through.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 12
            for row in 0..<Int(size.height / side) + 1 {
                for column in 0..<Int(size.width / side) + 1 where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)),
                        with: .color(.white.opacity(0.5))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
