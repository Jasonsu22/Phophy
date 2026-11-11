import SwiftUI

struct SettingsView: View {
    @Environment(IndexStatus.self) private var indexStatus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppSettings.Key.useAppleIntelligence) private var useAppleIntelligence = true
    @AppStorage(AppSettings.Key.allowCloudAI) private var allowCloudAI = true
    @AppStorage(AppSettings.Key.indexICloudPhotos) private var indexICloudPhotos = true
    @AppStorage(AppSettings.Key.lookUpPlaces) private var lookUpPlaces = true
    @AppStorage(AppSettings.Key.cloudProvider) private var providerID = CloudProvider.anthropic.rawValue
    @AppStorage(AppSettings.Key.customBaseURL) private var customBaseURL = ""

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
                    indexSection
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationBackground(.clear)
        .onAppear(perform: loadProviderFields)
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
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
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
