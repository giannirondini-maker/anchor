import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { initializeDatabase, getDb, getMessagesForConversation } from "../src/services/database.service.js";

beforeAll(async () => {
  process.env.DATABASE_PATH = ":memory:";
  await initializeDatabase();
});

beforeEach(() => {
  const db = getDb();
  db.exec("DELETE FROM messages");
  db.exec("DELETE FROM conversation_tags");
  db.exec("DELETE FROM tags");
  db.exec("DELETE FROM conversations");
});

describe("Message ordering", () => {
  it("preserves insertion order when created_at timestamps are identical", () => {
    const db = getDb();

    // Insert conversation
    db.prepare("INSERT INTO conversations (id, title, model) VALUES (?, ?, ?)").run(
      "conv_order",
      "Order Test",
      "test-model"
    );

    // Use identical timestamps for both messages
    const timestamp = new Date().toISOString();

    // Insert user message first, then assistant message (same timestamp)
    db.prepare(
      "INSERT INTO messages (id, conversation_id, role, content, created_at, status) VALUES (?, ?, ?, ?, ?, ?)"
    ).run("m_user", "conv_order", "user", "Hello", timestamp, "sent");

    db.prepare(
      "INSERT INTO messages (id, conversation_id, role, content, created_at, status) VALUES (?, ?, ?, ?, ?, ?)"
    ).run("m_assistant", "conv_order", "assistant", "Hi", timestamp, "sent");

    const messages = getMessagesForConversation("conv_order");
    expect(messages).toHaveLength(2);
    expect(messages[0].role).toBe("user");
    expect(messages[1].role).toBe("assistant");
  });
});
