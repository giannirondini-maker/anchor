/**
 * Request Validation Schemas
 *
 * Zod schemas for validating API request bodies.
 * Provides type-safe validation with detailed error messages.
 */

import { z } from "zod";

// ============================================================================
// Conversation Schemas
// ============================================================================

/**
 * Schema for creating a new conversation
 */
export const CreateConversationSchema = z.object({
  title: z
    .string()
    .min(1, "Title cannot be empty")
    .max(200, "Title must be 200 characters or less")
    .optional(),
  model: z
    .string()
    .min(1, "Model ID cannot be empty")
    .max(100, "Model ID must be 100 characters or less")
    .optional(),
  agent: z
    .string()
    .min(1, "Agent ID cannot be empty")
    .max(100, "Agent ID must be 100 characters or less")
    .optional()
    .nullable(),
});

export type CreateConversationInput = z.infer<typeof CreateConversationSchema>;

/**
 * Schema for updating a conversation
 */
export const UpdateConversationSchema = z.object({
  title: z
    .string()
    .min(1, "Title cannot be empty")
    .max(200, "Title must be 200 characters or less")
    .optional(),
  model: z
    .string()
    .min(1, "Model ID cannot be empty")
    .max(100, "Model ID must be 100 characters or less")
    .optional(),
  agent: z
    .string()
    .min(1, "Agent ID cannot be empty")
    .max(100, "Agent ID must be 100 characters or less")
    .optional()
    .nullable(),
});

export type UpdateConversationInput = z.infer<typeof UpdateConversationSchema>;

// ============================================================================
// Message Schemas
// ============================================================================

/**
 * Schema for sending a message
 */
export const SendMessageSchema = z.object({
  content: z
    .string()
    .min(1, "Message content is required")
    .max(100000, "Message must be 100,000 characters or less")
    .refine(
      (val) => val.trim().length > 0,
      "Message content cannot be empty or only whitespace"
    ),
});

export type SendMessageInput = z.infer<typeof SendMessageSchema>;

/**
 * Schema for retrying a message (with optional edited content)
 */
export const RetryMessageSchema = z.object({
  content: z
    .string()
    .min(1, "Content cannot be empty")
    .max(100000, "Message must be 100,000 characters or less")
    .optional(),
});

export type RetryMessageInput = z.infer<typeof RetryMessageSchema>;

// ============================================================================
// Route Parameter Schemas
// ============================================================================

/**
 * Schema for conversation ID parameter
 */
export const ConversationIdSchema = z.object({
  id: z
    .string()
    .regex(/^conv_[a-f0-9-]+$/, "Invalid conversation ID format"),
});

/**
 * Schema for message ID parameter
 */
export const MessageIdSchema = z.object({
  id: z.string().regex(/^conv_[a-f0-9-]+$/, "Invalid conversation ID format"),
  messageId: z.string().regex(/^msg_[a-f0-9-]+$/, "Invalid message ID format"),
});

// ============================================================================
// Query Parameter Schemas
// ============================================================================

/**
 * Schema for search query
 */
export const SearchQuerySchema = z.object({
  q: z
    .string()
    .max(500, "Search query must be 500 characters or less")
    .optional(),
});

export type SearchQueryInput = z.infer<typeof SearchQuerySchema>;

// ============================================================================
// Tag Schemas
// ============================================================================

/**
 * Schema for adding a tag to a conversation
 */
export const AddTagSchema = z.object({
  name: z
    .string()
    .min(1, "Tag name cannot be empty")
    .max(50, "Tag name must be 50 characters or less")
    .transform((val) => val.trim()),
  color: z
    .string()
    .regex(/^#[0-9a-fA-F]{6}$/, "Color must be a valid hex color (e.g., #FF5733)")
    .optional()
    .nullable(),
});

export type AddTagInput = z.infer<typeof AddTagSchema>;

/**
 * Schema for removing a tag from a conversation
 */
export const RemoveTagSchema = z.object({
  tagId: z.number().int().positive("Tag ID must be a positive integer"),
});

export type RemoveTagInput = z.infer<typeof RemoveTagSchema>;
