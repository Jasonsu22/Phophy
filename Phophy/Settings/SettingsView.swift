import SwiftUI

struct SettingsView: View {
    @Environment(IndexStatus.self) private var indexStatus
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppSettings.Key.useAppleIntelligence) private var useAppleIntelligence = true
    @AppStorage(AppSettings.Key.allowCloudAI) private var allowCloudAI = true
    @AppStorage(AppSettings.Key.indexICloudPhotos) private var indexICloudPhotos = true
    @AppStorage(AppSettings.Key.lookUpPlaces) private var lookUpPlaces = true
    @AppStorage(AppSettings.Key.cloudProvider) private var providerID = CloudProvider.anthropic.rawValue
    @AppStorage(AppSettings.Key.customBaseURL) private var customBaseURL = ""

    @AppStorage(AppSettings.Key.imageProvider) private var imageProviderID = ImageProvider.openai.rawValue
    @AppStorage(AppSettings.Key.imageBaseURL) private var imageBaseURL = ""
    @State private var imageModelName = ""
    @State private var imageKeyDraft = ""
    @State private var hasImageKey = false

    private var imageProvider: ImageProvider { ImageProvider(rawValue: imageProviderID) ?? .openai }

    @State private var modelName = ""
    @State private var keyDraft = ""
    @State private var hasKey = false

    private var provider: CloudProvider { CloudProvider(rawValue: providerID) ?? .anthropic }

    @State private var appleIntelligence = AppleIntelligenceStatus.current

    private var backend: AIBackend {
        AIBackend.resolve(
            status: appleIntelligence,
            useAppleIntelligence: useAppleIntelligence,
            allowCloud: allowCloudAI
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    CurrentModelCard(backend: backend)
                    aiSection
                    if allowCloudAI { cloudSection }
                    imageSection
                    indexSection
                    DescriptionSettings()
                    aboutSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background { AmbientBackground() }
            .tint(Color(hex: 0x14B8C6))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            // Room for the floating ask bar and the tab bar.
            .contentMargins(.bottom, 80, for: .scrollContent)
        }
        .presentationBackground(.clear)
        .onAppear(perform: loadProviderFields)
        .onAppear(perform: loadImageFields)
        .onChange(of: imageProviderID) { loadImageFields() }
        .onChange(of: imageModelName) {
            UserDefaults.standard.set(imageModelName, forKey: AppSettings.Key.imageModel(imageProvider))
        }
        .onChange(of: providerID) { loadProviderFields() }
        .onChange(of: modelName) {
            UserDefaults.standard.set(modelName, forKey: AppSettings.Key.cloudModel(provider))
        }
        .onChange(of: scenePhase) {
            // The user may have turned Apple Intelligence on in iPhone Settings.
            if scenePhase == .active { appleIntelligence = .current }
        }
    }

    private var aiSection: some View {
        SettingsSection(title: "Assistant and lecture digests", footer: aiFooter) {
            SettingsRow(icon: "apple.intelligence", title: "Apple Intelligence") {
                StatusPill(text: appleIntelligence.shortSummary, isPositive: appleIntelligence.isAvailable)
            }
            RowDivider()
            SettingsRow(
                icon: "cpu",
                title: "Use Apple Intelligence",
                subtitle: appleIntelligence.isAvailable ? "Free, private, works offline" : nil
            ) {
                // Shown off when the phone can't run it, without losing the saved
                // choice in case Apple Intelligence becomes available later.
                Toggle("Use Apple Intelligence", isOn: Binding(
                    get: { appleIntelligence.isAvailable && useAppleIntelligence },
                    set: { useAppleIntelligence = $0 }
                ))
                .labelsHidden()
                .disabled(!appleIntelligence.isAvailable)
            }
            .opacity(appleIntelligence.isAvailable ? 1 : 0.55)
            RowDivider()
            SettingsRow(icon: "cloud.fill", title: "Allow cloud AI", subtitle: "Only the text a request needs") {
                Toggle("Allow cloud AI", isOn: $allowCloudAI)
                    .labelsHidden()
            }
        }
    }

    private var aiFooter: String {
        if appleIntelligence.isAvailable {
            return "With both on, Phophy uses Apple Intelligence first. Turn it off to always use the cloud model, which handles long lectures better."
        }
        if appleIntelligence == .turnedOff {
            return "Turn on Apple Intelligence in iPhone Settings to run the assistant on this iPhone."
        }
        return "This iPhone can't run Apple Intelligence, so the assistant uses the cloud model. Search and sorting still run entirely on your iPhone."
    }

    private var cloudSection: some View {
        SettingsSection(title: "Cloud model", footer: provider.help) {
            SettingsRow(icon: "server.rack", title: "Provider") {
                Picker("Provider", selection: $providerID) {
                    ForEach(CloudProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            RowDivider()
            FieldRow(icon: "cpu", title: "Model") {
                TextField(provider.modelPlaceholder, text: $modelName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if provider == .custom {
                RowDivider()
                FieldRow(icon: "link", title: "Base URL") {
                    TextField("https://api.example.com/v1", text: $customBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            RowDivider()
            if hasKey {
                SettingsRow(icon: "key", title: "API key", subtitle: "Saved in your iPhone's Keychain") {
                    Button("Remove", role: .destructive) {
                        APIKeyStore.delete(for: provider)
                        hasKey = false
                    }
                    .buttonStyle(.glass)
                }
            } else {
                FieldRow(icon: "key", title: "API key") {
                    HStack(spacing: 8) {
                        SecureField(provider.keyPlaceholder, text: $keyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") {
                            let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty, APIKeyStore.save(key, for: provider) else { return }
                            keyDraft = ""
                            hasKey = true
                        }
                        .buttonStyle(.glass)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func loadProviderFields() {
        let saved = UserDefaults.standard.string(forKey: AppSettings.Key.cloudModel(provider)) ?? ""
        modelName = saved.isEmpty ? provider.defaultModel : saved
        keyDraft = ""
        hasKey = APIKeyStore.load(for: provider) != nil
    }

    private var imageSection: some View {
        SettingsSection(
            title: "AI photo edits",
            footer: "Used only when you ask the editor for something your iPhone can't do itself, such as removing a person, and only after you confirm. " + imageProvider.help
        ) {
            SettingsRow(icon: "wand.and.sparkles", title: "Service") {
                Picker("Service", selection: $imageProviderID) {
                    ForEach(ImageProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            RowDivider()
            FieldRow(icon: "cpu", title: "Model") {
                TextField(imageProvider.defaultModel.isEmpty ? "Model name" : imageProvider.defaultModel, text: $imageModelName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if imageProvider == .custom {
                RowDivider()
                FieldRow(icon: "link", title: "Base URL") {
                    TextField("https://api.example.com/v1", text: $imageBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            RowDivider()
            if hasImageKey {
                SettingsRow(icon: "key", title: "API key", subtitle: imageKeySubtitle) {
                    if APIKeyStore.load(account: imageProvider.keyAccount) != nil {
                        Button("Remove", role: .destructive) {
                            APIKeyStore.delete(account: imageProvider.keyAccount)
                            hasImageKey = imageProvider.savedKey != nil
                        }
                        .buttonStyle(.glass)
                    }
                }
            } else {
                FieldRow(icon: "key", title: "API key") {
                    HStack(spacing: 8) {
                        SecureField(imageProvider.keyPlaceholder, text: $imageKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") {
                            let key = imageKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty, APIKeyStore.save(key, account: imageProvider.keyAccount) else { return }
                            imageKeyDraft = ""
                            hasImageKey = true
                        }
                        .buttonStyle(.glass)
                        .disabled(imageKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private var imageKeySubtitle: String {
        APIKeyStore.load(account: imageProvider.keyAccount) == nil
            ? "Using the assistant's OpenAI key"
            : "Saved in your iPhone's Keychain"
    }

    private func loadImageFields() {
        let saved = UserDefaults.standard.string(forKey: AppSettings.Key.imageModel(imageProvider)) ?? ""
        imageModelName = saved.isEmpty ? imageProvider.defaultModel : saved
        imageKeyDraft = ""
        hasImageKey = imageProvider.savedKey != nil
    }

    private var indexSection: some View {
        SettingsSection(
            title: "Photo index",
            footer: "Indexing runs on your iPhone and is free. Photos kept only in iCloud are downloaded briefly to read them, which uses data. Place names let you search by where a photo was taken."
        ) {
            SettingsRow(icon: "photo.stack.fill", title: "Indexed photos") {
                Text("\(indexStatus.indexed, format: .number) of \(indexStatus.total, format: .number)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if indexStatus.total > 0 {
                ProgressView(value: Double(indexStatus.indexed), total: Double(indexStatus.total))
                    .padding(.leading, 56)
                    .padding(.trailing, 16)
                    .padding(.bottom, indexStatus.pause == nil ? 12 : 4)
                    .accessibilityHidden(true)
                if indexStatus.isRunning, let pause = indexStatus.pause {
                    Text(pause.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 56)
                        .padding(.bottom, 12)
                }
            }
            RowDivider()
            SettingsRow(icon: "text.magnifyingglass", title: "Search by description") {
                StatusPill(
                    text: indexStatus.semanticSearchAvailable ? "On" : "Not installed",
                    isPositive: indexStatus.semanticSearchAvailable
                )
            }
            RowDivider()
            SettingsRow(icon: "icloud.and.arrow.down.fill", title: "Index photos stored in iCloud") {
                Toggle("Index photos stored in iCloud", isOn: $indexICloudPhotos)
                    .labelsHidden()
            }
            RowDivider()
            SettingsRow(icon: "mappin.and.ellipse", title: "Look up place names", subtitle: "Sends photo locations, not photos, to Apple Maps") {
                Toggle("Look up place names", isOn: $lookUpPlaces)
                    .labelsHidden()
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            SettingsRow(icon: "info", title: "Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The hero at the top: which model the assistant will use right now.
private struct CurrentModelCard: View {
    let backend: AIBackend

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: backend.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 4) {
                Text("CURRENTLY USING")
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(backend.title)
                    .font(.title3.bold())
                    .contentTransition(.opacity)
                Text(backend.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .animation(.smooth, value: backend)
        .accessibilityElement(children: .combine)
    }
}

/// A titled glass card holding rows, with optional explanatory text below.
private struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            VStack(spacing: 0) { content }
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row: coloured icon tile, title, optional subtitle, trailing control.
private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }
}

/// A row whose control is a text field under its title.
private struct FieldRow<Field: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let field: Field

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                field
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }
}

private struct StatusPill: View {
    let text: String
    let isPositive: Bool

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isPositive ? Color(hex: 0x8FE3EA) : .white.opacity(0.75))
            .background(
                isPositive ? Color(hex: 0x0F8F9C).opacity(0.3) : .white.opacity(0.1),
                in: .capsule
            )
    }
}

private extension AppleIntelligenceStatus {
    var shortSummary: String {
        switch self {
        case .available: "Available"
        case .notSupported: "Not supported"
        case .turnedOff: "Turned off"
        case .preparing: "Downloading"
        case .unavailable: "Unavailable"
        }
    }
}

private extension AIBackend {
    var symbol: String {
        switch self {
        case .appleIntelligence: "apple.intelligence"
        case .cloud: "cloud.fill"
        case .off: "pause.fill"
        }
    }

}

/// Who writes photo descriptions for search, with a clear warning before
/// any photo is uploaded.
private struct DescriptionSettings: View {
    @Environment(DescribeStatus.self) private var status
    @AppStorage(AppSettings.Key.describer) private var choiceID = DescriberChoice.automatic.rawValue
    @AppStorage(AppSettings.Key.downloadableModel) private var modelID = DownloadableModel.smolVLM.rawValue
    @AppStorage(AppSettings.Key.cloudDescriptionsConsented) private var consented = false
    @AppStorage(AppSettings.Key.describeOnlyWhenCharging) private var onlyWhenCharging = false

    @State private var pendingCloud: DescriberChoice?
    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var modelReady = false
    @State private var downloading = false
    @State private var downloadError: String?
    @State private var appleAvailable = false

    private var choice: DescriberChoice { DescriberChoice(rawValue: choiceID) ?? .automatic }
    private var model: DownloadableModel { DownloadableModel(rawValue: modelID) ?? .smolVLM }
    private var keyAccount: String { choice == .gemini ? ImageProvider.gemini.keyAccount : ImageProvider.openai.keyAccount }

    /// "apple" → "Apple Intelligence", "gemini:gemini-2.5-flash-lite" → "Google Gemini".
    static func describerName(_ id: String) -> String {
        switch id {
        case IndexStore.userDescriber: "you"
        case "apple": "Apple Intelligence"
        case "smolVLM": "SmolVLM2 on this iPhone"
        case "fastVLM": "FastVLM on this iPhone"
        case let id where id.hasPrefix("gemini"): "Google Gemini"
        case let id where id.hasPrefix("openai"): "OpenAI"
        default: id
        }
    }

    var body: some View {
        SettingsSection(title: "Photo descriptions", footer: footer) {
            SettingsRow(icon: "text.below.photo", title: "Described photos", subtitle: status.message ?? status.describer.map { "By " + Self.describerName($0) }) {
                Text("\(status.described, format: .number) of \(max(status.toDescribe, status.described), format: .number)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            RowDivider()
            SettingsRow(icon: "sparkles", title: "Who describes") {
                Picker("Who describes", selection: Binding(
                    get: { choiceID },
                    set: { new in
                        let picked = DescriberChoice(rawValue: new) ?? .automatic
                        if picked.isCloud && !consented { pendingCloud = picked } else { choiceID = new }
                    }
                )) {
                    ForEach(DescriberChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if choice == .automatic || choice == .downloaded {
                RowDivider()
                downloadRows
            }
            if choice.isCloud {
                RowDivider()
                keyRow
                RowDivider()
                SettingsRow(icon: "dollarsign.circle", title: "Estimated cost", subtitle: "Billed to your key by the service") {
                    Text(costText).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            RowDivider()
            SettingsRow(icon: "bolt.batteryblock", title: "Only while charging") {
                Toggle("Only while charging", isOn: $onlyWhenCharging).labelsHidden()
            }
            RowDivider()
            SettingsRow(icon: "arrow.clockwise", title: "Describe now") {
                Button(status.isRunning ? "Working…" : "Start") { start() }
                    .buttonStyle(.glass)
                    .disabled(status.isRunning)
            }
        }
        .alert(cloudTitle, isPresented: Binding(get: { pendingCloud != nil }, set: { if !$0 { pendingCloud = nil } })) {
            Button("Upload and describe") {
                consented = true
                if let pendingCloud { choiceID = pendingCloud.rawValue }
                pendingCloud = nil
            }
            Button("Keep photos on my iPhone", role: .cancel) { pendingCloud = nil }
        } message: {
            Text(cloudWarning)
        }
        .task { await refresh() }
        .onChange(of: choiceID) { Task { await refresh(); start() } }
        .onChange(of: modelID) { Task { await refresh() } }
    }

    private var footer: String {
        switch choice {
        case .gemini, .openai:
            return "Privacy: small copies of your photos are uploaded to \(choice == .gemini ? "Google" : "OpenAI") to be described. Their terms apply, and Phophy can't control or delete what they keep. Near-duplicates are described once to save cost."
        case .off:
            return "Without descriptions, search still uses text in photos, labels, concept tags and visual similarity."
        default:
            return "Descriptions are written on your iPhone and never leave it. They let search find details such as \u{201C}red umbrella\u{201D} or \u{201C}girl with a kite\u{201D}, and find a screenshot by what it is, such as \u{201C}train ticket\u{201D}. Near-duplicates are described once, and work pauses while you use the app."
        }
    }

    private var cloudTitle: String {
        "Upload photos to \(pendingCloud == .openai ? "OpenAI" : "Google")?"
    }

    private var cloudWarning: String {
        let service = pendingCloud == .openai ? "OpenAI" : "Google Gemini"
        return "To describe your photos, Phophy will send small copies of them (384 pixels) to \(service), using your own API key. Once uploaded, Phophy can't control how they're stored or used, so there is no privacy guarantee for those photos. Don't use this if your library holds photos you need to keep private. You can switch back to on-device descriptions at any time."
    }

    private var costText: String {
        let remaining = max(0, status.toDescribe - status.described)
        let photos = remaining > 0 ? remaining : 10_000
        let cost = CloudDescriber.estimatedCost(photos: photos, service: choice == .openai ? .openai : .gemini)
        return "≈ \(cost.formatted(.currency(code: "USD").precision(.fractionLength(2)))) / \(photos.formatted()) photos"
    }

    @ViewBuilder private var downloadRows: some View {
        if appleAvailable && choice == .automatic {
            SettingsRow(icon: "apple.intelligence", title: "Apple Intelligence", subtitle: "Built in, nothing to download") {
                StatusPill(text: "In use", isPositive: true)
            }
        } else {
            SettingsRow(icon: "cpu", title: "Model") {
                Picker("Model", selection: $modelID) {
                    ForEach(DownloadableModel.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            RowDivider()
            SettingsRow(icon: "arrow.down.circle", title: modelReady ? "Downloaded" : "Download", subtitle: downloadError ?? model.sizeNote) {
                if modelReady {
                    StatusPill(text: "Ready", isPositive: true)
                } else if downloading {
                    ProgressView()
                } else {
                    Button("Download") { download() }.buttonStyle(.glass)
                }
            }
        }
    }

    @ViewBuilder private var keyRow: some View {
        if hasKey {
            SettingsRow(icon: "key", title: "API key", subtitle: "Saved in your iPhone's Keychain") {
                Button("Remove", role: .destructive) {
                    APIKeyStore.delete(account: keyAccount)
                    hasKey = false
                }
                .buttonStyle(.glass)
            }
        } else {
            FieldRow(icon: "key", title: choice == .gemini ? "Gemini API key" : "OpenAI API key") {
                HStack(spacing: 8) {
                    SecureField(choice == .gemini ? "AIza…" : "sk-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save") {
                        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty, APIKeyStore.save(key, account: keyAccount) else { return }
                        keyDraft = ""
                        hasKey = true
                        start()
                    }
                    .buttonStyle(.glass)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func refresh() async {
        hasKey = choice == .gemini ? CloudDescriber.configured(.gemini) != nil : CloudDescriber.configured(.openai) != nil
        if #available(iOS 27.0, *) {
            appleAvailable = OnDeviceDescriber.apple() != nil
            modelReady = await OnDeviceDescriber.isDownloaded(model)
        }
    }

    private func download() {
        guard #available(iOS 27.0, *) else { downloadError = "Needs iOS 27"; return }
        downloading = true
        downloadError = nil
        let model = model
        Task {
            do {
                try await OnDeviceDescriber.download(model)
                modelReady = true
                start()
            } catch {
                downloadError = error.localizedDescription
            }
            downloading = false
        }
    }

    private func start() {
        let status = status
        Task.detached(priority: .utility) { await DescriptionService.shared.run(status: status) }
    }
}
