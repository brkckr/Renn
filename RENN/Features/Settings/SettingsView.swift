import SwiftUI
import UIKit
import RENNDomain
import RENNFeatures

/// App-wide settings (02 D09). No video settings, Look/Beat/indicator controls or name form.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let configuration: AppConfiguration
    let effectiveLocalization: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        // The stack only hosts the Licenses subpage; the tab root shows no navigation bar.
        NavigationStack {
            settingsContent
                .toolbar(.hidden, for: .navigationBar)
                .background(RENNColor.backgroundBase.ignoresSafeArea())
        }
        .task { await viewModel.observe() }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("settings.title")
                    .font(RENNFont.heading)
                    .foregroundStyle(RENNColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)

                proCard
                languageSection
                purchasesSection
                privacySection
                storageSection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Sections

    private var proCard: some View {
        Button {
            viewModel.showPaywall()
        } label: {
            HStack(spacing: 12) {
                RENNIcon.crown.image
                    .font(.system(size: 24))
                    .foregroundStyle(RENNColor.brandYellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.pro.title")
                        .font(RENNFont.bodyMedium)
                        .foregroundStyle(RENNColor.textPrimary)
                    Text(viewModel.isPro ? LocalizedStringKey("settings.pro.active") : LocalizedStringKey("settings.pro.pitch"))
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.textSecondary)
                    if viewModel.access.provenance == .providerNotConfigured {
                        Text("settings.pro.notConfigured")
                            .font(RENNFont.secondary)
                            .foregroundStyle(RENNColor.brandAmber)
                    }
                }
                Spacer(minLength: 0)
                if !viewModel.isPro {
                    RENNIcon.chevronRight.image
                        .foregroundStyle(RENNColor.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: RENNMetrics.cardRadius, style: .continuous)
                    .strokeBorder(RENNColor.brandYellow.opacity(0.6), lineWidth: 1))
            .glassBackground(cornerRadius: RENNMetrics.cardRadius)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPro)
    }

    private var languageSection: some View {
        SettingsGroup(title: "settings.language") {
            Picker(
                selection: Binding(get: { viewModel.language }, set: { viewModel.setLanguage($0) })
            ) {
                Text("settings.language.system").tag(AppLanguage.system)
                Text(verbatim: "Türkçe").tag(AppLanguage.turkish)
                Text(verbatim: "English").tag(AppLanguage.english)
            } label: {
                Text("settings.language")
            }
            .pickerStyle(.segmented)
            Text("settings.language.footer")
                .font(RENNFont.secondary)
                .foregroundStyle(RENNColor.textSecondary)
        }
    }

    private var purchasesSection: some View {
        SettingsGroup(title: "settings.purchases") {
            Button {
                Task { await viewModel.restorePurchases() }
            } label: {
                HStack {
                    Text("settings.restore")
                    Spacer()
                    if viewModel.restoreState == .restoring { ProgressView() }
                }
            }
            .buttonStyle(SettingsRowButtonStyle())
            .disabled(viewModel.restoreState == .restoring)
            if let message = restoreMessage {
                Text(message)
                    .font(RENNFont.secondary)
                    .foregroundStyle(RENNColor.textSecondary)
            }
        }
    }

    private var privacySection: some View {
        SettingsGroup(title: "settings.privacy") {
            Toggle(isOn: Binding(
                get: { viewModel.diagnosticsConsent.allowsCollection },
                set: { viewModel.setDiagnosticsEnabled($0) })
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.diagnostics")
                        .font(RENNFont.body)
                        .foregroundStyle(RENNColor.textPrimary)
                    Text("settings.diagnostics.footer")
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.textSecondary)
                }
            }
            .tint(RENNColor.brandYellow)
            Button("settings.permissions") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(SettingsRowButtonStyle())
        }
    }

    /// Storage/cache controls (02 D09): usage, clear regenerable cache, where projects live.
    private var storageSection: some View {
        SettingsGroup(title: "settings.storage") {
            storageRow("settings.storage.projects", bytes: viewModel.storage?.projectBytes)
            storageRow("settings.storage.cache", bytes: viewModel.storage?.cacheBytes)
            Button("settings.storage.clearCache") {
                Task { await viewModel.clearCache() }
            }
            .accessibilityIdentifier("settings.storage.clearCache")
            .buttonStyle(SettingsRowButtonStyle())
            .disabled(viewModel.isClearingCache || (viewModel.storage?.cacheBytes ?? 0) == 0)
            Text("settings.storage.cacheFooter")
                .font(RENNFont.secondary)
                .foregroundStyle(RENNColor.textSecondary)
            Text("settings.storage.footer")
                .font(RENNFont.secondary)
                .foregroundStyle(RENNColor.textSecondary)
        }
        .task { await viewModel.refreshStorage() }
    }

    private func storageRow(_ title: LocalizedStringKey, bytes: Int64?) -> some View {
        HStack {
            Text(title)
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textPrimary)
            Spacer()
            if let bytes {
                Text(bytes, format: .byteCount(style: .file))
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                    .monospacedDigit()
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var aboutSection: some View {
        SettingsGroup(title: "settings.about") {
            linkRow("settings.support", url: configuration.supportURL)
            linkRow("settings.privacyPolicy", url: configuration.privacyURL)
            linkRow("settings.terms", url: configuration.termsURL)
            NavigationLink("settings.licenses") { LicensesView() }
                .buttonStyle(SettingsRowButtonStyle())
            HStack {
                Text("settings.version")
                Spacer()
                Text(verbatim: "\(configuration.marketingVersion) (\(configuration.buildNumber))")
                    .foregroundStyle(RENNColor.textSecondary)
            }
            .font(RENNFont.body)
            .foregroundStyle(RENNColor.textPrimary)
        }
    }

    #if DEBUG
    /// Development-only diagnostics: configuration placeholders and font fallback are
    /// always visible to developers, never hidden as completed branding (02 D01, 08 I03).
    private var developerSection: some View {
        SettingsGroup(title: "settings.developer") {
            developerLine("Environment", configuration.environment.rawValue)
            developerLine("Localization", effectiveLocalization)
            developerLine("Access", "\(viewModel.access.level.rawValue) · \(viewModel.access.provenance.rawValue)")
            ForEach(configuration.missingConfiguration, id: \.self) { item in
                developerLine("Placeholder", item)
            }
            ForEach(FontRegistry.report()) { face in
                developerLine(face.role, "\(face.postScriptName): \(face.isAvailable ? "bundled" : "MISSING → system fallback")")
            }
        }
    }

    private func developerLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label).font(RENNFont.secondary).foregroundStyle(RENNColor.textSecondary)
            Text(verbatim: value).font(.footnote.monospaced()).foregroundStyle(RENNColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    // MARK: Helpers

    @ViewBuilder
    private func linkRow(_ title: LocalizedStringKey, url: URL?) -> some View {
        if let url {
            Button(title) { openURL(url) }
                .buttonStyle(SettingsRowButtonStyle())
        } else {
            // Owner-specific documents/hosting are not supplied yet (08 I04).
            HStack {
                Text(title)
                Spacer()
                Text("settings.notAvailableYet").foregroundStyle(RENNColor.textSecondary)
            }
            .font(RENNFont.body)
            .foregroundStyle(RENNColor.textPrimary.opacity(0.6))
            .frame(minHeight: RENNMetrics.minimumTouchTarget)
        }
    }

    private var restoreMessage: LocalizedStringKey? {
        switch viewModel.restoreState {
        case .idle, .restoring: nil
        case .restored: "settings.restore.restored"
        case .nothingToRestore: "settings.restore.nothing"
        case .failed(.notConfigured): "settings.restore.notConfigured"
        case .failed: "settings.restore.failed"
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(RENNFont.roboto(13, medium: true, relativeTo: .footnote))
                .foregroundStyle(RENNColor.textSecondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackground(cornerRadius: RENNMetrics.cardRadius)
        }
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RENNFont.body)
            .foregroundStyle(RENNColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: RENNMetrics.minimumTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Third-party notices. Font and SDK notices are added when the licensed files/SDKs are
/// bundled (08 I03, M06).
private struct LicensesView: View {
    var body: some View {
        ScrollView {
            Text("settings.licenses.pending")
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textSecondary)
                .padding(RENNMetrics.sideMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RENNColor.backgroundBase.ignoresSafeArea())
        .navigationTitle(Text("settings.licenses"))
    }
}
