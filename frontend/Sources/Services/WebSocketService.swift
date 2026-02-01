/**
 * WebSocket Service
 *
 * Handles WebSocket communication for real-time message streaming.
 *
 * Connection State Management:
 * - `isConnected`: True only after server confirms connection with `session:idle` event
 * - `connectionState`: Detailed state for UI feedback (connecting, connected, disconnected, reconnecting)
 * - Connection is confirmed via URLSessionWebSocketDelegate + server `session:idle` event
 *
 * Reconnection Strategy:
 * - Automatic reconnection with exponential backoff (1s, 2s, 4s, 8s, 16s)
 * - Maximum 5 reconnection attempts before giving up
 * - Ping/pong keep-alive every 30 seconds to detect stale connections
 */

import Foundation
import Combine

// MARK: - Connection State

enum WebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting(let attempt): return "Reconnecting (\(attempt)/5)..."
        }
    }
}

// MARK: - WebSocket Service

@MainActor
class WebSocketService: NSObject, ObservableObject {
    // MARK: - Singleton
    
    static let shared = WebSocketService()
    
    // MARK: - Published Properties
    
    /// True only when connection is confirmed by server (session:idle received)
    @Published var isConnected: Bool = false
    
    /// Detailed connection state for UI feedback
    @Published var connectionState: WebSocketConnectionState = .disconnected
    
    /// Last connection error, if any
    @Published var connectionError: Error?
    
    // MARK: - Properties
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    private var currentConversationId: String?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = Configuration.maxReconnectAttempts
    private var isClosingIntentionally = false
    private var pingTimer: Timer?
    private let pingInterval: TimeInterval = 30.0
    
    // MARK: - Callbacks
    
    var onMessageStart: ((String) -> Void)?
    var onMessageDelta: ((String, String) -> Void)?
    var onMessageComplete: ((String, String) -> Void)?
    var onMessageError: ((String, String) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        // Set delegate to self for URLSessionWebSocketDelegate callbacks
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Connection Management
    
    func connect(conversationId: String) {
        // If already connected to this conversation, do nothing
        if currentConversationId == conversationId && isConnected {
            print("🔌 [WS] Already connected to conversation: \(conversationId)")
            return
        }
        
        // Close existing connection if switching conversations
        if webSocket != nil {
            print("🔌 [WS] Switching from conversation \(currentConversationId ?? "none") to \(conversationId)")
            isClosingIntentionally = true
            webSocket?.cancel(with: .goingAway, reason: nil)
            webSocket = nil
            stopPingTimer()
        }
        
        // Start new connection
        currentConversationId = conversationId
        reconnectAttempts = 0
        createConnection()
    }
    
    private func createConnection() {
        guard let conversationId = currentConversationId else {
            print("❌ [WS] No conversation ID set")
            return
        }
        
        isClosingIntentionally = false
        connectionState = reconnectAttempts > 0 ? .reconnecting(attempt: reconnectAttempts) : .connecting
        connectionError = nil
        
        // Build WebSocket URL using Configuration
        let baseWsUrl = Configuration.webSocketURL.absoluteString
        guard let url = URL(string: "\(baseWsUrl)?conversationId=\(conversationId)") else {
            connectionError = WebSocketError.invalidURL
            connectionState = .disconnected
            print("❌ [WS] Invalid URL")
            return
        }
        
        print("🔌 [WS] Connecting to: \(url.absoluteString)")
        
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        // Note: isConnected will be set to true only when we receive session:idle from server
        // This happens in handleMessage() after the connection is confirmed
        
        // Start receiving messages
        receiveMessage()
    }
    
    func disconnect() {
        print("🔌 [WS] Disconnecting intentionally")
        isClosingIntentionally = true
        stopPingTimer()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        connectionState = .disconnected
        currentConversationId = nil
    }
    
    // MARK: - Ping/Pong Keep-Alive (Task 6)
    
    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
        }
        print("🏓 [WS] Ping timer started (interval: \(pingInterval)s)")
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        webSocket?.sendPing { [weak self] error in
            Task { @MainActor in
                if let error = error {
                    print("🏓 [WS] Ping failed: \(error.localizedDescription)")
                    self?.handleDisconnect(error: error)
                } else {
                    print("🏓 [WS] Pong received")
                }
            }
        }
    }
    
    // MARK: - Message Receiving
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue listening
                    self.receiveMessage()
                    
                case .failure(let error):
                    print("❌ [WS] Receive error: \(error.localizedDescription)")
                    self.handleDisconnect(error: error)
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
            
            switch message.event {
            case "session:idle":
                // Task 2: Connection confirmed by server
                isConnected = true
                connectionState = .connected
                connectionError = nil
                reconnectAttempts = 0
                startPingTimer()
                print("✅ [WS] Session ready - connection confirmed for conversation: \(currentConversationId ?? "unknown")")
                
            case "message:start":
                if let messageId = message.data.messageId {
                    onMessageStart?(messageId)
                }
                
            case "message:delta":
                if let messageId = message.data.messageId,
                   let content = message.data.content {
                    onMessageDelta?(messageId, content)
                }
                
            case "message:complete":
                if let messageId = message.data.messageId,
                   let fullContent = message.data.fullContent {
                    onMessageComplete?(messageId, fullContent)
                }
                
            case "message:error":
                if let messageId = message.data.messageId,
                   let error = message.data.error {
                    onMessageError?(messageId, error)
                }
                
            case "pong":
                // Server pong response (if using application-level ping)
                print("🏓 [WS] Application pong received")
                
            default:
                print("⚠️ [WS] Unknown event: \(message.event)")
            }
        } catch {
            print("❌ [WS] Failed to decode message: \(error.localizedDescription)")
        }
    }
    
    private func handleDisconnect(error: Error) {
        stopPingTimer()
        isConnected = false
        
        // If we closed intentionally, don't try to reconnect
        guard !isClosingIntentionally else {
            print("🔌 [WS] Intentional disconnect, not reconnecting")
            connectionState = .disconnected
            return
        }
        
        connectionError = error
        
        // Attempt reconnection with exponential backoff
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            connectionState = .reconnecting(attempt: reconnectAttempts)
            
            let delay = pow(2.0, Double(reconnectAttempts))
            print("🔄 [WS] Reconnecting in \(delay)s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))...")
            
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self = self, !self.isClosingIntentionally else { return }
                self.createConnection()
            }
        } else {
            print("❌ [WS] Max reconnection attempts reached")
            connectionState = .disconnected
        }
    }
    
    // MARK: - Sending Messages
    
    func send(_ message: String) {
        guard isConnected else {
            print("⚠️ [WS] Cannot send message: not connected")
            return
        }
        
        webSocket?.send(.string(message)) { error in
            if let error = error {
                print("❌ [WS] Failed to send message: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate (Task 3)

extension WebSocketService: URLSessionWebSocketDelegate {
    
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            print("✅ [WS] Transport opened (protocol: \(`protocol` ?? "none"))")
            // Note: We don't set isConnected here - we wait for session:idle from server
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
            print("🔌 [WS] Transport closed (code: \(closeCode.rawValue), reason: \(reasonString))")
            
            if !isClosingIntentionally {
                handleDisconnect(error: WebSocketError.connectionClosed(code: closeCode.rawValue))
            }
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            if let error = error {
                print("❌ [WS] Task completed with error: \(error.localizedDescription)")
                if !isClosingIntentionally {
                    handleDisconnect(error: error)
                }
            }
        }
    }
}

// MARK: - WebSocket Errors

enum WebSocketError: LocalizedError {
    case invalidURL
    case connectionFailed
    case messageFailed
    case connectionClosed(code: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .connectionFailed:
            return "Failed to connect to WebSocket"
        case .messageFailed:
            return "Failed to send message"
        case .connectionClosed(let code):
            return "Connection closed (code: \(code))"
        }
    }
}
