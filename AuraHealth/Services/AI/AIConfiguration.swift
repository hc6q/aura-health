import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case groq, cloudflare, mistral
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .cloudflare: return "Cloudflare"
        case .mistral: return "Mistral"
        }
    }
    var credentialKey: String {
        switch self {
        case .groq: return "groq-api-key"
        case .cloudflare: return "cloudflare-api-token"
        case .mistral: return "mistral-api-key"
        }
    }
    var modelKey: String { "aiModel.\(rawValue)" }
    var models: [AIModel] {
        switch self {
        case .groq: return [AIModel(id: "openai/gpt-oss-120b", name: "GPT OSS 120B (recommended)"), AIModel(id: "openai/gpt-oss-20b", name: "GPT OSS 20B")]
        case .cloudflare: return [AIModel(id: "@cf/openai/gpt-oss-120b", name: "GPT OSS 120B")]
        case .mistral: return [AIModel(id: "mistral-small-latest", name: "Mistral Small (latest)")]
        }
    }
    static var selected: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .groq
    }
    func endpoint(accountID: String) throws -> URL {
        let base: String
        switch self {
        case .groq: base = "https://api.groq.com/openai/v1"
        case .mistral: base = "https://api.mistral.ai/v1"
        case .cloudflare:
            guard accountID.count == 32, accountID.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
                throw AIServiceError.configuration("Enter a valid 32-character Cloudflare Account ID in Settings → AI.")
            }
            base = "https://api.cloudflare.com/client/v4/accounts/\(accountID)/ai/v1"
        }
        guard let url = URL(string: base + "/chat/completions"), url.scheme == "https" else {
            throw AIServiceError.configuration("AI requires a valid HTTPS endpoint.")
        }
        return url
    }
}

struct AIModel: Identifiable, Equatable {
    let id: String
    let name: String
    let supportsTools = true
    // These are capabilities enabled by this integration, not every upstream feature.
    // Attachments always use local PDFKit/Vision extraction; no raw media is uploaded.
    let supportsVision = false
    let supportsDocuments = false
}

/// Immutable snapshot: changing Settings during a tool round never changes its destination.
struct AIConfiguration {
    let provider: AIProvider
    let model: AIModel
    let endpoint: URL
    let credential: String

    static func current(defaults: UserDefaults = .standard, credentialForKey: (String) -> String? = KeychainService.getValue(for:)) throws -> AIConfiguration {
        let provider = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .groq
        let account = defaults.string(forKey: "cloudflareAccountID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let endpoint = try provider.endpoint(accountID: account)
        let credential = credentialForKey(provider.credentialKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !credential.isEmpty else { throw AIServiceError.configuration("Add your \(provider.displayName) credential in Settings → AI.") }
        let stored = defaults.string(forKey: provider.modelKey)
        let model = provider.models.first(where: { $0.id == stored }) ?? provider.models[0]
        return AIConfiguration(provider: provider, model: model, endpoint: endpoint, credential: credential)
    }
    static var isConfigured: Bool { (try? current()) != nil }
}
