/**
 * Validation Schema Tests
 *
 * Unit tests for Zod validation schemas
 */

import { describe, it, expect } from "vitest";
import {
  CreateConversationSchema,
  UpdateConversationSchema,
  SendMessageSchema,
  RetryMessageSchema,
} from "../src/middleware/validation.js";

describe("CreateConversationSchema", () => {
  it("should accept valid input with all fields", () => {
    const input = {
      title: "Test Conversation",
      model: "claude-sonnet-4-20250514",
      agent: "my-agent",
    };
    
    const result = CreateConversationSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.title).toBe("Test Conversation");
      expect(result.data.model).toBe("claude-sonnet-4-20250514");
      expect(result.data.agent).toBe("my-agent");
    }
  });

  it("should accept empty object (all fields optional)", () => {
    const result = CreateConversationSchema.safeParse({});
    expect(result.success).toBe(true);
  });

  it("should accept null agent", () => {
    const input = { title: "Test", agent: null };
    const result = CreateConversationSchema.safeParse(input);
    expect(result.success).toBe(true);
  });

  it("should reject title longer than 200 characters", () => {
    const input = { title: "a".repeat(201) };
    const result = CreateConversationSchema.safeParse(input);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.errors[0].message).toContain("200 characters");
    }
  });

  it("should reject empty title string", () => {
    const input = { title: "" };
    const result = CreateConversationSchema.safeParse(input);
    expect(result.success).toBe(false);
  });
});

describe("UpdateConversationSchema", () => {
  it("should accept partial updates", () => {
    const result = UpdateConversationSchema.safeParse({ title: "New Title" });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.title).toBe("New Title");
      expect(result.data.model).toBeUndefined();
    }
  });

  it("should accept model-only update", () => {
    const result = UpdateConversationSchema.safeParse({ model: "gpt-5" });
    expect(result.success).toBe(true);
  });

  it("should reject empty model string", () => {
    const result = UpdateConversationSchema.safeParse({ model: "" });
    expect(result.success).toBe(false);
  });
});

describe("SendMessageSchema", () => {
  it("should accept valid message content", () => {
    const input = { content: "Hello, how are you?" };
    const result = SendMessageSchema.safeParse(input);
    expect(result.success).toBe(true);
  });

  it("should reject empty content", () => {
    const result = SendMessageSchema.safeParse({ content: "" });
    expect(result.success).toBe(false);
  });

  it("should reject whitespace-only content", () => {
    const result = SendMessageSchema.safeParse({ content: "   \n\t  " });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.errors[0].message).toContain("empty or only whitespace");
    }
  });

  it("should reject missing content field", () => {
    const result = SendMessageSchema.safeParse({});
    expect(result.success).toBe(false);
  });

  it("should reject content over 100,000 characters", () => {
    const input = { content: "a".repeat(100001) };
    const result = SendMessageSchema.safeParse(input);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.errors[0].message).toContain("100,000 characters");
    }
  });

  it("should accept content at max length", () => {
    const input = { content: "a".repeat(100000) };
    const result = SendMessageSchema.safeParse(input);
    expect(result.success).toBe(true);
  });
});

describe("RetryMessageSchema", () => {
  it("should accept empty object (content optional)", () => {
    const result = RetryMessageSchema.safeParse({});
    expect(result.success).toBe(true);
  });

  it("should accept valid edited content", () => {
    const input = { content: "Edited message" };
    const result = RetryMessageSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.content).toBe("Edited message");
    }
  });

  it("should reject empty content string", () => {
    const result = RetryMessageSchema.safeParse({ content: "" });
    expect(result.success).toBe(false);
  });
});
