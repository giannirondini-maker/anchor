/**
 * Database Service
 *
 * Handles SQLite database initialization and operations.
 * Uses better-sqlite3 for synchronous operations.
 */

import Database from "better-sqlite3";
import path from "path";
import fs from "fs";
import { config } from "../config.js";
import {
  Conversation,
  ConversationRow,
  Message,
  MessageRow,
  Tag,
  TagRow,
  MessageRole,
  MessageStatus,
} from "../types/index.js";

let db: Database.Database;

/**
 * Initialize the database connection and create tables if needed
 */
export async function initializeDatabase(): Promise<void> {
  // Ensure the directory exists
  const dbDir = path.dirname(config.database.path);
  if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
    console.log(`📁 Created database directory: ${dbDir}`);
  }

  // Open database connection
  db = new Database(config.database.path);

  // Enable WAL mode for better concurrency
  db.pragma("journal_mode = WAL");

  // Enable foreign keys
  db.pragma("foreign_keys = ON");

  // Create tables
  createTables();

  console.log(`📦 Database initialized at: ${config.database.path}`);
}

/**
 * Create database tables if they don't exist
 */
function createTables(): void {
  // Conversations table
  db.exec(`
    CREATE TABLE IF NOT EXISTS conversations (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT 'New Conversation',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      model TEXT,
      agent TEXT,
      session_id TEXT
    )
  `);

  // Messages table
  db.exec(`
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
      content TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      status TEXT DEFAULT 'sent' CHECK (status IN ('sending', 'sent', 'error')),
      error_message TEXT,
      FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
    )
  `);

  // Tags table
  db.exec(`
    CREATE TABLE IF NOT EXISTS tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      color TEXT
    )
  `);

  // Conversation-Tags junction table
  db.exec(`
    CREATE TABLE IF NOT EXISTS conversation_tags (
      conversation_id TEXT NOT NULL,
      tag_id INTEGER NOT NULL,
      PRIMARY KEY (conversation_id, tag_id),
      FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
      FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
    )
  `);

  // Create indexes for performance
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
    CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
    CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);
    CREATE INDEX IF NOT EXISTS idx_conversations_title ON conversations(title);
  `);

  console.log("📋 Database tables created/verified");
}

/**
 * Get the database instance
 */
export function getDb(): Database.Database {
  if (!db) {
    throw new Error("Database not initialized. Call initializeDatabase() first.");
  }
  return db;
}

// ============================================================================
// Conversation Operations
// ============================================================================

function rowToConversation(row: ConversationRow): Conversation {
  return {
    id: row.id,
    title: row.title,
    createdAt: new Date(row.created_at),
    updatedAt: new Date(row.updated_at),
    model: row.model,
    agent: row.agent,
    sessionId: row.session_id,
    tags: getTagsForConversation(row.id),
  };
}

export function getAllConversations(): Conversation[] {
  const stmt = db.prepare(`
    SELECT * FROM conversations 
    ORDER BY updated_at DESC
  `);
  const rows = stmt.all() as ConversationRow[];
  return rows.map(rowToConversation);
}

export function getConversationById(id: string): Conversation | null {
  const stmt = db.prepare(`SELECT * FROM conversations WHERE id = ?`);
  const row = stmt.get(id) as ConversationRow | undefined;
  return row ? rowToConversation(row) : null;
}

export function createConversation(
  id: string,
  title: string,
  model: string | null = null,
  agent: string | null = null,
  sessionId: string | null = null
): Conversation {
  const stmt = db.prepare(`
    INSERT INTO conversations (id, title, model, agent, session_id)
    VALUES (?, ?, ?, ?, ?)
  `);
  stmt.run(id, title, model, agent, sessionId);
  return getConversationById(id)!;
}

export function updateConversation(
  id: string,
  updates: { title?: string; model?: string; agent?: string; sessionId?: string }
): Conversation | null {
  const fields: string[] = [];
  const values: (string | null)[] = [];

  if (updates.title !== undefined) {
    fields.push("title = ?");
    values.push(updates.title);
  }
  if (updates.model !== undefined) {
    fields.push("model = ?");
    values.push(updates.model);
  }
  if (updates.agent !== undefined) {
    fields.push("agent = ?");
    values.push(updates.agent);
  }
  if (updates.sessionId !== undefined) {
    fields.push("session_id = ?");
    values.push(updates.sessionId);
  }

  if (fields.length === 0) {
    return getConversationById(id);
  }

  fields.push("updated_at = CURRENT_TIMESTAMP");
  values.push(id);

  const stmt = db.prepare(`
    UPDATE conversations 
    SET ${fields.join(", ")}
    WHERE id = ?
  `);
  stmt.run(...values);

  return getConversationById(id);
}

export function deleteConversation(id: string): boolean {
  const stmt = db.prepare(`DELETE FROM conversations WHERE id = ?`);
  const result = stmt.run(id);
  return result.changes > 0;
}

export function deleteAllConversations(): number {
  const stmt = db.prepare(`DELETE FROM conversations`);
  const result = stmt.run();
  return result.changes;
}

// ============================================================================
// Message Operations
// ============================================================================

function rowToMessage(row: MessageRow): Message {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    role: row.role as MessageRole,
    content: row.content,
    createdAt: new Date(row.created_at),
    status: row.status as MessageStatus,
    errorMessage: row.error_message,
  };
}

export function getMessagesForConversation(conversationId: string, limit?: number, before?: string): Message[] {
  // If no pagination is requested, return all messages in ascending order
  if (!limit) {
    const stmt = db.prepare(`
      SELECT * FROM messages 
      WHERE conversation_id = ?
      ORDER BY created_at ASC, rowid ASC
    `);
    const rows = stmt.all(conversationId) as MessageRow[];
    return rows.map(rowToMessage);
  }

  // When limit is provided we query in reverse (latest first) and then reverse back
  // Optionally support a `before` cursor (ISO 8601 timestamp) to page older messages
  let rows: MessageRow[] = [];

  if (before) {
    const stmt = db.prepare(`
      SELECT * FROM messages
      WHERE conversation_id = ? AND created_at < ?
      ORDER BY created_at DESC, rowid DESC
      LIMIT ?
    `);
    rows = stmt.all(conversationId, before, limit) as MessageRow[];
  } else {
    const stmt = db.prepare(`
      SELECT * FROM messages
      WHERE conversation_id = ?
      ORDER BY created_at DESC, rowid DESC
      LIMIT ?
    `);
    rows = stmt.all(conversationId, limit) as MessageRow[];
  }

  // Return in ascending order (oldest -> newest)
  return rows.reverse().map(rowToMessage);
}

export function createMessage(
  id: string,
  conversationId: string,
  role: MessageRole,
  content: string,
  status: MessageStatus = "sent"
): Message {
  const stmt = db.prepare(`
    INSERT INTO messages (id, conversation_id, role, content, status)
    VALUES (?, ?, ?, ?, ?)
  `);
  stmt.run(id, conversationId, role, content, status);

  // Update conversation's updated_at timestamp
  db.prepare(`
    UPDATE conversations SET updated_at = CURRENT_TIMESTAMP WHERE id = ?
  `).run(conversationId);

  return getMessageById(id)!;
}

export function getMessageById(id: string): Message | null {
  const stmt = db.prepare(`SELECT * FROM messages WHERE id = ?`);
  const row = stmt.get(id) as MessageRow | undefined;
  return row ? rowToMessage(row) : null;
}

export function updateMessage(
  id: string,
  updates: { content?: string; status?: MessageStatus; errorMessage?: string | null }
): Message | null {
  const fields: string[] = [];
  const values: (string | null)[] = [];

  if (updates.content !== undefined) {
    fields.push("content = ?");
    values.push(updates.content);
  }
  if (updates.status !== undefined) {
    fields.push("status = ?");
    values.push(updates.status);
  }
  if (updates.errorMessage !== undefined) {
    fields.push("error_message = ?");
    values.push(updates.errorMessage);
  }

  if (fields.length === 0) {
    return getMessageById(id);
  }

  values.push(id);

  const stmt = db.prepare(`
    UPDATE messages 
    SET ${fields.join(", ")}
    WHERE id = ?
  `);
  stmt.run(...values);

  return getMessageById(id);
}

export function deleteMessage(id: string): boolean {
  const stmt = db.prepare(`DELETE FROM messages WHERE id = ?`);
  const result = stmt.run(id);
  return result.changes > 0;
}

// ============================================================================
// Tag Operations
// ============================================================================

function rowToTag(row: TagRow): Tag {
  return {
    id: row.id,
    name: row.name,
    color: row.color,
  };
}

export function getAllTags(): Tag[] {
  const stmt = db.prepare(`SELECT * FROM tags ORDER BY name`);
  const rows = stmt.all() as TagRow[];
  return rows.map(rowToTag);
}

export function getTagsForConversation(conversationId: string): Tag[] {
  const stmt = db.prepare(`
    SELECT t.* FROM tags t
    JOIN conversation_tags ct ON t.id = ct.tag_id
    WHERE ct.conversation_id = ?
    ORDER BY t.name
  `);
  const rows = stmt.all(conversationId) as TagRow[];
  return rows.map(rowToTag);
}

export function createTag(name: string, color: string | null = null): Tag {
  const stmt = db.prepare(`
    INSERT INTO tags (name, color) VALUES (?, ?)
  `);
  const result = stmt.run(name, color);
  return {
    id: Number(result.lastInsertRowid),
    name,
    color,
  };
}

export function addTagToConversation(
  conversationId: string,
  tagId: number
): boolean {
  try {
    const stmt = db.prepare(`
      INSERT INTO conversation_tags (conversation_id, tag_id) VALUES (?, ?)
    `);
    stmt.run(conversationId, tagId);
    return true;
  } catch {
    return false; // Already exists or invalid
  }
}

export function removeTagFromConversation(
  conversationId: string,
  tagId: number
): boolean {
  const stmt = db.prepare(`
    DELETE FROM conversation_tags WHERE conversation_id = ? AND tag_id = ?
  `);
  const result = stmt.run(conversationId, tagId);
  return result.changes > 0;
}

// ============================================================================
// Search Operations
// ============================================================================

export function searchConversations(query: string): Conversation[] {
  // Search by title or by tag name
  const stmt = db.prepare(`
    SELECT DISTINCT c.* FROM conversations c
    LEFT JOIN conversation_tags ct ON c.id = ct.conversation_id
    LEFT JOIN tags t ON ct.tag_id = t.id
    WHERE c.title LIKE ? OR t.name LIKE ?
    ORDER BY c.updated_at DESC
  `);
  const searchPattern = `%${query}%`;
  const rows = stmt.all(searchPattern, searchPattern) as ConversationRow[];
  return rows.map(rowToConversation);
}
