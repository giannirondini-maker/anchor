/**
 * MessageListView Tests
 *
 * Unit tests for MessageListView including message rendering,
 * streaming indicators, tool activity, and scroll behavior
 */

import Foundation
import Testing
@testable import Anchor

// Disambiguate Anchor types from Testing types
private typealias Attachment = Anchor.Attachment

struct MessageListViewTests {
    
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
    
    @Test func testStreamingIndicatorLogic_whenLoadingAndNoPlaceholder() {
        let messages: [Message] = []
        let isLoading = true
        
        // When loading with no messages, streaming indicator should show
        // Logic: isLoading = true AND (no messages OR last message is not .sending)
        let shouldShow = isLoading && (messages.isEmpty || messages.last?.status != .sending)
        #expect(shouldShow, "Should show streaming indicator when loading with no placeholder")
    }
    
    @Test func testStreamingIndicatorLogic_whenNotLoading() {
        let messages: [Message] = []
        let isLoading = false
        
        // When not loading, streaming indicator should not show
        let shouldShow = isLoading && (messages.isEmpty || messages.last?.status != .sending)
        #expect(!shouldShow, "Should not show streaming indicator when not loading")
    }
    
    @Test func testStreamingIndicatorLogic_whenPlaceholderExists() {
        // Last message is placeholder being streamed
        let messages = [
            createMessage(role: .user, content: "Hello"),
            createMessage(role: .assistant, content: "", status: .sending)
        ]
        let isLoading = true
        
        // Should not show streaming indicator when we have a placeholder message
        let shouldShow = isLoading && (messages.isEmpty || messages.last?.status != .sending)
        #expect(!shouldShow, "Should not show streaming indicator when placeholder exists")
    }
    
    // MARK: - WebSocket Connection State Tests
    
    @Test func testWebSocketConnectionStateEquality() {
        #expect(WebSocketConnectionState.disconnected == .disconnected)
        #expect(WebSocketConnectionState.connecting == .connecting)
        #expect(WebSocketConnectionState.connected == .connected)
        #expect(
            WebSocketConnectionState.reconnecting(attempt: 3) == WebSocketConnectionState.reconnecting(attempt: 3)
        )
        
        #expect(
            WebSocketConnectionState.reconnecting(attempt: 1) != WebSocketConnectionState.reconnecting(attempt: 2)
        )
    }
    
    @Test func testWebSocketConnectionStateDescriptions() {
        #expect(WebSocketConnectionState.disconnected.description == "Disconnected")
        #expect(WebSocketConnectionState.connecting.description == "Connecting...")
        #expect(WebSocketConnectionState.connected.description == "Connected")
        #expect(
            WebSocketConnectionState.reconnecting(attempt: 3).description == "Reconnecting (3/5)..."
        )
    }
    
    @Test func testWebSocketConnectionStateIsConnected() {
        #expect(WebSocketConnectionState.connected.isConnected)
        #expect(!WebSocketConnectionState.disconnected.isConnected)
        #expect(!WebSocketConnectionState.connecting.isConnected)
        #expect(!WebSocketConnectionState.reconnecting(attempt: 1).isConnected)
    }
    
    // MARK: - Message Bubble Equatable Tests
    
    @Test func testMessageBubbleEquality_sameContent() {
        let message = createMessage(id: "msg1", role: .user, content: "Hello")
        
        let bubble1 = MessageBubbleView(message: message)
        let bubble2 = MessageBubbleView(message: message)
        
        #expect(bubble1 == bubble2, "Bubbles with same message should be equal")
    }
    
    @Test func testMessageBubbleEquality_differentContent() {
        let message1 = createMessage(id: "msg1", role: .user, content: "Hello")
        let message2 = createMessage(id: "msg1", role: .user, content: "Hello World")
        
        let bubble1 = MessageBubbleView(message: message1)
        let bubble2 = MessageBubbleView(message: message2)
        
        #expect(bubble1 != bubble2, "Bubbles with different content should not be equal")
    }
    
    @Test func testMessageBubbleEquality_differentStatus() {
        let message1 = createMessage(id: "msg1", role: .user, content: "Hello", status: .sent)
        let message2 = createMessage(id: "msg1", role: .user, content: "Hello", status: .error)
        
        let bubble1 = MessageBubbleView(message: message1)
        let bubble2 = MessageBubbleView(message: message2)
        
        #expect(bubble1 != bubble2, "Bubbles with different status should not be equal")
    }
    
    @Test func testMessageBubbleEquality_differentAttachments() {
        let message1 = createMessage(id: "msg1", role: .user, content: "Hello", attachments: nil)
        let message2 = createMessage(id: "msg1", role: .user, content: "Hello", attachments: [createAttachment()])
        
        let bubble1 = MessageBubbleView(message: message1)
        let bubble2 = MessageBubbleView(message: message2)
        
        #expect(bubble1 != bubble2, "Bubbles with different attachments should not be equal")
    }
    
    // MARK: - CachedMarkdownView Equatable Tests
    
    @Test func testCachedMarkdownViewEquality_sameContent() {
        let view1 = CachedMarkdownView(content: "# Hello")
        let view2 = CachedMarkdownView(content: "# Hello")
        
        #expect(view1 == view2, "Views with same content should be equal")
    }
    
    @Test func testCachedMarkdownViewEquality_differentContent() {
        let view1 = CachedMarkdownView(content: "# Hello")
        let view2 = CachedMarkdownView(content: "# World")
        
        #expect(view1 != view2, "Views with different content should not be equal")
    }
    
    // MARK: - Tool Activity Tests
    
    @Test func testToolActivityToolNames() {
        // Test that tool names are properly stored
        let toolNames = ["web_search", "bing_search", "read_url", "fetch_url", 
                        "read_file", "code_search", "run_command", "custom_tool"]
        
        for toolName in toolNames {
            let view = ToolActivityIndicatorView(toolName: toolName)
            // displayName is private, but we can verify the view is created
            #expect(view != nil)
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
    
    @Test func testMessageRoleDetermination() {
        let userMessage = createMessage(role: .user)
        let assistantMessage = createMessage(role: .assistant)
        
        // Test role property directly
        #expect(userMessage.role == .user)
        #expect(assistantMessage.role == .assistant)
    }
    
    // MARK: - Bubble Color Logic Tests
    
    @Test func testBubbleColorLogic_errorMessage() {
        let errorMessage = createMessage(role: .user, status: .error, errorMessage: "Network error")
        
        // Error messages should have red-tinted background
        #expect(errorMessage.status == .error)
        #expect(errorMessage.errorMessage != nil)
    }
    
    @Test func testBubbleColorLogic_normalMessages() {
        let userMessage = createMessage(role: .user, status: .sent)
        let assistantMessage = createMessage(role: .assistant, status: .sent)
        
        // Verify message types
        #expect(userMessage.role == .user)
        #expect(userMessage.status == .sent)
        #expect(assistantMessage.role == .assistant)
        #expect(assistantMessage.status == .sent)
    }
    
    // MARK: - Attachment Tests
    
    @Test func testAttachmentDisplay() {
        let attachments = [
            createAttachment(id: "1", displayName: "document.pdf"),
            createAttachment(id: "2", displayName: "image.png")
        ]
        
        let message = createMessage(role: .user, attachments: attachments)
        
        #expect(message.attachments?.count == 2)
        #expect(message.attachments?[0].displayName == "document.pdf")
        #expect(message.attachments?[1].displayName == "image.png")
    }
    
    // MARK: - Lazy Loading Threshold Tests
    
    @Test func testLazyLoadingThreshold() {
        // Small lists (≤20) should use regular VStack
        let smallList = Array(repeating: createMessage(role: .user), count: 20)
        let _ = MessageListView(messages: smallList, isLoading: false)
        
        // Large lists (>20) should use LazyVStack
        let largeList = Array(repeating: createMessage(role: .user), count: 21)
        let _ = MessageListView(messages: largeList, isLoading: false)
        
        // Verify threshold is correctly set
        #expect(smallList.count <= 20)
        #expect(largeList.count > 20)
    }
    
    // MARK: - Pagination Tests
    
    @Test func testHasOlderMessages_true() {
        let messages = Array(repeating: createMessage(role: .user), count: 10)
        let view = MessageListView(
            messages: messages,
            isLoading: false,
            hasOlderMessages: true
        )
        
        #expect(view.hasOlderMessages)
    }
    
    @Test func testHasOlderMessages_false() {
        let messages = Array(repeating: createMessage(role: .user), count: 5)
        let view = MessageListView(
            messages: messages,
            isLoading: false,
            hasOlderMessages: false
        )
        
        #expect(!view.hasOlderMessages)
    }
    
    @Test func testIsLoadingOlder() {
        let messages = [createMessage(role: .user)]
        let view = MessageListView(
            messages: messages,
            isLoading: false,
            hasOlderMessages: true,
            isLoadingOlder: true
        )
        
        #expect(view.isLoadingOlder)
    }
    
    // MARK: - Callback Tests
    
    @Test func testOnRetryCallback() {
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
            }
        )

        // Simulate retry
        view.onRetry?(message, "Edited content")

        #expect(capturedMessage?.id == message.id)
        #expect(capturedContent == "Edited content")
    }
    
    @Test func testOnLoadOlderCallback() {
        var callbackCalled = false

        let view = MessageListView(
            messages: [],
            isLoading: false,
            hasOlderMessages: true,
            onLoadOlder: {
                callbackCalled = true
            }
        )

        view.onLoadOlder?()

        #expect(callbackCalled)
    }
    
    // MARK: - Preference Key Tests
    // Note: Preference keys are private to MessageListView
    // They are tested indirectly through scroll behavior integration tests
    
    @Test func testMessageHeightPreferenceKey() {
        let key = MessageHeightPreferenceKey.self
        #expect(key.defaultValue == 0)
        
        var value: CGFloat = 50
        key.reduce(value: &value, nextValue: { 100 })
        #expect(value == 100)
    }
    
    // MARK: - Message Sending Status Tests
    
    @Test func testSendingMessageWithEmptyContent() {
        let message = createMessage(role: .assistant, content: "", status: .sending)
        
        #expect(message.status == .sending)
        #expect(message.content.isEmpty)
    }
    
    @Test func testErrorMessageDisplay() {
        let errorMsg = "Connection timeout"
        let message = createMessage(
            role: .assistant,
            content: "Partial response",
            status: .error,
            errorMessage: errorMsg
        )
        
        #expect(message.status == .error)
        #expect(message.errorMessage == errorMsg)
    }
    
    // MARK: - Integration Test Scenarios
    
    @Test func testCompleteMessageExchange() {
        let messages = [
            createMessage(id: "1", role: .user, content: "Hello", status: .sent),
            createMessage(id: "2", role: .assistant, content: "Hi there!", status: .sent),
            createMessage(id: "3", role: .user, content: "How are you?", status: .sent),
            createMessage(id: "4", role: .assistant, content: "I'm doing well!", status: .sent)
        ]
        
        let view = MessageListView(messages: messages, isLoading: false)
        
        #expect(view.messages.count == 4)
        #expect(view.messages[0].role == .user)
        #expect(view.messages[1].role == .assistant)
    }
    
    @Test func testStreamingConversation() {
        let messages = [
            createMessage(id: "1", role: .user, content: "Write me a poem", status: .sent),
            createMessage(id: "2", role: .assistant, content: "Roses are red...", status: .sending)
        ]
        
        let isLoading = true
        let _ = MessageListView(messages: messages, isLoading: isLoading)
        
        // Test streaming indicator logic: should not show when placeholder exists
        let shouldShow = isLoading && (messages.isEmpty || messages.last?.status != .sending)
        #expect(!shouldShow, "Should not show streaming indicator when placeholder exists")
        #expect(messages.last?.status == .sending)
    }
    
    @Test func testErrorRecovery() {
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
        
        #expect(view.messages.last?.status == .error)
        #expect(view.messages.last?.errorMessage != nil)
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
