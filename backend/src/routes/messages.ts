/**
 * Messages Routes
 */

import { Router } from "express";
import { v4 as uuidv4 } from "uuid";
import {
  getConversationById,
  getMessagesForConversation,
  createMessage,
  updateMessage,
} from "../services/database.service.js";
import { copilotService } from "../services/copilot.service.js";
import { broadcastToConversation } from "../websocket/handler.js";
import { AppError, SendMessageResponse, ErrorCodes } from "../types/index.js";
import { config } from "../config.js";
import { validateBody } from "../middleware/validate.js";
import {
  SendMessageSchema,
  RetryMessageSchema,
  SendMessageInput,
  RetryMessageInput,
} from "../middleware/validation.js";
import { messageLimiter } from "../middleware/rateLimit.js";

const router = Router();

/**
 * GET /api/conversations/:id/messages
 * Supports optional pagination via query params:
 *  - limit=<n> : return at most n messages (latest messages)
 *  - before=<ISO8601 timestamp> : return messages older than this timestamp
 */
router.get("/:id/messages", (req, res, next) => {
  try {
    const { id } = req.params;

    const conversation = getConversationById(id);
    if (!conversation) {
      throw new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    }

    const limit = req.query.limit ? parseInt(req.query.limit as string) : undefined;
    const before = req.query.before ? String(req.query.before) : undefined;

    const messages = getMessagesForConversation(id, limit, before);
    res.json({ messages });
  } catch (error) {
    next(error);
  }
});

/**
 * POST /api/conversations/:id/messages
 * Sends a new message and triggers streaming response
 */
router.post("/:id/messages", messageLimiter, validateBody(SendMessageSchema), async (req, res, next) => {
  try {
    const { id: conversationId } = req.params;
    const body = req.body as SendMessageInput;

    const conversation = getConversationById(conversationId);
    if (!conversation) {
      throw new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    }

    // Create user message
    const userMessageId = `msg_${uuidv4()}`;
    createMessage(userMessageId, conversationId, "user", body.content.trim(), "sent");

    // Create placeholder for assistant message
    const assistantMessageId = `msg_${uuidv4()}`;
    createMessage(assistantMessageId, conversationId, "assistant", "", "sending");

    // Ensure session exists (resume with context if needed)
    let session = copilotService.getSession(conversationId);
    if (!session) {
      const messages = getMessagesForConversation(conversationId);
      // Exclude the placeholder assistant message we just created
      const historyForResume = messages
        .filter((m) => m.id !== assistantMessageId)
        .map((m) => ({
          role: m.role,
          content: m.content,
        }));

      await copilotService.resumeSession(conversationId, historyForResume, {
        conversationId,
        model: conversation.model || config.defaults.model,
        injectHistory: true,
      });
    }

    // Return immediately with 202 Accepted
    const response: SendMessageResponse = {
      messageId: assistantMessageId,
      status: "streaming",
    };
    res.status(202).json(response);

    // Broadcast message start
    broadcastToConversation(conversationId, "message:start", {
      messageId: assistantMessageId,
    });

    // Send to SDK and stream response
    copilotService.sendMessage(
      conversationId,
      body.content.trim(),
      // onDelta
      (content: string) => {
        broadcastToConversation(conversationId, "message:delta", {
          messageId: assistantMessageId,
          content,
        });
      },
      // onComplete
      (fullContent: string) => {
        // Update message in database
        updateMessage(assistantMessageId, {
          content: fullContent,
          status: "sent",
        });

        broadcastToConversation(conversationId, "message:complete", {
          messageId: assistantMessageId,
          fullContent,
        });
      },
      // onError
      (error: Error) => {
        updateMessage(assistantMessageId, {
          status: "error",
          errorMessage: error.message,
        });

        broadcastToConversation(conversationId, "message:error", {
          messageId: assistantMessageId,
          error: error.message,
        });
      }
    );
  } catch (error) {
    next(error);
  }
});

/**
 * POST /api/conversations/:id/messages/:messageId/retry
 * Retry a failed message with optional edited content
 */
router.post("/:id/messages/:messageId/retry", validateBody(RetryMessageSchema), async (req, res, next) => {
  try {
    const { id: conversationId, messageId } = req.params;
    const body = req.body as RetryMessageInput;

    const conversation = getConversationById(conversationId);
    if (!conversation) {
      throw new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    }

    const messages = getMessagesForConversation(conversationId);
    
    // Find the failed assistant message
    const failedMessage = messages.find(
      (m) => m.id === messageId && m.role === "assistant" && m.status === "error"
    );

    if (!failedMessage) {
      throw new AppError(ErrorCodes.MESSAGE_NOT_FOUND, "Failed message not found", 404);
    }

    // Find the preceding user message
    const messageIndex = messages.findIndex((m) => m.id === messageId);
    const userMessage = messages
      .slice(0, messageIndex)
      .reverse()
      .find((m) => m.role === "user");

    if (!userMessage) {
      throw new AppError(ErrorCodes.MESSAGE_NOT_FOUND, "Original user message not found", 404);
    }

    // Use provided content or original user message content
    const retryContent = body.content?.trim() || userMessage.content;

    // If content was edited, update the user message
    if (body.content && body.content.trim() !== userMessage.content) {
      updateMessage(userMessage.id, { content: body.content.trim() });
    }

    // Reset the failed message status
    updateMessage(messageId, {
      content: "",
      status: "sending",
      errorMessage: null,
    });

    // Ensure session exists
    let session = copilotService.getSession(conversationId);
    if (!session) {
      const historyForResume = messages
        .filter((m) => m.id !== messageId)
        .slice(0, messageIndex)
        .map((m) => ({
          role: m.role,
          content: m.content,
        }));

      await copilotService.resumeSession(conversationId, historyForResume, {
        conversationId,
        model: conversation.model || config.defaults.model,
        injectHistory: true,
      });
    }

    // Return immediately with 202 Accepted
    res.status(202).json({
      messageId,
      status: "streaming",
    });

    // Broadcast message start
    broadcastToConversation(conversationId, "message:start", {
      messageId,
    });

    // Retry sending to SDK with potentially edited content
    copilotService.sendMessage(
      conversationId,
      retryContent,
      // onDelta
      (content: string) => {
        broadcastToConversation(conversationId, "message:delta", {
          messageId,
          content,
        });
      },
      // onComplete
      (fullContent: string) => {
        updateMessage(messageId, {
          content: fullContent,
          status: "sent",
          errorMessage: null,
        });

        broadcastToConversation(conversationId, "message:complete", {
          messageId,
          fullContent,
        });
      },
      // onError
      (error: Error) => {
        updateMessage(messageId, {
          status: "error",
          errorMessage: error.message,
        });

        broadcastToConversation(conversationId, "message:error", {
          messageId,
          error: error.message,
        });
      }
    );
  } catch (error) {
    next(error);
  }
});

export default router;
