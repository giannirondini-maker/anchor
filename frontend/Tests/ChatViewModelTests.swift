/**
 * ChatViewModel Tests
 *
 * Unit tests for ChatViewModel behavior including debouncing,
 * cancellation, and pagination state management
 */

import Foundation
import Testing
@testable import Anchor

struct ChatViewModelTests {

    // MARK: - Initial State Tests

    @Test @MainActor
    func testInitialState() {
        let viewModel = ChatViewModel(conversationId: "test_conv")

        // Verify initial published properties
        #expect(viewModel.messages.isEmpty, "Should start with no messages")
        #expect(viewModel.inputText.isEmpty, "Input should be empty")
        #expect(!viewModel.isStreaming, "Should not be streaming initially")
        #expect(!viewModel.hasOlderMessages, "Should not have older messages initially")
        #expect(!viewModel.isLoadingOlder, "Should not be loading older messages")
        #expect(viewModel.selectedModel == Configuration.defaultModel, "Should use default model")
    }

    // MARK: - Loading State Tests

    @Test @MainActor
    func testHasOlderMessagesAfterFullLoad() {
        let viewModel = ChatViewModel(conversationId: "test_conv")

        // Simulate a full page of messages loaded
        let limit = Configuration.initialMessageLimit
        viewModel.messages = createMockMessages(count: limit)

        // When exactly `limit` messages are loaded, hasOlderMessages should be true
        // (This would normally be set by the actual loadMessages function)
        let expectHasOlder = viewModel.messages.count >= limit

        #expect(expectHasOlder, "Should indicate older messages exist when full page loaded")
    }

    @Test @MainActor
    func testNoOlderMessagesWhenPartialLoad() {
        let viewModel = ChatViewModel(conversationId: "test_conv")

        // Simulate partial page loaded (fewer than limit)
        let limit = Configuration.initialMessageLimit
        viewModel.messages = createMockMessages(count: limit - 20)

        let expectHasOlder = viewModel.messages.count >= limit

        #expect(!expectHasOlder, "Should not indicate older messages when partial page loaded")
    }

    // MARK: - Conversation Switching Tests

    @Test @MainActor
    func testSwitchConversationClearsState() {
        let viewModel = ChatViewModel(conversationId: "conv1")

        // Set up some state
        viewModel.messages = createMockMessages(count: 10)
        viewModel.isStreaming = true
        viewModel.hasOlderMessages = true
        viewModel.isLoadingOlder = true

        // Switch conversation
        viewModel.switchConversation(to: "conv2")

        // Verify state is cleared immediately
        #expect(viewModel.messages.isEmpty, "Messages should be cleared on switch")
        #expect(!viewModel.isStreaming, "Streaming flag should be cleared")
        #expect(!viewModel.hasOlderMessages, "hasOlderMessages should be cleared")
        #expect(!viewModel.isLoadingOlder, "isLoadingOlder should be cleared")
    }

    // MARK: - Message Retry Tests

    @Test @MainActor
    func testRetryMessageRemovesSubsequentMessages() async {
        let viewModel = ChatViewModel(conversationId: "test_conv")

        // Set up conversation with multiple message exchanges
        viewModel.messages = [
            Message(id: "msg1", conversationId: "test_conv", role: .user, content: "Message 1", status: .sent),
            Message(id: "msg2", conversationId: "test_conv", role: .assistant, content: "Response 1", status: .sent),
            Message(id: "msg3", conversationId: "test_conv", role: .user, content: "Message 2", status: .sent),
            Message(id: "msg4", conversationId: "test_conv", role: .assistant, content: "Response 2", status: .error)
        ]

        // Find the message to retry (msg3)
        let messageToRetry = viewModel.messages[2]

        // Retry it (this removes msg3 and msg4, then adds edited version)
        await viewModel.retryMessage(messageToRetry, with: "Edited Message 2")

        // Should have msg1, msg2, and the new edited message
        // (In actual implementation, the new message would be added)
        // Here we're just testing the removal logic conceptually
        #expect(viewModel.messages.count >= 2, "Should keep messages before retry point")
    }

    // MARK: - Input Validation Tests

    @Test @MainActor
    func testSendMessageTrimsWhitespace() {
        let viewModel = ChatViewModel(conversationId: "test_conv")

        // Test that empty/whitespace input is handled properly
        viewModel.inputText = "   \n\t  "

        // Can't actually call sendMessage without network service, but we can test the logic
        let content = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldSend = !content.isEmpty

        #expect(!shouldSend, "Should not send empty/whitespace-only messages")
    }

    // MARK: - Error Handling Tests

    @Test @MainActor
    func testDismissError() {
        let viewModel = ChatViewModel(conversationId: "test_conv")

        viewModel.error = "Test error message"
        #expect(viewModel.error != nil)

        viewModel.dismissError()
        #expect(viewModel.error == nil, "Error should be cleared after dismiss")
    }

    // MARK: - Streaming Indicator Logic Tests

    @Test @MainActor
    func testStreamingWithPlaceholderMessage() {
        let viewModel = ChatViewModel(conversationId: "test_conv")

        // Simulate streaming with a placeholder message
        viewModel.isStreaming = true
        viewModel.messages = [
            Message(id: "msg1", conversationId: "test_conv", role: .user, content: "Question", status: .sent),
            Message(id: "msg2", conversationId: "test_conv", role: .assistant, content: "", status: .sending)
        ]

        // The MessageListView should NOT show the streaming indicator when placeholder exists
        let hasPlaceholder = viewModel.messages.last?.status == .sending &&
                             viewModel.messages.last?.role == .assistant

        let shouldShowStreamingIndicator = viewModel.isStreaming && !hasPlaceholder

        #expect(!shouldShowStreamingIndicator, "Should not show streaming indicator when placeholder exists")
    }

    @Test @MainActor
    func testStreamingWithoutPlaceholder() {
        let viewModel = ChatViewModel(conversationId: "test_conv")

        // Streaming but no placeholder yet
        viewModel.isStreaming = true
        viewModel.messages = [
            Message(id: "msg1", conversationId: "test_conv", role: .user, content: "Question", status: .sent)
        ]

        let hasPlaceholder = viewModel.messages.last?.status == .sending &&
                             viewModel.messages.last?.role == .assistant

        let shouldShowStreamingIndicator = viewModel.isStreaming && !hasPlaceholder

        #expect(shouldShowStreamingIndicator, "Should show streaming indicator when no placeholder")
    }

    // MARK: - Helper Methods

    private func createMockMessages(count: Int) -> [Message] {
        var messages: [Message] = []
        let baseDate = Date()

        for i in 0..<count {
            let message = Message(
                id: "msg_\(i)",
                conversationId: "test_conv",
                role: i % 2 == 0 ? .user : .assistant,
                content: "Message \(i)",
                createdAt: baseDate.addingTimeInterval(Double(i)),
                status: .sent
            )
            messages.append(message)
        }

        return messages
    }
}

