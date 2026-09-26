import Foundation

struct AIMessage: Codable {
    let role: String
    var content: String?
    var toolCalls: [AIToolCall]? = nil
    var toolCallID: String? = nil
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls", toolCallID = "tool_call_id"
    }
}
struct AIToolCall: Codable {
    let id: String
    let type: String
    let function: Function
    struct Function: Codable {
        let name: String
        let arguments: String
    }
    func input() throws -> [String: Any] {
        let raw = function.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }
        return object
    }
}
struct AIToolDefinition: Codable {
    var type = "function"
    let function: Function
    struct Function: Codable {
        let name: String
        let description: String
        let parameters: JSONValue
    }
}
struct AICompletionRequest: Codable {
    let model: String
    let messages: [AIMessage]
    let tools: [AIToolDefinition]?
    let maxTokens: Int
    enum CodingKeys: String, CodingKey {
        case model, messages, tools
        case maxTokens = "max_tokens"
    }
}
struct AICompletionResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: AIMessage
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    func message() throws -> AIMessage {
        guard let choice = choices.first, choice.message.role == "assistant",
              choice.finishReason != "length", choice.finishReason != "content_filter" else {
            throw AIServiceError.invalidResponse
        }
        let calls = choice.message.toolCalls ?? []
        guard calls.count <= 32, Set(calls.map(\.id)).count == calls.count,
              calls.allSatisfy({ !$0.id.isEmpty && $0.type == "function" && !$0.function.name.isEmpty }),
              !calls.isEmpty || !(choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
            throw AIServiceError.invalidResponse
        }
        return choice.message
    }
}

/// A single HTTP implementation shared by chat, lab extraction and smart habits.
/// Never exposes upstream bodies, which can echo health data or credentials.
struct AITransport {
    let session: URLSession
    init(session: URLSession = AITransport.privateSession) { self.session = session }
    private static let redirectPolicy = AIRedirectPolicy()
    private static let privateSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: redirectPolicy, delegateQueue: nil)
    }()
    func complete(configuration: AIConfiguration, messages: [AIMessage], tools: [AIToolDefinition]? = nil) async throws -> AIMessage {
        guard configuration.endpoint.scheme == "https" else { throw AIServiceError.configuration("HTTPS is required.") }
        if tools != nil && !configuration.model.supportsTools { throw AIServiceError.configuration("This model does not support tools.") }
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(AICompletionRequest(model: configuration.model.id, messages: messages, tools: tools, maxTokens: 4096))
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw AIServiceError.http(provider: configuration.provider.displayName, status: http.statusCode)
            }
            do { return try JSONDecoder().decode(AICompletionResponse.self, from: data).message() }
            catch { throw AIServiceError.invalidResponse }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? AIServiceError.timeout : AIServiceError.network
        }
    }
}
private final class AIRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not forward credentials or health data to a redirect destination.
        completionHandler(nil)
    }
}

/// Bounded orchestration, with device-only execution supplied by AIService.
@MainActor
struct AIToolConversation {
    let transport: AITransport
    func run(configuration: AIConfiguration, messages initial: [AIMessage], tools: [AIToolDefinition], execute: (String, [String: Any]) async -> String) async throws -> String {
        var messages = initial
        var executed = [String: String]()
        for _ in 0..<4 {
            try Task.checkCancellation()
            let reply: AIMessage
            do {
                reply = try await transport.complete(configuration: configuration, messages: messages, tools: tools)
            } catch {
                let completed = messages.filter { $0.role == "tool" }.compactMap(\.content)
                guard !completed.isEmpty else { throw error }
                return "The AI response could not be completed. Actions already processed:\n" + completed.joined(separator: "\n") + "\n" + error.localizedDescription
            }
            let calls = reply.toolCalls ?? []
            if calls.isEmpty { return reply.content ?? "" }
            messages.append(reply)
            for call in calls {
                try Task.checkCancellation()
                let result: String
                if let previous = executed[call.id] {
                    result = previous
                } else if tools.contains(where: { $0.function.name == call.function.name }) {
                    do { result = await execute(call.function.name, try call.input()) }
                    catch { result = "Invalid tool arguments. Supply a JSON object matching the function schema. No action was performed." }
                    executed[call.id] = result
                } else { result = "Unknown tool. No action was performed." }
                messages.append(AIMessage(role: "tool", content: result, toolCallID: call.id))
            }
        }
        // Return completed actions even if the provider never produces its final answer.
        // Do not replay a write or switch models/providers automatically.
        let results = messages.filter { $0.role == "tool" }.compactMap(\.content)
        return "Tool round limit reached. Actions already processed:\n" + results.joined(separator: "\n")
    }
}

enum AIServiceError: LocalizedError {
    case configuration(String), http(provider: String, status: Int)
    case invalidResponse, timeout, network, unreadableAttachment, attachmentTooLarge
    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .http(let provider, let status):
            switch status {
            case 401, 403: return "\(provider): credential invalid or missing permission. Review Settings → AI."
            case 404: return "\(provider): model or endpoint unavailable. Review the selected model."
            case 429: return "\(provider): quota or rate limit reached. Try again later."
            case 500...599: return "\(provider) is temporarily unavailable. Try again later."
            default: return "\(provider) rejected the request (HTTP \(status)). Check the model and account configuration."
            }
        case .invalidResponse: return "The AI provider returned an invalid or incomplete response."
        case .timeout: return "The AI request timed out. Check for completed actions before retrying."
        case .network: return "Could not connect to the AI provider. Check your connection."
        case .unreadableAttachment: return "No readable text found. Use a clearer image, searchable PDF or text file. Raw images and documents are not uploaded by this integration."
        case .attachmentTooLarge: return "The attachment is too large. Select up to 30 pages, 20 MB or 60,000 text characters."
        }
    }
}
