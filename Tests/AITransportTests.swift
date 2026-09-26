import XCTest
import Foundation
import PDFKit
import AppKit
@testable import AuraAI

final class MockProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handle!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class AITransportTests: XCTestCase {
    private var configuration: AIConfiguration {
        AIConfiguration(provider: .groq, model: AIProvider.groq.models[0], endpoint: try! AIProvider.groq.endpoint(accountID: ""), credential: "synthetic-test-credential")
    }
    private func transport() -> AITransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        return AITransport(session: URLSession(configuration: config))
    }
    private func data(_ value: String) -> Data { Data(value.utf8) }

    func testTextAndNullContentResponses() throws {
        let text = try JSONDecoder().decode(AICompletionResponse.self, from: data(#"{"choices":[{"message":{"role":"assistant","content":"Hello"}}]}"#)).message()
        XCTAssertEqual(text.content, "Hello")
        let response = try JSONDecoder().decode(AICompletionResponse.self, from: data(#"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call1","type":"function","function":{"name":"get_vitals","arguments":"{}"}}]}}]}"#)).message()
        XCTAssertNil(response.content)
        XCTAssertEqual(try response.toolCalls?.first?.input().count, 0)
        let empty = AIToolCall(id: "a", type: "function", function: .init(name: "get_vitals", arguments: ""))
        XCTAssertTrue(try empty.input().isEmpty)
        XCTAssertThrowsError(try AIToolCall(id: "b", type: "function", function: .init(name: "get_vitals", arguments: "[]")).input())
        XCTAssertThrowsError(try JSONDecoder().decode(AICompletionResponse.self, from: data(#"{"choices":[]}"#)).message())
        XCTAssertThrowsError(try JSONDecoder().decode(AICompletionResponse.self, from: data(#"{"choices":[{"finish_reason":"length","message":{"role":"assistant","content":"partial"}}]}"#)).message())
    }

    func testSchemasPreserveEveryTool() throws {
        let expected: Set<String> = ["get_vitals", "get_biomarkers", "get_medications", "get_conditions", "get_habits", "get_diet", "get_health_summary", "import_lab_results", "add_biomarker", "add_measurement", "log_medication", "add_habit", "log_habit", "add_condition", "add_medication", "deactivate_habit", "deactivate_medication", "update_condition", "delete_measurement", "delete_biomarker", "navigate"]
        let tools = try AITools.definitions()
        XCTAssertEqual(Set(tools.map(\.function.name)), expected)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tools)) as! [[String: Any]]
        XCTAssertTrue(encoded.allSatisfy { $0["type"] as? String == "function" && ($0["function"] as? [String: Any])?["parameters"] != nil })
    }

    func testMultipleToolsRoundTripAndEndpointIsolation() async throws {
        var requests = 0
        var names = [String]()
        MockProtocol.handle = { request in
            XCTAssertEqual(request.url?.host, "api.groq.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-credential")
            // URLProtocol can receive a body stream instead of httpBody.
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; body.append(buffer, count: count)
                }
            }
            let decoded = try JSONDecoder().decode(AICompletionRequest.self, from: body)
            XCTAssertEqual(decoded.messages.first?.role, "system")
            requests += 1
            if requests == 1 {
                return (200, Data(#"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call1","type":"function","function":{"name":"get_vitals","arguments":"{\"days\":2}"}},{"id":"call2","type":"function","function":{"name":"get_medications","arguments":""}}]}}]}"#.utf8))
            }
            XCTAssertEqual(decoded.messages.suffix(2).map(\.role), ["tool", "tool"])
            XCTAssertEqual(decoded.messages.suffix(2).compactMap(\.toolCallID), ["call1", "call2"])
            XCTAssertEqual(decoded.messages[2].toolCalls?.count, 2)
            return (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"Done"}}]}"#.utf8))
        }
        let result = try await AIToolConversation(transport: transport()).run(configuration: configuration, messages: [AIMessage(role: "system", content: "Test"), AIMessage(role: "user", content: "Test")], tools: AITools.definitions()) { name, input in
            names.append(name)
            if name == "get_vitals" { XCTAssertEqual(input["days"] as? Int, 2) }
            return "synthetic result"
        }
        XCTAssertEqual(result, "Done")
        XCTAssertEqual(names, ["get_vitals", "get_medications"])
        XCTAssertEqual(requests, 2)
    }

    func testTextOnlyAndHTTPFailures() async throws {
        MockProtocol.handle = { _ in (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"Hello"}}]}"#.utf8)) }
        let reply = try await transport().complete(configuration: configuration, messages: [.init(role: "user", content: "Hello")])
        XCTAssertEqual(reply.content, "Hello")
        for status in [401, 403, 404, 429, 503] {
            MockProtocol.handle = { _ in (status, Data("sensitive upstream echo".utf8)) }
            do {
                _ = try await transport().complete(configuration: configuration, messages: [])
                XCTFail("Expected HTTP failure")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("Groq"))
                XCTAssertFalse(error.localizedDescription.contains("sensitive"))
            }
        }
        MockProtocol.handle = { _ in throw URLError(.timedOut) }
        do { _ = try await transport().complete(configuration: configuration, messages: []); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        MockProtocol.handle = { _ in (200, Data("bad JSON".utf8)) }
        do { _ = try await transport().complete(configuration: configuration, messages: []); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("invalid")) }
    }

    func testLoopBoundAndInvalidArgumentsDoNotExecute() async throws {
        var requests = 0
        var executions = 0
        MockProtocol.handle = { _ in
            requests += 1
            return (200, Data(#"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"bad","type":"function","function":{"name":"add_measurement","arguments":"not JSON"}}]}}]}"#.utf8))
        }
        let result = try await AIToolConversation(transport: transport()).run(configuration: configuration, messages: [], tools: AITools.definitions()) { _, _ in executions += 1; return "unexpected" }
        XCTAssertEqual(requests, 4)
        XCTAssertEqual(executions, 0)
        XCTAssertTrue(result.contains("limit"))
    }

    func testConfigurationDefaultsAndValidation() throws {
        let suite = "AuraAITest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertThrowsError(try AIConfiguration.current(defaults: defaults, credentialForKey: { _ in nil }))
        let resolved = try AIConfiguration.current(defaults: defaults, credentialForKey: { key in
            XCTAssertEqual(key, "groq-api-key")
            return "synthetic-test-credential"
        })
        XCTAssertEqual(resolved.provider, .groq)
        XCTAssertEqual(AIProvider.groq.models.first?.id, "openai/gpt-oss-120b")
        XCTAssertEqual(Set(AIProvider.allCases.map(\.credentialKey)).count, 3)
        XCTAssertThrowsError(try AIProvider.cloudflare.endpoint(accountID: "../escape"))
        let endpoint = try AIProvider.cloudflare.endpoint(accountID: String(repeating: "a", count: 32))
        XCTAssertEqual(endpoint.scheme, "https")
        XCTAssertEqual(endpoint.host, "api.cloudflare.com")
    }

    func testLocalTextAndPDFWithoutCredentials() async throws {
        let text = "Quest Diagnostics\nCollected Date: 09/01/2026\nGlucose 95 mg/dL\n"
        let markers = LocalLabParser.parse(text: text, fileName: "test.txt")
        XCTAssertEqual(markers.first?.marker, "Glucose")
        XCTAssertEqual(markers.first?.value, 95)
        XCTAssertEqual(LocalLabParser.parse(text: "Vitamin B12 420 pg/mL", fileName: "test.txt").first?.value, 420)
        XCTAssertEqual(LocalLabParser.parse(text: "HbA1c 5.4 %", fileName: "test.txt").first?.value, 5.4)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        // A text-backed PDF validates the production PDFKit extraction path.
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        view.textStorage?.setAttributedString(attributed)
        try view.dataWithPDF(inside: view.bounds).write(to: url)
        let pdfMarkers = try await LocalLabParser.parse(fileURL: url)
        XCTAssertEqual(pdfMarkers.first?.value, 95)
    }
}
