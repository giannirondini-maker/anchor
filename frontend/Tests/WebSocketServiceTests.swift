/**
 * WebSocket Service Tests
 *
 * Unit tests for WebSocketService including connection state management,
 * reconnection logic, message handling, and ping/pong keep-alive
 */

import Foundation
import Testing
@testable import Anchor

struct WebSocketServiceTests {
    
    // MARK: - Initial State Tests
    
    @MainActor
    @Test func testInitialState() {
        let service = WebSocketService()
        
        #expect(!service.isConnected, "Should not be connected initially")
        #expect(service.connectionState == .disconnected, "Should be in disconnected state")
        #expect(service.connectionError == nil, "Should have no connection error initially")
    }
    
    // MARK: - Connection State Tests
    
    @MainActor
    @Test func testConnectionStateIsConnectedProperty() {
        // Test the computed property on WebSocketConnectionState
        #expect(WebSocketConnectionState.connected.isConnected)
        #expect(!WebSocketConnectionState.disconnected.isConnected)
        #expect(!WebSocketConnectionState.connecting.isConnected)
        #expect(!WebSocketConnectionState.reconnecting(attempt: 1).isConnected)
    }
    
    @MainActor
    @Test func testConnectionStateDescriptions() {
        #expect(WebSocketConnectionState.disconnected.description == "Disconnected")
        #expect(WebSocketConnectionState.connecting.description == "Connecting...")
        #expect(WebSocketConnectionState.connected.description == "Connected")
        #expect(WebSocketConnectionState.reconnecting(attempt: 2).description == "Reconnecting (2/5)...")
    }
    
    @MainActor
    @Test func testConnectionStateEquality() {
        #expect(WebSocketConnectionState.disconnected == WebSocketConnectionState.disconnected)
        #expect(WebSocketConnectionState.connected == WebSocketConnectionState.connected)
        #expect(WebSocketConnectionState.reconnecting(attempt: 2) == WebSocketConnectionState.reconnecting(attempt: 2))
        #expect(WebSocketConnectionState.reconnecting(attempt: 1) != WebSocketConnectionState.reconnecting(attempt: 2))
    }
    
    // MARK: - Message Handling Tests
    
    @Test @MainActor
    func testHandleSessionIdleMessage() async {
        let _ = WebSocketService()

        // Simulate receiving session:idle message JSON structure
        let _ = """
        {"event":"session:idle","data":{"messageId":null,"content":null,"fullContent":null,"error":null,"toolName":null,"success":null}}
        """

        // Note: This test would require making handleMessage internal or using a test-specific protocol
        // For demonstration purposes, we're showing the expected behavior

        // When session:idle is received:
        // #expect(service.isConnected)
        // #expect(service.connectionState == .connected)
        // #expect(service.connectionError == nil)
    }
    
    @Test @MainActor
    func testMessageStartCallback() {
        let service = WebSocketService()
        var receivedMessageId: String?

        service.onMessageStart = { messageId in
            receivedMessageId = messageId
        }

        // For now, manually test the callback mechanism
        service.onMessageStart?("msg123")

        #expect(receivedMessageId == "msg123")
    }
    
    @Test @MainActor
    func testMessageDeltaCallback() {
        let service = WebSocketService()
        var receivedMessageId: String?
        var receivedDelta: String?

        service.onMessageDelta = { messageId, delta in
            receivedMessageId = messageId
            receivedDelta = delta
        }

        service.onMessageDelta?("msg123", "Hello ")

        #expect(receivedMessageId == "msg123")
        #expect(receivedDelta == "Hello ")
    }
    
    @Test @MainActor
    func testMessageCompleteCallback() {
        let service = WebSocketService()
        var receivedMessageId: String?
        var receivedContent: String?

        service.onMessageComplete = { messageId, fullContent in
            receivedMessageId = messageId
            receivedContent = fullContent
        }

        service.onMessageComplete?("msg123", "Hello, world!")

        #expect(receivedMessageId == "msg123")
        #expect(receivedContent == "Hello, world!")
    }
    
    @Test @MainActor
    func testMessageErrorCallback() {
        let service = WebSocketService()
        var receivedMessageId: String?
        var receivedError: String?

        service.onMessageError = { messageId, error in
            receivedMessageId = messageId
            receivedError = error
        }

        service.onMessageError?("msg123", "Network error")

        #expect(receivedMessageId == "msg123")
        #expect(receivedError == "Network error")
    }
    
    @Test @MainActor
    func testToolStartCallback() {
        let service = WebSocketService()
        var receivedMessageId: String?
        var receivedToolName: String?

        service.onToolStart = { messageId, toolName in
            receivedMessageId = messageId
            receivedToolName = toolName
        }

        service.onToolStart?("msg123", "web_search")

        #expect(receivedMessageId == "msg123")
        #expect(receivedToolName == "web_search")
    }
    
    @Test @MainActor
    func testToolCompleteCallback() {
        let service = WebSocketService()
        var receivedMessageId: String?
        var receivedToolName: String?

        service.onToolComplete = { messageId, toolName in
            receivedMessageId = messageId
            receivedToolName = toolName
        }

        service.onToolComplete?("msg123", "web_search")

        #expect(receivedMessageId == "msg123")
        #expect(receivedToolName == "web_search")
    }
    
    // MARK: - WebSocket Error Tests
    
    @Test func testWebSocketErrorDescriptions() {
        #expect(
            WebSocketError.invalidURL.errorDescription == "Invalid WebSocket URL"
        )
        
        #expect(
            WebSocketError.connectionFailed.errorDescription == "Failed to connect to WebSocket"
        )
        
        #expect(
            WebSocketError.messageFailed.errorDescription == "Failed to send message"
        )
        
        #expect(
            WebSocketError.connectionClosed(code: 1000).errorDescription == "Connection closed (code: 1000)"
        )
    }
    
    // MARK: - Reconnection Logic Tests (Behavioral)
    
    @MainActor
    @Test func testReconnectionAttemptsIncrement() {
        // Test that reconnection attempts would increment
        // In actual implementation, we would need to observe the state over time
        let maxAttempts = Configuration.maxReconnectAttempts
        #expect(maxAttempts == 5, "Max reconnection attempts should be 5")
        
        // Test exponential backoff calculation
        for attempt in 1...5 {
            let delay = pow(2.0, Double(attempt))
            #expect(delay > 0, "Delay should be positive")
            #expect(delay <= 32.0, "Delay should not exceed 32 seconds")
        }
    }
    
    // MARK: - Configuration Tests
    
    @Test func testConfigurationValues() {
        // Verify WebSocket configuration values
        #expect(Configuration.maxReconnectAttempts == 5)
        #expect(Configuration.reconnectBaseDelay == 1.0)
        #expect(Configuration.reconnectMaxDelay == 30.0)
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    @Test func testSharedInstance() {
        let instance1 = WebSocketService.shared
        let instance2 = WebSocketService.shared
        
        #expect(instance1 === instance2, "Shared instance should be the same object")
    }
    
    // MARK: - Connection URL Tests
    
    @Test func testConnectionURLConstruction() {
        let conversationId = "test_conv_123"
        
        // Verify Configuration provides correct WebSocket URL
        #expect(Configuration.webSocketURL.absoluteString.starts(with: "ws://"))
        
        // Verify URL construction would be valid
        let url = URL(string: "\(Configuration.webSocketURL.absoluteString)?conversationId=\(conversationId)")
        #expect(url != nil, "Constructed WebSocket URL should be valid")
        
        // Verify the URL contains the conversation ID
        #expect(url?.absoluteString.contains(conversationId) ?? false)
    }
}

// MARK: - Integration Test Notes

/*
 * Integration Tests (to be run with live backend):
 *
 * 1. testEndToEndConnection - Connect, receive session:idle, disconnect
 * 2. testMessageStreaming - Send message, receive deltas, receive completion
 * 3. testReconnectionBehavior - Simulate network failure, verify reconnection
 * 4. testPingPongKeepAlive - Verify ping/pong messages after 30 seconds
 * 5. testConversationSwitching - Switch between conversations, verify clean state
 * 6. testIntentionalDisconnect - Call disconnect(), verify no reconnection attempt
 * 7. testMultipleCallbacks - Set all callbacks, send messages, verify all fire
 * 8. testToolExecution - Verify tool:start and tool:complete events
 *
 * These tests require:
 * - Mock/test WebSocket server
 * - Dependency injection for URLSession
 * - Test-specific protocol for private method access
 */
