/**
 * Global Error Handler Middleware
 */

import { Request, Response, NextFunction } from "express";
import { AppError, ErrorCodes } from "../types/index.js";

/**
 * Map SDK/system errors to user-friendly error codes
 */
function categorizeError(err: Error): { code: string; statusCode: number; message: string } {
  const errorMessage = err.message.toLowerCase();

  // SDK/Authentication errors
  if (errorMessage.includes("not authenticated") || errorMessage.includes("auth")) {
    return {
      code: ErrorCodes.SDK_NOT_AUTHENTICATED,
      statusCode: 401,
      message: "Copilot CLI is not authenticated. Please run 'copilot auth login'.",
    };
  }

  if (errorMessage.includes("not installed") || errorMessage.includes("command not found")) {
    return {
      code: ErrorCodes.SDK_NOT_INSTALLED,
      statusCode: 503,
      message: "Copilot CLI is not installed. Please install it first.",
    };
  }

  if (errorMessage.includes("connection") || errorMessage.includes("timeout")) {
    return {
      code: ErrorCodes.SDK_CONNECTION_FAILED,
      statusCode: 503,
      message: "Failed to connect to Copilot service. Please try again.",
    };
  }

  // Session errors
  if (errorMessage.includes("session not found") || err.message === ErrorCodes.SESSION_NOT_FOUND) {
    return {
      code: ErrorCodes.SESSION_NOT_FOUND,
      statusCode: 404,
      message: "Session not found. Please start a new conversation.",
    };
  }

  // Model errors
  if (errorMessage.includes("model not available") || errorMessage.includes("model")) {
    return {
      code: ErrorCodes.MODEL_NOT_AVAILABLE,
      statusCode: 400,
      message: "The selected model is not available. Please choose a different model.",
    };
  }

  // Quota errors
  if (errorMessage.includes("quota") || errorMessage.includes("rate limit")) {
    return {
      code: ErrorCodes.QUOTA_EXCEEDED,
      statusCode: 429,
      message: "Request quota exceeded. Please wait before sending more messages.",
    };
  }

  // Database errors
  if (errorMessage.includes("sqlite") || errorMessage.includes("database")) {
    return {
      code: ErrorCodes.DATABASE_ERROR,
      statusCode: 500,
      message: "Database operation failed. Please try again.",
    };
  }

  // Network errors
  if (errorMessage.includes("network") || errorMessage.includes("fetch")) {
    return {
      code: ErrorCodes.NETWORK_ERROR,
      statusCode: 503,
      message: "Network error. Please check your internet connection.",
    };
  }

  // Default
  return {
    code: ErrorCodes.INTERNAL_ERROR,
    statusCode: 500,
    message: process.env.NODE_ENV === "production"
      ? "An unexpected error occurred"
      : err.message,
  };
}

export function errorHandler(
  err: Error,
  _req: Request,
  res: Response,
  _next: NextFunction
): void {
  console.error("[Error]", err);

  if (err instanceof AppError) {
    res.status(err.statusCode).json({
      error: err.toJSON(),
    });
    return;
  }

  // Handle specific error types
  if (err.name === "SyntaxError") {
    res.status(400).json({
      error: {
        code: ErrorCodes.INVALID_REQUEST,
        message: "Invalid JSON in request body",
      },
    });
    return;
  }

  // Categorize and handle the error
  const categorized = categorizeError(err);
  res.status(categorized.statusCode).json({
    error: {
      code: categorized.code,
      message: categorized.message,
    },
  });
}
