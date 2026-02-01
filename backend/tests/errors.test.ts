/**
 * Error Handler Tests
 *
 * Unit tests for error categorization and handling
 */

import { describe, it, expect } from "vitest";
import { AppError, ErrorCodes } from "../src/types/index.js";

describe("AppError", () => {
  it("should create an error with code and message", () => {
    const error = new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    
    expect(error.code).toBe("CONVERSATION_NOT_FOUND");
    expect(error.message).toBe("Conversation not found");
    expect(error.statusCode).toBe(404);
    expect(error.name).toBe("AppError");
  });

  it("should default to 500 status code", () => {
    const error = new AppError(ErrorCodes.INTERNAL_ERROR, "Something went wrong");
    expect(error.statusCode).toBe(500);
  });

  it("should include details when provided", () => {
    const details = { field: "title", value: "" };
    const error = new AppError(ErrorCodes.INVALID_REQUEST, "Invalid request", 400, details);
    
    expect(error.details).toEqual(details);
  });

  it("should convert to JSON properly", () => {
    const error = new AppError(
      ErrorCodes.MESSAGE_NOT_FOUND,
      "Message not found",
      404,
      { messageId: "msg_123" }
    );
    
    const json = error.toJSON();
    
    expect(json).toEqual({
      code: "MESSAGE_NOT_FOUND",
      message: "Message not found",
      details: { messageId: "msg_123" },
    });
  });

  it("should be an instance of Error", () => {
    const error = new AppError(ErrorCodes.INTERNAL_ERROR, "Test error");
    expect(error).toBeInstanceOf(Error);
  });
});

describe("ErrorCodes", () => {
  it("should have SDK error codes", () => {
    expect(ErrorCodes.SDK_NOT_INSTALLED).toBe("SDK_NOT_INSTALLED");
    expect(ErrorCodes.SDK_NOT_AUTHENTICATED).toBe("SDK_NOT_AUTHENTICATED");
    expect(ErrorCodes.SDK_CONNECTION_FAILED).toBe("SDK_CONNECTION_FAILED");
    expect(ErrorCodes.SDK_SESSION_ERROR).toBe("SDK_SESSION_ERROR");
  });

  it("should have session error codes", () => {
    expect(ErrorCodes.SESSION_NOT_FOUND).toBe("SESSION_NOT_FOUND");
    expect(ErrorCodes.SESSION_CREATE_FAILED).toBe("SESSION_CREATE_FAILED");
    expect(ErrorCodes.SESSION_RESUME_FAILED).toBe("SESSION_RESUME_FAILED");
  });

  it("should have conversation error codes", () => {
    expect(ErrorCodes.CONVERSATION_NOT_FOUND).toBe("CONVERSATION_NOT_FOUND");
    expect(ErrorCodes.CONVERSATION_CREATE_FAILED).toBe("CONVERSATION_CREATE_FAILED");
  });

  it("should have message error codes", () => {
    expect(ErrorCodes.MESSAGE_NOT_FOUND).toBe("MESSAGE_NOT_FOUND");
    expect(ErrorCodes.MESSAGE_SEND_FAILED).toBe("MESSAGE_SEND_FAILED");
    expect(ErrorCodes.INVALID_MESSAGE_CONTENT).toBe("INVALID_MESSAGE_CONTENT");
  });

  it("should have general error codes", () => {
    expect(ErrorCodes.INVALID_REQUEST).toBe("INVALID_REQUEST");
    expect(ErrorCodes.DATABASE_ERROR).toBe("DATABASE_ERROR");
    expect(ErrorCodes.NETWORK_ERROR).toBe("NETWORK_ERROR");
    expect(ErrorCodes.QUOTA_EXCEEDED).toBe("QUOTA_EXCEEDED");
    expect(ErrorCodes.INTERNAL_ERROR).toBe("INTERNAL_ERROR");
  });
});
