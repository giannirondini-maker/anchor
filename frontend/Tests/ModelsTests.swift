/**
 * Model Tests
 *
 * Unit tests for data model decoding and initialization
 */

import XCTest
@testable import Anchor

final class ModelsTests: XCTestCase {
    
    // MARK: - Conversation Tests
    
    func testConversationDecoding() throws {
        let json = """
        {
            "id": "conv_123",
            "title": "Test Conversation",
            "createdAt": "2026-01-29T10:30:00.000Z",
            "updatedAt": "2026-01-29T11:00:00.000Z",
            "model": "claude-sonnet-4-20250514",
            "agent": null,
            "sessionId": "session_456",
            "tags": []
        }
        """.data(using: .utf8)!
        
        let conversation = try JSONDecoder().decode(Conversation.self, from: json)
        
        XCTAssertEqual(conversation.id, "conv_123")
        XCTAssertEqual(conversation.title, "Test Conversation")
        XCTAssertEqual(conversation.model, "claude-sonnet-4-20250514")
        XCTAssertNil(conversation.agent)
        XCTAssertEqual(conversation.sessionId, "session_456")
        XCTAssertTrue(conversation.tags.isEmpty)
    }
    
    func testConversationDecodingWithMissingOptionalFields() throws {
        let json = """
        {
            "id": "conv_123",
            "title": "Test",
            "createdAt": "2026-01-29T10:30:00.000Z",
            "updatedAt": "2026-01-29T10:30:00.000Z"
        }
        """.data(using: .utf8)!
        
        let conversation = try JSONDecoder().decode(Conversation.self, from: json)
        
        XCTAssertEqual(conversation.id, "conv_123")
        XCTAssertNil(conversation.model)
        XCTAssertNil(conversation.agent)
        XCTAssertNil(conversation.sessionId)
        XCTAssertTrue(conversation.tags.isEmpty)
    }
    
    func testConversationInitializer() {
        let conversation = Conversation(
            id: "conv_test",
            title: "My Chat",
            model: "gpt-5",
            agent: nil
        )
        
        XCTAssertEqual(conversation.id, "conv_test")
        XCTAssertEqual(conversation.title, "My Chat")
        XCTAssertEqual(conversation.model, "gpt-5")
    }
    
    func testConversationEquality() {
        let now = Date()
        let conv1 = Conversation(id: "conv_1", title: "Chat 1", createdAt: now, updatedAt: now)
        let conv2 = Conversation(id: "conv_1", title: "Chat 1", createdAt: now, updatedAt: now)
        let conv3 = Conversation(id: "conv_2", title: "Chat 2", createdAt: now, updatedAt: now)

        XCTAssertEqual(conv1, conv2)
        XCTAssertNotEqual(conv1, conv3)
    }
    
    // MARK: - Message Tests
    
    func testMessageDecoding() throws {
        let json = """
        {
            "id": "msg_123",
            "conversationId": "conv_456",
            "role": "assistant",
            "content": "Hello! How can I help you?",
            "createdAt": "2026-01-29T10:30:00.000Z",
            "status": "sent",
            "errorMessage": null
        }
        """.data(using: .utf8)!
        
        let message = try JSONDecoder().decode(Message.self, from: json)
        
        XCTAssertEqual(message.id, "msg_123")
        XCTAssertEqual(message.conversationId, "conv_456")
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Hello! How can I help you?")
        XCTAssertEqual(message.status, .sent)
        XCTAssertNil(message.errorMessage)
    }
    
    func testMessageWithError() throws {
        let json = """
        {
            "id": "msg_123",
            "conversationId": "conv_456",
            "role": "assistant",
            "content": "",
            "createdAt": "2026-01-29T10:30:00.000Z",
            "status": "error",
            "errorMessage": "Rate limit exceeded"
        }
        """.data(using: .utf8)!
        
        let message = try JSONDecoder().decode(Message.self, from: json)
        
        XCTAssertEqual(message.status, .error)
        XCTAssertEqual(message.errorMessage, "Rate limit exceeded")
    }
    
    func testMessageRoles() {
        XCTAssertEqual(MessageRole.user.rawValue, "user")
        XCTAssertEqual(MessageRole.assistant.rawValue, "assistant")
        XCTAssertEqual(MessageRole.system.rawValue, "system")
    }
    
    func testMessageStatuses() {
        XCTAssertEqual(MessageStatus.sending.rawValue, "sending")
        XCTAssertEqual(MessageStatus.sent.rawValue, "sent")
        XCTAssertEqual(MessageStatus.error.rawValue, "error")
    }
    
    // MARK: - ModelInfo Tests
    
    func testModelInfoDecoding() throws {
        let json = """
        {
            "id": "claude-sonnet-4-20250514",
            "name": "Claude Sonnet 4",
            "multiplier": 1.5,
            "supportsVision": true,
            "maxContextTokens": 200000,
            "enabled": true
        }
        """.data(using: .utf8)!
        
        let model = try JSONDecoder().decode(ModelInfo.self, from: json)
        
        XCTAssertEqual(model.id, "claude-sonnet-4-20250514")
        XCTAssertEqual(model.name, "Claude Sonnet 4")
        XCTAssertEqual(model.multiplier, 1.5)
        XCTAssertTrue(model.supportsVision)
        XCTAssertEqual(model.maxContextTokens, 200000)
        XCTAssertTrue(model.enabled)
    }
    
    func testModelInfoWithDefaults() throws {
        let json = """
        {
            "id": "simple-model",
            "name": "Simple Model"
        }
        """.data(using: .utf8)!
        
        let model = try JSONDecoder().decode(ModelInfo.self, from: json)
        
        XCTAssertEqual(model.multiplier, 1.0)
        XCTAssertFalse(model.supportsVision)
        XCTAssertEqual(model.maxContextTokens, 0)
        XCTAssertTrue(model.enabled)
    }
    
    // MARK: - Tag Tests
    
    func testTagDecoding() throws {
        let json = """
        {
            "id": 1,
            "name": "Important",
            "color": "#FF0000"
        }
        """.data(using: .utf8)!
        
        let tag = try JSONDecoder().decode(Tag.self, from: json)
        
        XCTAssertEqual(tag.id, 1)
        XCTAssertEqual(tag.name, "Important")
        XCTAssertEqual(tag.color, "#FF0000")
    }
    
    func testTagDecodingWithNullColor() throws {
        let json = """
        {
            "id": 2,
            "name": "Work",
            "color": null
        }
        """.data(using: .utf8)!
        
        let tag = try JSONDecoder().decode(Tag.self, from: json)
        
        XCTAssertEqual(tag.id, 2)
        XCTAssertEqual(tag.name, "Work")
        XCTAssertNil(tag.color)
    }
    
    func testTagEquality() {
        let tag1 = Tag(id: 1, name: "Test", color: "#FF0000")
        let tag2 = Tag(id: 1, name: "Test", color: "#FF0000")
        let tag3 = Tag(id: 2, name: "Other", color: nil)
        
        XCTAssertEqual(tag1, tag2)
        XCTAssertNotEqual(tag1, tag3)
    }
    
    func testConversationDecodingWithTags() throws {
        let json = """
        {
            "id": "conv_123",
            "title": "Tagged Conversation",
            "createdAt": "2026-01-29T10:30:00.000Z",
            "updatedAt": "2026-01-29T11:00:00.000Z",
            "model": "claude-sonnet-4",
            "tags": [
                {"id": 1, "name": "Important", "color": "#FF0000"},
                {"id": 2, "name": "Work", "color": null}
            ]
        }
        """.data(using: .utf8)!
        
        let conversation = try JSONDecoder().decode(Conversation.self, from: json)
        
        XCTAssertEqual(conversation.id, "conv_123")
        XCTAssertEqual(conversation.tags.count, 2)
        XCTAssertEqual(conversation.tags[0].name, "Important")
        XCTAssertEqual(conversation.tags[0].color, "#FF0000")
        XCTAssertEqual(conversation.tags[1].name, "Work")
        XCTAssertNil(conversation.tags[1].color)
    }
    
    // MARK: - Response Types Tests
    
    func testConversationsResponseDecoding() throws {
        let json = """
        {
            "conversations": [
                {
                    "id": "conv_1",
                    "title": "Chat 1",
                    "createdAt": "2026-01-29T10:30:00.000Z",
                    "updatedAt": "2026-01-29T10:30:00.000Z",
                    "tags": []
                }
            ]
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(ConversationsResponse.self, from: json)
        
        XCTAssertEqual(response.conversations.count, 1)
        XCTAssertEqual(response.conversations[0].id, "conv_1")
    }
    
    func testHealthResponseDecoding() throws {
        let json = """
        {
            "status": "healthy",
            "version": "1.0.0",
            "sdk": {
                "connected": true,
                "authenticated": true
            }
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(HealthResponse.self, from: json)
        
        XCTAssertEqual(response.status, "healthy")
        XCTAssertEqual(response.version, "1.0.0")
        XCTAssertTrue(response.sdk.connected)
        XCTAssertTrue(response.sdk.authenticated)
    }
}
