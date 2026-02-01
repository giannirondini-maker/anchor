/**
 * Conversations Routes
 */

import { Router } from "express";
import { v4 as uuidv4 } from "uuid";
import {
  getAllConversations,
  getConversationById,
  createConversation,
  updateConversation,
  deleteConversation,
  deleteAllConversations,
  searchConversations,
  getMessagesForConversation,
  createTag,
  addTagToConversation,
  removeTagFromConversation,
  getAllTags,
} from "../services/database.service.js";
import { copilotService } from "../services/copilot.service.js";
import { AppError, ErrorCodes } from "../types/index.js";
import { config } from "../config.js";
import { validateBody } from "../middleware/validate.js";
import {
  CreateConversationSchema,
  UpdateConversationSchema,
  CreateConversationInput,
  UpdateConversationInput,
  AddTagSchema,
  AddTagInput,
} from "../middleware/validation.js";
import { createLimiter } from "../middleware/rateLimit.js";

const router = Router();

/**
 * GET /api/conversations
 * Returns all conversations, optionally filtered by search query
 */
router.get("/", (req, res, next) => {
  try {
    const { q } = req.query;

    const conversations =
      typeof q === "string" && q.trim()
        ? searchConversations(q.trim())
        : getAllConversations();

    res.json({ conversations });
  } catch (error) {
    next(error);
  }
});

/**
 * POST /api/conversations
 * Creates a new conversation
 */
router.post("/", createLimiter, validateBody(CreateConversationSchema), async (req, res, next) => {
  try {
    const body = req.body as CreateConversationInput;
    const id = `conv_${uuidv4()}`;
    const title = body.title || "New Conversation";
    const agent = body.agent || null;

    // Determine model preference:
    // 1) use provided model (body.model)
    // 2) prefer configured default if present in SDK models
    // 3) otherwise use first model returned by SDK (multiplier may be forced to 0.0)
    // 4) fallback to configured default when SDK is unavailable
    let selectedModel: string | null = body.model ?? null;
    try {
      const models = await copilotService.listModels();
      if (!selectedModel) {
        const defaultModelId = config.defaults.model;
        const defaultInList = models.some((m) => m.id === defaultModelId);
        if (defaultInList) {
          selectedModel = defaultModelId;
        } else if (models.length > 0) {
          // Prefer a model that already has multiplier === 0 (e.g., no cost) if available
          const zeroModel = models.find((m) => m.multiplier === 0 || m.multiplier === 0.0);
          if (zeroModel) {
            console.log(`AUDIT: Default model '${defaultModelId}' not found; falling back to zero-multiplier model: ${zeroModel.id}`);
            selectedModel = zeroModel.id;
          } else {
            // Otherwise use the first model in the list
            selectedModel = models[0].id;
          }
        } else {
          selectedModel = config.defaults.model;
        }
      }
    } catch (err) {
      // Listing models failed; fall back to configured default or provided model
      selectedModel = selectedModel ?? config.defaults.model;
    }

    // Create conversation in database
    const conversation = createConversation(id, title, selectedModel, agent);

    // Create SDK session
    await copilotService.createSession(id, selectedModel);

    // Update conversation with session ID
    updateConversation(id, { sessionId: id });

    res.status(201).json(conversation);
  } catch (error) {
    next(error);
  }
});

/**
 * GET /api/conversations/:id
 * Returns a specific conversation by ID
 */
router.get("/:id", (req, res, next) => {
  try {
    const { id } = req.params;
    const conversation = getConversationById(id);

    if (!conversation) {
      throw new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    }

    // Include session stats if available
    const sessionStats = copilotService.getSessionStats(id);

    res.json({
      ...conversation,
      session: sessionStats.exists
        ? {
            active: true,
            model: sessionStats.model,
            messageCount: sessionStats.messageCount,
            idleTimeMs: sessionStats.idleTimeMs,
          }
        : { active: false },
    });
  } catch (error) {
    next(error);
  }
});

/**
 * PUT /api/conversations/:id
 * Updates a conversation (rename, change model, tags)
 */
router.put("/:id", validateBody(UpdateConversationSchema), async (req, res, next) => {
  try {
    const { id } = req.params;
    const body = req.body as UpdateConversationInput;

    const existing = getConversationById(id);
    if (!existing) {
      throw new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    }

    // Update model in SDK session if changed
    if (body.model && body.model !== existing.model) {
      // Get existing messages for context preservation
      const messages = getMessagesForConversation(id);
      const historyForContext = messages.map((m) => ({
        role: m.role,
        content: m.content,
      }));

      // Check if session exists, if not just update the DB (session will be created on next message)
      const hasSession = copilotService.hasSession(id);
      
      if (hasSession) {
        const modelUpdated = await copilotService.updateSessionModel(
          id,
          body.model,
          historyForContext
        );

        if (!modelUpdated) {
          throw new AppError(
            ErrorCodes.MODEL_SWITCH_FAILED,
            `Failed to switch model to ${body.model}`,
            500
          );
        }
      }
      // If no session exists, model will be used when session is created on next message
    }

    const updated = updateConversation(id, {
      title: body.title,
      model: body.model,
      agent: body.agent ?? undefined,
    });
    res.json(updated);
  } catch (error) {
    next(error);
  }
});

/**
 * DELETE /api/conversations/:id
 * Deletes a specific conversation
 */
router.delete("/:id", async (req, res, next) => {
  try {
    const { id } = req.params;

    const deleted = deleteConversation(id);
    if (!deleted) {
      throw new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    }

    // Destroy SDK session (ignore errors - conversation already deleted)
    try {
      await copilotService.destroySession(id);
    } catch {
      // Session might not exist, which is fine
    }

    res.status(204).send();
  } catch (error) {
    next(error);
  }
});

/**
 * DELETE /api/conversations
 * Deletes all conversations
 */
router.delete("/", (_req, res, next) => {
  try {
    const count = deleteAllConversations();
    res.json({ deleted: count });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Tag Routes
// ============================================================================

/**
 * POST /api/conversations/:id/tags
 * Adds a tag to a conversation (creates tag if it doesn't exist)
 */
router.post("/:id/tags", validateBody(AddTagSchema), (req, res, next) => {
  try {
    const { id } = req.params;
    const body = req.body as AddTagInput;

    const conversation = getConversationById(id);
    if (!conversation) {
      throw new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    }

    // Check if tag already exists by name
    const existingTags = getAllTags();
    let tag = existingTags.find(
      (t) => t.name.toLowerCase() === body.name.toLowerCase()
    );

    // Create tag if it doesn't exist
    if (!tag) {
      tag = createTag(body.name, body.color || null);
    }

    // Add tag to conversation
    const added = addTagToConversation(id, tag.id);
    if (!added) {
      // Tag already associated with this conversation - not an error, just return current state
    }

    // Return updated conversation
    const updated = getConversationById(id);
    res.status(201).json(updated);
  } catch (error) {
    next(error);
  }
});

/**
 * DELETE /api/conversations/:id/tags/:tagId
 * Removes a tag from a conversation
 */
router.delete("/:id/tags/:tagId", (req, res, next) => {
  try {
    const { id, tagId } = req.params;
    const tagIdNum = parseInt(tagId, 10);

    if (isNaN(tagIdNum)) {
      throw new AppError(ErrorCodes.INVALID_REQUEST, "Invalid tag ID", 400);
    }

    const conversation = getConversationById(id);
    if (!conversation) {
      throw new AppError(ErrorCodes.CONVERSATION_NOT_FOUND, "Conversation not found", 404);
    }

    removeTagFromConversation(id, tagIdNum);

    // Return updated conversation
    const updated = getConversationById(id);
    res.json(updated);
  } catch (error) {
    next(error);
  }
});

export default router;
