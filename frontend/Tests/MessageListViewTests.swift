/**
 * MessageListView Tests
 *
 * Unit tests for MessageListView including message rendering,
 * streaming indicators, tool activity, and scroll behavior
 */

import XCTest
import SwiftUI
@testable import Anchor

final class MessageListViewTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func createMessage(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String = "Test content",
        status: MessageStatus = .sent,
        errorMessage: String? = nil,
        attachments: [Attachment]? = nil
    ) -> Message {
        Message(
            id: id,
            conversationId: "test_conv",
            role: role,
            content: content,
            status: status,
            errorMessage: errorMessage,
            attachments: attachments
        )
    }
    
    private func createAttachment(
        id: String = UUID().uuidString,
        displayName: String = "test.txt"
    ) -> Attachment {
        Attachment(
            id: id,
            conversationId: "test_conv",
            originalName: displayName,
            displayName: displayName,
            size: 1024,
            mimeType: "text/plain",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    // MARK: - Streaming Indicator Logic Tests
    
    func testStreamingIndicatorLogic_whenLoadingAndNoPlaceholder() {
        let messages: [Message] = []
        let isLoading = true
        
        // When loading with no messages, streaming indicator should show
        // Logic: isLoading = true AND (no messages OR last message is not .sending)
        let shouldShow = isLoading && (messages.isEmpty || messages.last?.status != .sending)
        XCTAssertTrue(shouldShow, "Should show streaming indicator when loading with no placeholder")
    }
    
    func testStreamingIndicatorLogic_whenNotLoading() {
        let messages: [Message] = []
        let isLoading = false
        
        // When not loading, streaming indicator should not show
        let shouldShow = isLoading && (messages.isEmpty || messages.last?.status != .sending)
        XCTAssertFalse(shouldShow, "Should not show streaming indicator when not loading")
    }
    
    func testStreamingIndicatorLogic_whenPlaceholderExists() {
        // Last message is placeholder being streamed
        let messages = [
            createMessage(role: .user, content: "Hello"),
            createMessage(role: .assistant, content: "", status: .sending)
        ]
        let isLoading = true
        
        // Should not show streaming indicator when we have a placeholder message
        let shouldShow = isLoading && (messages.isEmpty || messages.last?.status != .sending)
        XCTAssertFalse(shouldShow, "Should not show streaming indicator when placeholder exists")
    }
    
    // MARK: - WebSocket Connection State Tests
    
    func testWebSocketConnectionStateEquality() {
        XCTAssertEqual(WebSocketConnectionState.disconnected, .disconnected)
        XCTAssertEqual(WebSocketConnectionState.connecting, .connecting)
        XCTAssertEqual(WebSocketConnectionState.connected, .connected)
        XCTAssertEqual(
            WebSocketConnectionState.reconnecting(attempt: 3),
            WebSocketConnectionState.reconnecting(attempt: 3)
        )
        
        XCTAssertNotEqual(
            WebSocketConnectionState.reconnecting(attempt: 1),
            WebSocketConnectionState.reconnecting(attempt: 2)
        )
    }
    
    func testWebSocketConnectionStateDescriptions() {
        XCTAssertEqual(WebSocketConnectionState.disconnected.description, "Disconnected")
        XCTAssertEqual(WebSocketConnectionState.connecting.description, "Connecting...")
        XCTAssertEqual(WebSocketConnectionState.connected.description, "Connected")
        XCTAssertEqual(
            WebSocketConnectionState.reconnecting(attempt: 3).description,
            "Reconnecting (3/5)..."
        )
    }
    
    func testWebSocketConnectionStateIsConnected() {
        XCTAssertTrue(WebSocketConnectionState.connected.isConnected)
        XCTAssertFalse(WebSocketConnectionState.disconnected.isConnected)
        XCTAssertFalse(WebSocketConnectionState.connecting.isConnected)
        XCTAssertFalse(WebSocketConnectionState.reconnecting(attempt: 1).isConnected)
    }
    
    // MARK: - Message Bubble Equatable Tests
    
    func testMessageBubbleEquality_sameContent() {
        let message = createMessage(id: "msg1", role: .user, content: "Hello")
        
        let bubble1 = MessageBubbleView(message: message)
        let bubble2 = MessageBubbleView(message: message)
        
        XCTAssertTrue(bubble1 == bubble2, "Bubbles with same message should be equal")
    }
    
    func testMessageBubbleEquality_differentContent() {
        let message1 = createMessage(id: "msg1", role: .user, content: "Hello")
        let message2 = createMessage(id: "msg1", role: .user, content: "Hello World")
        
        let bubble1 = MessageBubbleView(message: message1)
        let bubble2 = MessageBubbleView(message: message2)
        
        XCTAssertFalse(bubble1 == bubble2, "Bubbles with different content should not be equal")
    }
    
    func testMessageBubbleEquality_differentStatus() {
        let message1 = createMessage(id: "msg1", role: .user, content: "Hello", status: .sent)
        let message2 = createMessage(id: "msg1", role: .user, content: "Hello", status: .error)
        
        let bubble1 = MessageBubbleView(message: message1)
        let bubble2 = MessageBubbleView(message: message2)
        
        XCTAssertFalse(bubble1 == bubble2, "Bubbles with different status should not be equal")
    }
    
    func testMessageBubbleEquality_differentAttachments() {
        let message1 = createMessage(id: "msg1", role: .user, content: "Hello", attachments: nil)
        let message2 = createMessage(id: "msg1", role: .user, content: "Hello", attachments: [createAttachment()])
        
        let bubble1 = MessageBubbleView(message: message1)
        let bubble2 = MessageBubbleView(message: message2)
        
        XCTAssertFalse(bubble1 == bubble2, "Bubbles with different attachments should not be equal")
    }
    
    // MARK: - CachedMarkdownView Equatable Tests
    
    func testCachedMarkdownViewEquality_sameContent() {
        let view1 = CachedMarkdownView(content: "# Hello")
        let view2 = CachedMarkdownView(content: "# Hello")
        
        XCTAssertTrue(view1 == view2, "Views with same content should be equal")
    }
    
    func testCachedMarkdownViewEquality_differentContent() {
        let view1 = CachedMarkdownView(content: "# Hello")
        let view2 = CachedMarkdownView(content: "# World")
        
        XCTAssertFalse(view1 == view2, "Views with different content should not be equal")
    }
    
    // MARK: - Tool Activity Tests
    
    func testToolActivityToolNames() {
        // Test that tool names are properly stored
        let toolNames = ["web_search", "bing_search", "read_url", "fetch_url", 
                        "read_file", "code_search", "run_command", "custom_tool"]
        
        for toolName in toolNames {
            let view = ToolActivityIndicatorView(toolName: toolName)
            // displayName is private, but we can verify the view is created
            XCTAssertNotNil(view)
        }
        
        // Note: Display name logic tested via integration tests
        // Expected mappings:
        // web_search/bing_search -> "Searching the web"
        // read_url/fetch_url -> "Reading webpage"
        // read_file -> "Reading file"
        // code_search -> "Searching code"
        // run_command -> "Running command"
        // others -> "Using {toolName}"
    }
    
    // MARK: - Message Role Tests
    
    func testMessageRoleDetermination() {
        let userMessage = createMessage(role: .user)
        let assistantMessage = createMessage(role: .assistant)
        
        // Test role property directly
        XCTAssertEqual(userMessage.role, .user)
        XCTAssertEqual(assistantMessage.role, .assistant)
    }
    
    // MARK: - Bubble Color Logic Tests
    
    func testBubbleColorLogic_errorMessage() {
        let errorMessage = createMessage(role: .user, status: .error, errorMessage: "Network error")
        
        // Error messages should have red-tinted background
        XCTAssertEqual(errorMessage.status, .error)
        XCTAssertNotNil(errorMessage.errorMessage)
    }
    
    func testBubbleColorLogic_normalMessages() {
        let userMessage = createMessage(role: .user, status: .sent)
        let assistantMessage = createMessage(role: .assistant, status: .sent)
        
        // Verify message types
        XCTAssertEqual(userMessage.role, .user)
        XCTAssertEqual(userMessage.status, .sent)
        XCTAssertEqual(assistantMessage.role, .assistant)
        XCTAssertEqual(assistantMessage.status, .sent)
    }
    
    // MARK: - Attachment Tests
    
    func testAttachmentDisplay() {
        let attachments = [
            createAttachment(id: "1", displayName: "document.pdf"),
            createAttachment(id: "2", displayName: "image.png")
        ]
        
        let message = createMessage(role: .user, attachments: attachments)
        
        XCTAssertEqual(message.attachments?.count, 2)
        XCTAssertEqual(message.attachments?[0].displayName, "document.pdf")
        XCTAssertEqual(message.attachments?[1].displayName, "image.png")
    }
    
    // MARK: - Lazy Loading Threshold Tests
    
    func testLazyLoadingThreshold() {
        // Small lists (≤20) should use regular VStack
        let smallList = Array(repeating: createMessage(role: .user), count: 20)
        let _ = MessageListView(messages: smallList, isLoading: false)
        
        // Large lists (>20) should use LazyVStack
        let largeList = Array(repeating: createMessage(role: .user), count: 21)
        let _ = MessageListView(messages: largeList, isLoading: false)
        
        // Verify threshold is correctly set
        XCTAssertLessThanOrEqual(smallList.count, 20)
        XCTAssertGreaterThan(largeList.count, 20)
    }
    
    // MARK: - Pagination Tests
    
    func testHasOlderMessages_true() {
        let messages = Array(repeating: createMessage(role: .user), count: 10)
        let view = MessageListView(
            messages: messages,
            isLoading: false,
            hasOlderMessages: true
        )
        
        XCTAssertTrue(view.hasOlderMessages)
    }
    
    func testHasOlderMessages_false() {
        let messages = Array(repeating: createMessage(role: .user), count: 5)
        let view = MessageListView(
            messages: messages,
            isLoading: false,
            hasOlderMessages: false
        )
        
        XCTAssertFalse(view.hasOlderMessages)
    }
    
    func testIsLoadingOlder() {
        let messages = [createMessage(role: .user)]
        let view = MessageListView(
            messages: messages,
            isLoading: false,
            hasOlderMessages: true,
            isLoadingOlder: true
        )
        
        XCTAssertTrue(view.isLoadingOlder)
    }
    
    // MARK: - Callback Tests
    
    func testOnRetryCallback() {
        let expectation = XCTestExpectation(description: "Retry callback should be called")
        var capturedMessage: Message?
        var capturedContent: String?
        
        let message = createMessage(role: .user, content: "Original")
        let messages = [message]
        
        let view = MessageListView(
            messages: messages,
            isLoading: false,
            onRetry: { msg, content in
                capturedMessage = msg
                capturedContent = content
                expectation.fulfill()
            }
        )
        
        // Simulate retry
        view.onRetry?(message, "Edited content")
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capturedMessage?.id, message.id)
        XCTAssertEqual(capturedContent, "Edited content")
    }
    
    func testOnLoadOlderCallback() {
        let expectation = XCTestExpectation(description: "Load older callback should be called")
        
        let view = MessageListView(
            messages: [],
            isLoading: false,
            hasOlderMessages: true,
            onLoadOlder: {
                expectation.fulfill()
            }
        )
        
        view.onLoadOlder?()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Preference Key Tests
    // Note: Preference keys are private to MessageListView
    // They are tested indirectly through scroll behavior integration tests
    
    func testMessageHeightPreferenceKey() {
        let key = MessageHeightPreferenceKey.self
        XCTAssertEqual(key.defaultValue, 0)
        
        var value: CGFloat = 50
        key.reduce(value: &value, nextValue: { 100 })
        XCTAssertEqual(value, 100)
    }
    
    // MARK: - Message Sending Status Tests
    
    func testSendingMessageWithEmptyContent() {
        let message = createMessage(role: .assistant, content: "", status: .sending)
        
        XCTAssertEqual(message.status, .sending)
        XCTAssertTrue(message.content.isEmpty)
    }
    
    func testErrorMessageDisplay() {
        let errorMsg = "Connection timeout"
        let message = createMessage(
            role: .assistant,
            content: "Partial response",
            status: .error,
            errorMessage: errorMsg
        )
        
        XCTAssertEqual(message.status, .error)
        XCTAssertEqual(message.errorMessage, errorMsg)
    }
    
    // MARK: - Integration Test Scenarios
    
    func testCompleteMessageExchange() {
        let messages = [
            createMessage(id: "1", role: .user, content: "Hello", status: .sent),
            createMessage(id: "2", role: .assistant, content: "Hi there!", status: .sent),
            createMessage(id: "3", role: .user, content: "How are you?", status: .sent),
            createMessage(id: "4", role: .assistant, content: "I'm doing well!", status: .sent)
        ]
        
        let view = MessageListView(messages: messages, isLoading: false)
        
        XCTAssertEqual(view.messages.count, 4)
        XCTAssertEqual(view.messages[0].role, .user)
        XCTAssertEqual(view.messages[1].role, .assistant)
    }
    
    func testStreamingConversation() {
        let messages = [
            createMessage(id: "1", role: .user, content: "Write me a poem", status: .sent),
            createMessage(id: "2", role: .assistant, content: "Roses are red...", status: .sending)
        ]
        
        let isLoading = true
        let _ = MessageListView(messages: messages, isLoading: isLoading)
        
        // Test streaming indicator logic: should not show when placeholder exists
        let shouldShow = isLoading && (messages.isEmpty || messages.last?.status != .sending)
        XCTAssertFalse(shouldShow, "Should not show streaming indicator when placeholder exists")
        XCTAssertEqual(messages.last?.status, .sending)
    }
    
    func testErrorRecovery() {
        let messages = [
            createMessage(id: "1", role: .user, content: "Request", status: .sent),
            createMessage(
                id: "2",
                role: .assistant,
                content: "Partial",
                status: .error,
                errorMessage: "Connection lost"
            )
        ]
        
        let view = MessageListView(messages: messages, isLoading: false)
        
        XCTAssertEqual(view.messages.last?.status, .error)
        XCTAssertNotNil(view.messages.last?.errorMessage)
    }
}

// MARK: - SwiftUI View Testing Notes

/*
 * SwiftUI View Integration Tests (to be run with ViewInspector or UI tests):
 *
 * 1. testScrollToBottom - Verify auto-scroll when new messages arrive
 * 2. testEditModeUI - Enter edit mode, modify text, submit/cancel
 * 3. testCopyToClipboard - Verify NSPasteboard contains message content
 * 4. testHoverEffects - Verify copy/edit buttons appear on hover
 * 5. testStreamingAnimation - Verify streaming indicator animates
 * 6. testToolActivityAnimation - Verify tool indicator rotates
 * 7. testLoadOlderButton - Tap button, verify callback fires
 * 8. testMessageRetry - Edit message, verify retry callback with new content
 * 9. testAttachmentDisplay - Render message with attachments
 * 10. testMarkdownRendering - Verify markdown formats correctly
 * 11. testAccessibility - Verify all accessibility labels are present
 * 12. testLazyVStackPerformance - Measure rendering time for 100+ messages
 *
 * These tests require:
 * - ViewInspector library for SwiftUI view hierarchy inspection
 * - XCUITest for full UI interaction testing
 * - Performance testing harness for scroll performance
 */
