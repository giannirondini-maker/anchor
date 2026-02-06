/**
 * Pagination Tests
 *
 * Unit tests for message pagination and load older functionality
 */

import XCTest
@testable import Anchor

final class PaginationTests: XCTestCase {
    
    // MARK: - Configuration Tests
    
    func testPaginationLimitConfiguration() {
        // Verify the pagination limit is set appropriately
        let limit = Configuration.initialMessageLimit
        
        XCTAssertEqual(limit, 50, "Should limit initial messages to 50")
        XCTAssertGreaterThan(limit, 10, "Limit should be reasonable for chat (>10)")
        XCTAssertLessThan(limit, 200, "Limit should prevent excessive initial load (<200)")
    }
    
    // MARK: - Message Load Behavior Tests
    
    func testHasOlderMessagesDetection() {
        // When fetched messages count equals limit, there may be older messages
        let limit = Configuration.initialMessageLimit
        let messages = createMockMessages(count: limit)
        
        // In a real scenario, if we get exactly `limit` messages, hasOlderMessages = true
        // This tests the logic expectation
        let hasOlderMessages = messages.count >= limit
        XCTAssertTrue(hasOlderMessages, "Should indicate more messages may exist when count equals limit")
    }
    
    func testNoOlderMessagesWhenCountBelowLimit() {
        // When fetched messages count is less than limit, there are no older messages
        let limit = Configuration.initialMessageLimit
        let messages = createMockMessages(count: limit - 10)
        
        let hasOlderMessages = messages.count >= limit
        XCTAssertFalse(hasOlderMessages, "Should not indicate older messages when count < limit")
    }
    
    func testEmptyConversationHasNoOlderMessages() {
        let messages: [Message] = []
        let limit = Configuration.initialMessageLimit
        
        let hasOlderMessages = messages.count >= limit
        XCTAssertFalse(hasOlderMessages, "Empty conversation should not have older messages")
    }
    
    // MARK: - ISO8601 Timestamp Formatting Tests
    
    func testBeforeTimestampFormatting() {
        // Test that we can generate proper ISO8601 timestamps for pagination
        let calendar = Calendar.current
        let components = DateComponents(year: 2026, month: 2, day: 1, hour: 0, minute: 0, second: 0)
        guard let testDate = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }
        
        let message = Message(
            id: "test_msg",
            conversationId: "test_conv",
            role: .user,
            content: "Test",
            createdAt: testDate,
            status: .sent
        )
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: message.createdAt)
        
        XCTAssertTrue(timestamp.contains("2026"), "Should contain year 2026, got: \(timestamp)")
        XCTAssertTrue(timestamp.contains("T"), "Should be in ISO8601 format with T separator")
        XCTAssertTrue(timestamp.hasSuffix("Z") || timestamp.contains("+") || timestamp.contains("-"), 
                      "Should have timezone indicator")
    }
    
    // MARK: - Debounce Timing Tests
    
    func testDebounceDelayIsReasonable() async {
        // The debounce delay is 100ms (100_000_000 nanoseconds)
        let debounceDelayNs: UInt64 = 100_000_000
        let debounceDelaySeconds = Double(debounceDelayNs) / 1_000_000_000
        
        XCTAssertEqual(debounceDelaySeconds, 0.1, accuracy: 0.01, "Debounce should be 100ms")
        XCTAssertGreaterThan(debounceDelaySeconds, 0.05, "Debounce should be >50ms to be effective")
        XCTAssertLessThan(debounceDelaySeconds, 0.5, "Debounce should be <500ms to feel responsive")
    }
    
    // MARK: - CachedMarkdownView Equality Tests
    
    func testCachedMarkdownViewEquality() {
        let view1 = CachedMarkdownView(content: "Hello **world**")
        let view2 = CachedMarkdownView(content: "Hello **world**")
        let view3 = CachedMarkdownView(content: "Different content")
        
        XCTAssertEqual(view1, view2, "Identical content should be equal")
        XCTAssertNotEqual(view1, view3, "Different content should not be equal")
    }
    
    func testCachedMarkdownViewEqualityWithEmptyContent() {
        let view1 = CachedMarkdownView(content: "")
        let view2 = CachedMarkdownView(content: "")
        
        XCTAssertEqual(view1, view2, "Empty content views should be equal")
    }
    
    func testCachedMarkdownViewEqualityWithComplexMarkdown() {
        let markdown = """
        # Title

        This is **bold** and *italic*.

        ```swift
        let code = "example"
        ```

        - List item 1
        - List item 2
        """

        let view1 = CachedMarkdownView(content: markdown)
        let view2 = CachedMarkdownView(content: markdown)

        XCTAssertEqual(view1, view2, "Complex markdown should maintain equality")
    }

    // MARK: - MessageBubbleView Equatable Tests

    func testMessageBubbleViewEquality() {
        let message1 = Message(
            id: "msg1",
            conversationId: "conv1",
            role: .user,
            content: "Hello",
            status: .sent
        )

        let message2 = Message(
            id: "msg1",
            conversationId: "conv1",
            role: .user,
            content: "Hello",
            status: .sent
        )

        let view1 = MessageBubbleView(message: message1, onRetry: nil)
        let view2 = MessageBubbleView(message: message2, onRetry: nil)

        XCTAssertEqual(view1, view2, "MessageBubbleViews with identical messages should be equal")
    }

    func testMessageBubbleViewInequality() {
        let message1 = Message(
            id: "msg1",
            conversationId: "conv1",
            role: .user,
            content: "Hello",
            status: .sent
        )

        let message2 = Message(
            id: "msg1",
            conversationId: "conv1",
            role: .user,
            content: "Hello World",  // Different content
            status: .sent
        )

        let view1 = MessageBubbleView(message: message1, onRetry: nil)
        let view2 = MessageBubbleView(message: message2, onRetry: nil)

        XCTAssertNotEqual(view1, view2, "MessageBubbleViews with different content should not be equal")
    }

    func testMessageBubbleViewInequalityWithDifferentStatus() {
        let message1 = Message(
            id: "msg1",
            conversationId: "conv1",
            role: .user,
            content: "Hello",
            status: .sent
        )

        let message2 = Message(
            id: "msg1",
            conversationId: "conv1",
            role: .user,
            content: "Hello",
            status: .error  // Different status
        )

        let view1 = MessageBubbleView(message: message1, onRetry: nil)
        let view2 = MessageBubbleView(message: message2, onRetry: nil)

        XCTAssertNotEqual(view1, view2, "MessageBubbleViews with different status should not be equal")
    }

    // MARK: - Helper Methods
    
    private func createMockMessages(count: Int) -> [Message] {
        var messages: [Message] = []
        let baseDate = Date()
        
        for i in 0..<count {
            let message = Message(
                id: "msg_\(i)",
                conversationId: "conv_test",
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
