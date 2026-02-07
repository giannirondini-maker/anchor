/**
 * Network Service
 *
 * Handles HTTP communication with the backend API
 */

import Foundation

actor NetworkService {
    // MARK: - Singleton
    
    static let shared = NetworkService()
    
    // MARK: - Properties
    
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    // MARK: - Initialization
    
    private init() {
        self.baseURL = Configuration.apiBaseURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Configuration.requestTimeout
        config.timeoutIntervalForResource = Configuration.resourceTimeout
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }
    
    // MARK: - Health Check
    
    func checkHealth() async throws -> HealthResponse {
        return try await get(endpoint: "health")
    }
    
    // MARK: - Models
    
    func fetchModels() async throws -> [ModelInfo] {
        let response: ModelsResponse = try await get(endpoint: "models")
        return response.models
    }
    
    // MARK: - Conversations
    
    func fetchConversations() async throws -> [Conversation] {
        let response: ConversationsResponse = try await get(endpoint: "conversations")
        return response.conversations
    }
    
    func fetchConversation(id: String) async throws -> Conversation {
        return try await get(endpoint: "conversations/\(id)")
    }
    
    func createConversation(title: String = "New Conversation", model: String? = nil, agent: String? = nil) async throws -> Conversation {
        var body: [String: Any] = ["title": title]
        if let model = model { body["model"] = model }
        if let agent = agent { body["agent"] = agent }
        
        return try await post(endpoint: "conversations", body: body)
    }
    
    func updateConversation(id: String, title: String? = nil, model: String? = nil) async throws -> Conversation {
        var body: [String: Any] = [:]
        if let title = title { body["title"] = title }
        if let model = model { body["model"] = model }
        
        return try await put(endpoint: "conversations/\(id)", body: body)
    }
    
    func deleteConversation(id: String) async throws {
        try await delete(endpoint: "conversations/\(id)")
    }
    
    func deleteAllConversations() async throws {
        try await delete(endpoint: "conversations")
    }
    
    // MARK: - Tags
    
    func addTagToConversation(conversationId: String, name: String, color: String? = nil) async throws -> Conversation {
        var body: [String: Any] = ["name": name]
        if let color = color { body["color"] = color }
        
        return try await post(endpoint: "conversations/\(conversationId)/tags", body: body)
    }
    
    func removeTagFromConversation(conversationId: String, tagId: Int) async throws -> Conversation {
        return try await deleteWithResponse(endpoint: "conversations/\(conversationId)/tags/\(tagId)")
    }
    
    // MARK: - Messages
    
    func fetchMessages(conversationId: String, limit: Int? = nil, before: String? = nil) async throws -> [Message] {
        var queryItems: [URLQueryItem] = []
        if let limit = limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let before = before { queryItems.append(URLQueryItem(name: "before", value: before)) }
        
        let response: MessagesResponse = try await get(
            endpoint: "conversations/\(conversationId)/messages",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        return response.messages
    }
    
    func sendMessage(conversationId: String, content: String) async throws -> SendMessageResponse {
        let body: [String: Any] = ["content": content]
        return try await post(endpoint: "conversations/\(conversationId)/messages", body: body)
    }

    func sendMessage(
        conversationId: String,
        content: String,
        attachments: [MessageAttachmentReference]?
    ) async throws -> SendMessageResponse {
        var body: [String: Any] = ["content": content]
        if let attachments = attachments, !attachments.isEmpty {
            let encoded = attachments.map { attachment in
                var item: [String: Any] = ["id": attachment.id]
                if let displayName = attachment.displayName {
                    item["displayName"] = displayName
                }
                return item
            }
            body["attachments"] = encoded
        }
        return try await post(endpoint: "conversations/\(conversationId)/messages", body: body)
    }

    // MARK: - Attachments

    func uploadAttachment(
        conversationId: String,
        fileURL: URL,
        displayName: String? = nil
    ) async throws -> Attachment {
        let url = baseURL.appendingPathComponent("attachments")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(formField: "conversationId", value: conversationId, using: boundary)
        if let displayName = displayName {
            body.append(formField: "displayName", value: displayName, using: boundary)
        }

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = mimeTypeForExtension(fileURL.pathExtension)
        body.append(fileField: "file", filename: filename, mimeType: mimeType, fileData: fileData, using: boundary)
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoded = try decoder.decode(AttachmentUploadResponse.self, from: data)
        guard let attachment = decoded.attachments.first else {
            throw NetworkError.badRequest
        }
        return attachment
    }

    func updateAttachmentName(attachmentId: String, displayName: String) async throws -> Attachment {
        let body: [String: Any] = ["displayName": displayName]
        return try await put(endpoint: "attachments/\(attachmentId)", body: body)
    }

    func deleteAttachment(attachmentId: String) async throws {
        try await delete(endpoint: "attachments/\(attachmentId)")
    }
    
    // MARK: - Private Helpers
    
    private func get<T: Decodable>(endpoint: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let url: URL
        if let queryItems = queryItems, !queryItems.isEmpty {
            var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems
            guard let builtURL = components.url else {
                throw NetworkError.badRequest
            }
            url = builtURL
        } else {
            url = baseURL.appendingPathComponent(endpoint)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Log the raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ Failed to decode response from \(endpoint):")
                print("   Raw JSON: \(jsonString.prefix(500))")
                print("   Error: \(error)")
            }
            throw error
        }
    }
    
    private func post<T: Decodable>(endpoint: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func put<T: Decodable>(endpoint: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func delete(endpoint: String) async throws {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    private func deleteWithResponse<T: Decodable>(endpoint: String) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 400:
            throw NetworkError.badRequest
        case 401:
            throw NetworkError.unauthorized
        case 404:
            throw NetworkError.notFound
        case 500...599:
            throw NetworkError.serverError(httpResponse.statusCode)
        default:
            throw NetworkError.unknown(httpResponse.statusCode)
        }
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "txt", "log": return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "csv": return "text/csv"
        case "json": return "application/json"
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "js", "ts", "tsx", "jsx", "py", "swift", "java", "go", "rs", "rb", "c", "h", "cpp", "hpp":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - Multipart Helpers

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func append(formField name: String, value: String, using boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func append(
        fileField name: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        using boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}

// MARK: - Network Errors

enum NetworkError: LocalizedError {
    case invalidResponse
    case badRequest
    case unauthorized
    case notFound
    case serverError(Int)
    case unknown(Int)
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .badRequest:
            return "Bad request"
        case .unauthorized:
            return "Not authorized. Please check your authentication."
        case .notFound:
            return "Resource not found"
        case .serverError(let code):
            return "Server error (\(code))"
        case .unknown(let code):
            return "Unknown error (\(code))"
        case .connectionFailed:
            return "Failed to connect to server. Is the backend running?"
        }
    }
}
