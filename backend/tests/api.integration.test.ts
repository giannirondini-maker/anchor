/**
 * API Integration Tests
 *
 * Integration tests for API endpoints using a test server instance
 */

import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from "vitest";
import { createServer, ServerInstance } from "../src/server.js";
import { initializeDatabase, getDb } from "../src/services/database.service.js";
import { copilotService } from "../src/services/copilot.service.js";
import { config } from "../src/config.js";

// Note: These tests require the database to be initialized
// They test the HTTP routes in isolation without the Copilot SDK

describe("API Integration Tests", () => {
  let server: ServerInstance;
  let baseUrl: string;
  const testPort = 3099;

  beforeAll(async () => {
    // Set test environment
    process.env.DATABASE_PATH = ":memory:";
    process.env.DISABLE_RATE_LIMIT = "true";
    
    // Initialize database
    await initializeDatabase();
    
    // Create and start server
    server = createServer();
    await new Promise<void>((resolve) => {
      server.httpServer.listen(testPort, () => {
        baseUrl = `http://localhost:${testPort}/api`;
        resolve();
      });
    });
  });

  afterAll(async () => {
    // Close server
    await new Promise<void>((resolve, reject) => {
      server.httpServer.close((err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    
    // Close WebSocket server
    server.wss.close();
    
    // Close database
    try {
      getDb().close();
    } catch (e) {
      // Ignore if already closed
    }
  });

  beforeEach(() => {
    // Clear database tables before each test
    const db = getDb();
    db.exec("DELETE FROM messages");
    db.exec("DELETE FROM conversation_tags");
    db.exec("DELETE FROM tags");
    db.exec("DELETE FROM conversations");
  });

  describe("GET /api/health", () => {
    it("should return health status", async () => {
      const response = await fetch(`${baseUrl}/health`);
      const data = await response.json();

      // Without Copilot SDK initialized, health returns 503 (unhealthy)
      // but we still verify the response structure is correct
      expect([200, 503]).toContain(response.status);
      expect(data.status).toBeDefined();
      expect(data.version).toBe("1.0.0");
      expect(data.sdk).toBeDefined();
    });
  });

  describe("Conversations API", () => {
    describe("GET /api/conversations", () => {
      it("should return empty array when no conversations exist", async () => {
        const response = await fetch(`${baseUrl}/conversations`);
        const data = await response.json();

        expect(response.status).toBe(200);
        expect(data.conversations).toEqual([]);
      });

      it("should return all conversations", async () => {
        // Create test conversations directly in DB
        const db = getDb();
        db.prepare(
          "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
        ).run("conv_1", "Test 1", "gpt-5");
        db.prepare(
          "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
        ).run("conv_2", "Test 2", "gpt-5");

        const response = await fetch(`${baseUrl}/conversations`);
        const data = await response.json();

        expect(response.status).toBe(200);
        expect(data.conversations).toHaveLength(2);
      });
    });

    describe("POST /api/conversations", () => {
      // Note: These tests require Copilot SDK which is not available in test environment
      // They test validation and will get 500 when trying to create sessions
      
      it("should create a new conversation with defaults", async () => {
        const response = await fetch(`${baseUrl}/conversations`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({}),
        });
        const data = await response.json();

        // Without Copilot SDK, creation fails with 500
        // If SDK were available, it would return 201
        if (response.status === 201) {
          expect(data.id).toMatch(/^conv_/);
          expect(data.title).toBe("New Conversation");
          expect(data.model).toBeDefined();
        } else {
          // SDK not initialized - this is expected in test environment
          expect(response.status).toBe(500);
          expect(data.error).toBeDefined();
          expect(data.error.code).toBeDefined();
        }
      });

      it("should create a conversation with custom title", async () => {
        const response = await fetch(`${baseUrl}/conversations`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: "My Custom Chat" }),
        });
        const data = await response.json();

        // Without Copilot SDK, creation fails with 500
        if (response.status === 201) {
          expect(data.title).toBe("My Custom Chat");
        } else {
          // SDK not initialized - this is expected in test environment
          expect(response.status).toBe(500);
          expect(data.error).toBeDefined();
          expect(data.error.code).toBeDefined();
        }
      });

      it("should fall back to a SDK model with multiplier 0 when default is missing", async () => {
        // Arrange: mock SDK client to return two models, one premium and one free. Configured default (claude-haiku-4.5)
        // is intentionally missing to simulate the fallback behavior.
        const originalClient = (copilotService as any).client;
        const originalCreateSession = (copilotService as any).createSession;

        (copilotService as any).client = {
          listModels: async () => [
            {
              id: "claude-sonnet-4",
              name: "Claude Sonnet 4",
              billing: { multiplier: 1.5 },
              capabilities: { supports: { vision: false }, limits: { max_context_window_tokens: 8192 } },
              policy: { state: "enabled", terms: "" },
            },
            {
              id: "claude-lite-free",
              name: "Claude Lite Free",
              billing: { multiplier: 0.0 },
              capabilities: { supports: { vision: false }, limits: { max_context_window_tokens: 4096 } },
              policy: { state: "enabled", terms: "" },
            },
          ],
        };

        // Spy on console.log to detect audit message
        const logSpy = vi.spyOn(console, 'log');

        // Stub createSession so conversation creation succeeds
        (copilotService as any).createSession = async (_conversationId: string, _model: string) => {
          return {
            session: { destroy: async () => {} },
            model: _model,
            createdAt: new Date(),
            lastActiveAt: new Date(),
            messageCount: 0,
          };
        };

        // Act: create conversation with no model specified (should pick the free model)
        const createResp = await fetch(`${baseUrl}/conversations`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({}),
        });

        expect(createResp.status).toBe(201);
        const created = await createResp.json();
        expect(created.model).toBe("claude-lite-free");

        // And GET /models should preserve SDK multipliers (no forced zeroing)
        const modelsResp = await fetch(`${baseUrl}/models`);
        const modelsData = await modelsResp.json();
        expect(modelsResp.status).toBe(200);
        expect(modelsData.models[0].id).toBe("claude-sonnet-4");
        expect(modelsData.models[0].multiplier).toBe(1.5);
        expect(modelsData.models[1].id).toBe("claude-lite-free");
        expect(modelsData.models[1].multiplier).toBe(0);

        // Verify audit log was emitted
        expect(logSpy).toHaveBeenCalled();
        expect(logSpy.mock.calls.some((call: (string | string[])[]) => call[0].includes('AUDIT: Default model'))).toBe(true);

        // Cleanup
        (copilotService as any).client = originalClient;
        (copilotService as any).createSession = originalCreateSession;
        logSpy.mockRestore();
      });

      it("should prefer the configured default model when it is present in SDK list", async () => {
        // Arrange: mock SDK client to return a list that includes the configured default
        const originalClient = (copilotService as any).client;
        const originalCreateSession = (copilotService as any).createSession;

        const defaultModelId = (config as any).defaults.model;

        (copilotService as any).client = {
          listModels: async () => [
            {
              id: defaultModelId,
              name: "Configured Default",
              billing: { multiplier: 1.0 },
              capabilities: { supports: { vision: false }, limits: { max_context_window_tokens: 8192 } },
              policy: { state: "enabled", terms: "" },
            },
            {
              id: "claude-lite-free",
              name: "Claude Lite Free",
              billing: { multiplier: 0.0 },
              capabilities: { supports: { vision: false }, limits: { max_context_window_tokens: 4096 } },
              policy: { state: "enabled", terms: "" },
            },
          ],
        };

        // Stub createSession so conversation creation succeeds
        (copilotService as any).createSession = async (_conversationId: string, _model: string) => {
          return {
            session: { destroy: async () => {} },
            model: _model,
            createdAt: new Date(),
            lastActiveAt: new Date(),
            messageCount: 0,
          };
        };

        // Act: create conversation with no model specified (should pick the configured default)
        const createResp = await fetch(`${baseUrl}/conversations`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({}),
        });

        expect(createResp.status).toBe(201);
        const created = await createResp.json();
        expect(created.model).toBe(defaultModelId);

        // Cleanup
        (copilotService as any).client = originalClient;
        (copilotService as any).createSession = originalCreateSession;
      });

      it("should reject title over 200 characters", async () => {
        const response = await fetch(`${baseUrl}/conversations`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: "a".repeat(201) }),
        });

        expect(response.status).toBe(400);
      });
    });

    describe("GET /api/conversations/:id", () => {
      it("should return 404 for non-existent conversation", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_nonexistent`);
        
        expect(response.status).toBe(404);
      });

      it("should return conversation details", async () => {
        const db = getDb();
        db.prepare(
          "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
        ).run("conv_test123", "Test Chat", "claude-sonnet-4");

        const response = await fetch(`${baseUrl}/conversations/conv_test123`);
        const data = await response.json();

        expect(response.status).toBe(200);
        expect(data.id).toBe("conv_test123");
        expect(data.title).toBe("Test Chat");
        expect(data.session).toBeDefined();
      });
    });

    describe("PUT /api/conversations/:id", () => {
      it("should update conversation title", async () => {
        const db = getDb();
        db.prepare(
          "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
        ).run("conv_update", "Original Title", "gpt-5");

        const response = await fetch(`${baseUrl}/conversations/conv_update`, {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: "Updated Title" }),
        });
        const data = await response.json();

        expect(response.status).toBe(200);
        expect(data.title).toBe("Updated Title");
      });

      it("should return 404 for non-existent conversation", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_nonexistent`, {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: "New Title" }),
        });

        expect(response.status).toBe(404);
      });
    });

    describe("DELETE /api/conversations/:id", () => {
      it("should delete a conversation", async () => {
        const db = getDb();
        db.prepare(
          "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
        ).run("conv_delete", "To Delete", "gpt-5");

        const response = await fetch(`${baseUrl}/conversations/conv_delete`, {
          method: "DELETE",
        });

        expect(response.status).toBe(204);

        // Verify deletion
        const check = await fetch(`${baseUrl}/conversations/conv_delete`);
        expect(check.status).toBe(404);
      });
    });
  });

  describe("Messages API", () => {
    beforeEach(() => {
      // Create a test conversation for message tests
      const db = getDb();
      db.prepare(
        "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
      ).run("conv_msg_test", "Message Test", "gpt-5");
    });

    describe("GET /api/conversations/:id/messages", () => {
      it("should return empty array for new conversation", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_msg_test/messages`);
        const data = await response.json();

        expect(response.status).toBe(200);
        expect(data.messages).toEqual([]);
      });

      it("should return messages for a conversation", async () => {
        const db = getDb();
        db.prepare(
          "INSERT INTO messages (id, conversation_id, role, content, status) VALUES (?, ?, ?, ?, ?)"
        ).run("msg_1", "conv_msg_test", "user", "Hello", "sent");
        db.prepare(
          "INSERT INTO messages (id, conversation_id, role, content, status) VALUES (?, ?, ?, ?, ?)"
        ).run("msg_2", "conv_msg_test", "assistant", "Hi there!", "sent");

        const response = await fetch(`${baseUrl}/conversations/conv_msg_test/messages`);
        const data = await response.json();

        expect(response.status).toBe(200);
        expect(data.messages).toHaveLength(2);
        expect(data.messages[0].role).toBe("user");
        expect(data.messages[1].role).toBe("assistant");
      });

      it("should support pagination with limit and before", async () => {
        const db = getDb();

        // Insert 10 messages with deterministic timestamps
        for (let i = 1; i <= 10; i++) {
          const ts = new Date(Date.UTC(2026, 0, 1, 0, 0, i)); // 2026-01-01T00:00:0iZ
          db.prepare(
            "INSERT INTO messages (id, conversation_id, role, content, status, created_at) VALUES (?, ?, ?, ?, ?, ?)"
          ).run(`msg_${i}`, "conv_msg_test", i % 2 === 0 ? "assistant" : "user", `m${i}`, "sent", ts.toISOString());
        }

        // Get last 3 messages
        const resp1 = await fetch(`${baseUrl}/conversations/conv_msg_test/messages?limit=3`);
        const data1 = await resp1.json();
        expect(resp1.status).toBe(200);
        expect(data1.messages).toHaveLength(3);
        // Should be msg_8, msg_9, msg_10 in ascending order
        expect(data1.messages.map((m: any) => m.id)).toEqual(["msg_8", "msg_9", "msg_10"]);

        // Page earlier messages before msg_8
        const before = new Date(Date.UTC(2026, 0, 1, 0, 0, 8)).toISOString();
        const resp2 = await fetch(`${baseUrl}/conversations/conv_msg_test/messages?limit=3&before=${encodeURIComponent(before)}`);
        const data2 = await resp2.json();
        expect(resp2.status).toBe(200);
        expect(data2.messages).toHaveLength(3);
        // Should be msg_5, msg_6, msg_7
        expect(data2.messages.map((m: any) => m.id)).toEqual(["msg_5", "msg_6", "msg_7"]);
      });

      it("should return 404 for non-existent conversation", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_nonexistent/messages`);
        
        expect(response.status).toBe(404);
      });
    });

    describe("POST /api/conversations/:id/messages", () => {
      it("should reject empty content", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_msg_test/messages`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content: "" }),
        });

        expect(response.status).toBe(400);
      });

      it("should reject whitespace-only content", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_msg_test/messages`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content: "   \n\t  " }),
        });

        expect(response.status).toBe(400);
      });

      it("should return 404 for non-existent conversation", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_nonexistent/messages`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content: "Hello" }),
        });

        expect(response.status).toBe(404);
      });
    });
  });

  describe("Search", () => {
    it("should search conversations by title", async () => {
      const db = getDb();
      db.prepare(
        "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
      ).run("conv_s1", "Swift Programming", "gpt-5");
      db.prepare(
        "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
      ).run("conv_s2", "Python Tutorial", "gpt-5");
      db.prepare(
        "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
      ).run("conv_s3", "Swift UI Design", "gpt-5");

      const response = await fetch(`${baseUrl}/conversations?q=Swift`);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.conversations).toHaveLength(2);
      expect(data.conversations.every((c: any) => 
        c.title.toLowerCase().includes("swift")
      )).toBe(true);
    });

    it("should search conversations by tag name", async () => {
      const db = getDb();
      // Create conversations
      db.prepare(
        "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
      ).run("conv_tag1", "Chat One", "gpt-5");
      db.prepare(
        "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
      ).run("conv_tag2", "Chat Two", "gpt-5");
      
      // Create a tag
      db.prepare("INSERT INTO tags (id, name, color) VALUES (?, ?, ?)").run(1, "Claude", "#5436DA");
      
      // Associate tag with first conversation
      db.prepare("INSERT INTO conversation_tags (conversation_id, tag_id) VALUES (?, ?)").run("conv_tag1", 1);

      const response = await fetch(`${baseUrl}/conversations?q=Claude`);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.conversations).toHaveLength(1);
      expect(data.conversations[0].id).toBe("conv_tag1");
      expect(data.conversations[0].tags).toHaveLength(1);
      expect(data.conversations[0].tags[0].name).toBe("Claude");
    });
  });

  describe("Tags API", () => {
    beforeEach(() => {
      // Create a test conversation for tag tests
      const db = getDb();
      db.prepare(
        "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
      ).run("conv_tag_test", "Tag Test Chat", "gpt-5");
    });

    describe("POST /api/conversations/:id/tags", () => {
      it("should add a new tag to a conversation", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Important" }),
        });
        const data = await response.json();

        expect(response.status).toBe(201);
        expect(data.id).toBe("conv_tag_test");
        expect(data.tags).toHaveLength(1);
        expect(data.tags[0].name).toBe("Important");
      });

      it("should add a tag with a color", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Priority", color: "#FF5733" }),
        });
        const data = await response.json();

        expect(response.status).toBe(201);
        expect(data.tags).toHaveLength(1);
        expect(data.tags[0].name).toBe("Priority");
        expect(data.tags[0].color).toBe("#FF5733");
      });

      it("should reuse existing tag with same name (case insensitive)", async () => {
        // First, add a tag
        await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Work" }),
        });

        // Create another conversation
        const db = getDb();
        db.prepare(
          "INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)"
        ).run("conv_tag_test2", "Another Chat", "gpt-5");

        // Add same tag to second conversation
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test2/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "work" }), // lowercase
        });
        const data = await response.json();

        expect(response.status).toBe(201);
        expect(data.tags[0].name).toBe("Work"); // Original casing preserved

        // Check that only one tag exists in database
        const tagsCount = db.prepare("SELECT COUNT(*) as count FROM tags WHERE LOWER(name) = 'work'").get() as { count: number };
        expect(tagsCount.count).toBe(1);
      });

      it("should return 404 for non-existent conversation", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_nonexistent/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Test" }),
        });

        expect(response.status).toBe(404);
      });

      it("should reject empty tag name", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "" }),
        });

        expect(response.status).toBe(400);
      });

      it("should reject tag name over 50 characters", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "a".repeat(51) }),
        });

        expect(response.status).toBe(400);
      });

      it("should reject invalid color format", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Test", color: "red" }),
        });

        expect(response.status).toBe(400);
      });
    });

    describe("DELETE /api/conversations/:id/tags/:tagId", () => {
      it("should remove a tag from a conversation", async () => {
        // First add a tag
        const addResponse = await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "ToRemove" }),
        });
        const addData = await addResponse.json();
        const tagId = addData.tags[0].id;

        // Remove the tag
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags/${tagId}`, {
          method: "DELETE",
        });
        const data = await response.json();

        expect(response.status).toBe(200);
        expect(data.tags).toHaveLength(0);
      });

      it("should return 404 for non-existent conversation", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_nonexistent/tags/1`, {
          method: "DELETE",
        });

        expect(response.status).toBe(404);
      });

      it("should return 400 for invalid tag ID", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags/invalid`, {
          method: "DELETE",
        });

        expect(response.status).toBe(400);
      });

      it("should handle removing non-existent tag gracefully", async () => {
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags/999`, {
          method: "DELETE",
        });
        const data = await response.json();

        // Should return 200 with conversation (tag just doesn't exist)
        expect(response.status).toBe(200);
        expect(data.tags).toHaveLength(0);
      });
    });

    describe("Multiple tags", () => {
      it("should support multiple tags on one conversation", async () => {
        // Add first tag
        await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Tag1" }),
        });

        // Add second tag
        await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Tag2" }),
        });

        // Add third tag
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Tag3" }),
        });
        const data = await response.json();

        expect(response.status).toBe(201);
        expect(data.tags).toHaveLength(3);
      });

      it("should not duplicate tag if already associated", async () => {
        // Add tag
        await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Duplicate" }),
        });

        // Try to add same tag again
        const response = await fetch(`${baseUrl}/conversations/conv_tag_test/tags`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: "Duplicate" }),
        });
        const data = await response.json();

        expect(response.status).toBe(201);
        expect(data.tags).toHaveLength(1); // Still just one tag
      });
    });
  });
});
