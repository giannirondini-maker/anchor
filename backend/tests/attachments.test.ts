/**
 * Attachments API Tests
 */

import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import { createServer, ServerInstance } from "../src/server.js";
import { initializeDatabase, getDb } from "../src/services/database.service.js";

describe("Attachments API", () => {
  let server: ServerInstance;
  let baseUrl: string;
  const testPort = 3101;

  beforeAll(async () => {
    process.env.DATABASE_PATH = ":memory:";
    process.env.DISABLE_RATE_LIMIT = "true";

    await initializeDatabase();

    server = createServer();
    await new Promise<void>((resolve) => {
      server.httpServer.listen(testPort, () => {
        baseUrl = `http://localhost:${testPort}/api`;
        resolve();
      });
    });
  });

  afterAll(async () => {
    await new Promise<void>((resolve, reject) => {
      server.httpServer.close((err) => {
        if (err) reject(err);
        else resolve();
      });
    });
    server.wss.close();

    try {
      getDb().close();
    } catch {
      // Ignore
    }
  });

  beforeEach(() => {
    const db = getDb();
    db.exec("DELETE FROM messages");
    db.exec("DELETE FROM conversation_tags");
    db.exec("DELETE FROM tags");
    db.exec("DELETE FROM conversations");
  });

  it("uploads an attachment", async () => {
    const form = new FormData();
    form.append("conversationId", "conv_test");
    form.append("file", new Blob(["hello world"], { type: "text/plain" }), "note.txt");

    const response = await fetch(`${baseUrl}/attachments`, {
      method: "POST",
      body: form,
    });

    expect(response.status).toBe(201);
    const data = await response.json();
    expect(data.attachments).toHaveLength(1);
    expect(data.attachments[0].id).toMatch(/^att_/);
    expect(data.attachments[0].displayName).toBe("note.txt");
  });

  it("rejects unsupported attachment types", async () => {
    const form = new FormData();
    form.append("conversationId", "conv_test");
    form.append("file", new Blob(["binary"], { type: "application/octet-stream" }), "bad.exe");

    const response = await fetch(`${baseUrl}/attachments`, {
      method: "POST",
      body: form,
    });

    expect(response.status).toBe(400);
    const data = await response.json();
    expect(data.error).toBeDefined();
  });
});
