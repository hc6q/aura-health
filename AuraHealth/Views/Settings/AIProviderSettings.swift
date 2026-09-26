import SwiftUI

struct AIProviderSettings: View {
    @AppStorage("aiProvider") private var provider: AIProvider = .groq
    @AppStorage("cloudflareAccountID") private var accountID = ""
    @AppStorage("aiModel.groq") private var groqModel = "openai/gpt-oss-120b"
    @AppStorage("aiModel.cloudflare") private var cloudflareModel = "@cf/openai/gpt-oss-120b"
    @AppStorage("aiModel.mistral") private var mistralModel = "mistral-small-latest"
    @State private var credential = ""
    @State private var hasCredential = false
    @State private var keychainError: String?

    private var modelSelection: Binding<String> {
        switch provider {
        case .groq: return $groqModel
        case .cloudflare: return $cloudflareModel
        case .mistral: return $mistralModel
        }
    }
    private var configured: Bool {
        hasCredential && (try? provider.endpoint(accountID: accountID.trimmingCharacters(in: .whitespacesAndNewlines))) != nil
    }
    var body: some View {
        Group {
            Picker("AI Provider", selection: $provider) {
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Model", selection: modelSelection) {
                ForEach(provider.models) { Text($0.name).tag($0.id) }
            }
            if provider == .cloudflare {
                TextField("Account ID", text: $accountID)
                    .autocorrectionDisabled()
                Text("Use the 32-character Account ID and a token with Workers AI permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(configured ? "Configured" : "Not configured")
                    .foregroundStyle(configured ? Color.green : Color.secondary)
                Spacer()
                if hasCredential {
                    Button("Remove", role: .destructive) {
                        if KeychainService.deleteValue(for: provider.credentialKey) { refresh() }
                        else { keychainError = "Could not remove the credential from Keychain." }
                    }
                }
            }
            if !hasCredential {
                SecureField(provider == .cloudflare ? "API Token" : "API Key", text: $credential)
                    .autocorrectionDisabled()
                Button("Save") {
                    let value = credential.trimmingCharacters(in: .whitespacesAndNewlines)
                    if KeychainService.setValue(value, for: provider.credentialKey) {
                        credential = ""
                        refresh()
                    } else { keychainError = "Could not save the credential to Keychain. Try again." }
                }
                .disabled(credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let keychainError { Text(keychainError).foregroundStyle(.red) }
            Text("AI requests may send the message and relevant health context to the selected provider. API credentials are stored in Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            if provider == .groq {
                Text("You can enable Zero Data Retention in your Groq account’s Data Controls. GPT OSS 20B is available as a manual alternative; Aura never switches providers automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if provider == .mistral {
                Text("Mistral free mode may use inputs and outputs to improve or train models. Review and disable this in your Mistral account’s Privacy settings if desired.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Review Cloudflare Workers AI’s current data usage policy and account limits before sending health information.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { refresh() }
        .onChange(of: provider) { _, _ in
            credential = ""
            refresh()
        }
    }
    private func refresh() {
        hasCredential = !(KeychainService.getValue(for: provider.credentialKey)?.isEmpty ?? true)
        keychainError = nil
        if !provider.models.contains(where: { $0.id == modelSelection.wrappedValue }) {
            modelSelection.wrappedValue = provider.models[0].id
        }
    }
}
