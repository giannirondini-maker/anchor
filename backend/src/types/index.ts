/**
 * Type definitions for Anchor backend
 */

// ============================================================================
// Conversation Types
// ============================================================================

export interface Conversation {
  id: string;
  title: string;
  createdAt: Date;
  updatedAt: Date;
  model: string | null;
  agent: string | null;
  sessionId: string | null;
  tags: Tag[];
}

export interface ConversationRow {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
  model: string | null;
  agent: string | null;
  session_id: string | null;
}

export interface CreateConversationRequest {
  title?: string;
  model?: string;
  agent?: string;
}

export interface UpdateConversationRequest {
  title?: string;
  model?: string;
  agent?: string;
}

// ============================================================================
// Message Types
// ============================================================================

export type MessageRole = "user" | "assistant" | "system";
export type MessageStatus = "sending" | "sent" | "error";

export interface Message {
  id: string;
  conversationId: string;
  role: MessageRole;
  content: string;
  createdAt: Date;
  status: MessageStatus;
  errorMessage: string | null;
}

export interface MessageRow {
  id: string;
  conversation_id: string;
  role: MessageRole;
  content: string;
  created_at: string;
  status: MessageStatus;
  error_message: string | null;
}

export interface SendMessageRequest {
  content: string;
  attachments?: MessageAttachmentReference[];
}

export interface SendMessageResponse {
  messageId: string;
  status: "streaming";
}

export interface MessageAttachmentReference {
  id: string;
  displayName?: string;
}

export interface AttachmentMetadata {
  id: string;
  conversationId: string;
  originalName: string;
  displayName: string;
  size: number;
  mimeType: string;
  createdAt: string;
}

export interface AttachmentUploadResponse {
  attachments: AttachmentMetadata[];
}

export interface AttachmentUpdateRequest {
  displayName: string;
}

// ============================================================================
// Tag Types
// ============================================================================

export interface Tag {
  id: number;
  name: string;
  color: string | null;
}

export interface TagRow {
  id: number;
  name: string;
  color: string | null;
}

// ============================================================================
// Model Types
// ============================================================================

// Model capabilities from SDK
export interface ModelCapabilities {
  supports: {
    vision: boolean;
  };
  limits: {
    max_prompt_tokens?: number;
    max_context_window_tokens: number;
    vision?: {
      supported_media_types: string[];
      max_prompt_images: number;
      max_prompt_image_size: number;
    };
  };
}

// Model billing info from SDK
export interface ModelBilling {
  multiplier: number;
}

// Model policy from SDK
export interface ModelPolicy {
  state: "enabled" | "disabled" | "unconfigured";
  terms: string;
}

// Full model info matching SDK structure
export interface ModelInfo {
  id: string;
  name: string;
  capabilities: ModelCapabilities;
  policy?: ModelPolicy;
  billing?: ModelBilling;
}

// Simplified model info for frontend
export interface ModelInfoSimple {
  id: string;
  name: string;
  multiplier: number;
  supportsVision: boolean;
  maxContextTokens: number;
  enabled: boolean;
}

export interface ModelsResponse {
  models: ModelInfoSimple[];
}

// ============================================================================
// Agent Types
// ============================================================================

export interface AgentInfo {
  id: string;
  name: string;
  description: string;
}

export interface AgentsResponse {
  agents: AgentInfo[];
}

// ============================================================================
// Health & Auth Types
// ============================================================================

export interface HealthResponse {
  status: "healthy" | "unhealthy";
  version: string;
  sdk: {
    connected: boolean;
    authenticated: boolean;
  };
}

export interface AuthStatusResponse {
  authenticated: boolean;
  user?: string;
  message?: string;
}

// ============================================================================
// Error Types
// ============================================================================

export interface ApiError {
  code: string;
  message: string;
  details?: unknown;
}

export class AppError extends Error {
  constructor(
    public code: string,
    message: string,
    public statusCode: number = 500,
    public details?: unknown
  ) {
    super(message);
    this.name = "AppError";
  }

  toJSON(): ApiError {
    return {
      code: this.code,
      message: this.message,
      details: this.details,
    };
  }
}

// ============================================================================
// WebSocket Event Types
// ============================================================================

export type WebSocketEventType =
  | "message:start"
  | "message:delta"
  | "message:complete"
  | "message:error"
  | "session:idle"
  | "pong";

export interface WebSocketEvent<T = unknown> {
  event: WebSocketEventType;
  data: T;
}

export interface MessageStartEvent {
  messageId: string;
}

export interface MessageDeltaEvent {
  messageId: string;
  content: string;
}

export interface MessageCompleteEvent {
  messageId: string;
  fullContent: string;
}

export interface MessageErrorEvent {
  messageId: string;
  error: string;
}

// ============================================================================
// SDK Types (placeholder until actual SDK is integrated)
// ============================================================================

export interface CopilotSessionOptions {
  sessionId: string;
  model: string;
  streaming: boolean;
}

export interface CopilotMessage {
  role: MessageRole;
  content: string;
}

// ============================================================================
// Error Codes
// ============================================================================

export const ErrorCodes = {
  // SDK Errors
  SDK_NOT_INSTALLED: "SDK_NOT_INSTALLED",
  SDK_NOT_AUTHENTICATED: "SDK_NOT_AUTHENTICATED",
  SDK_CONNECTION_FAILED: "SDK_CONNECTION_FAILED",
  SDK_SESSION_ERROR: "SDK_SESSION_ERROR",

  // Session Errors
  SESSION_NOT_FOUND: "SESSION_NOT_FOUND",
  SESSION_CREATE_FAILED: "SESSION_CREATE_FAILED",
  SESSION_RESUME_FAILED: "SESSION_RESUME_FAILED",

  // Model Errors
  MODEL_NOT_AVAILABLE: "MODEL_NOT_AVAILABLE",
  MODEL_SWITCH_FAILED: "MODEL_SWITCH_FAILED",

  // Conversation Errors
  CONVERSATION_NOT_FOUND: "CONVERSATION_NOT_FOUND",
  CONVERSATION_CREATE_FAILED: "CONVERSATION_CREATE_FAILED",

  // Message Errors
  MESSAGE_NOT_FOUND: "MESSAGE_NOT_FOUND",
  MESSAGE_SEND_FAILED: "MESSAGE_SEND_FAILED",
  INVALID_MESSAGE_CONTENT: "INVALID_MESSAGE_CONTENT",

  // Attachment Errors
  ATTACHMENT_NOT_FOUND: "ATTACHMENT_NOT_FOUND",
  ATTACHMENT_INVALID: "ATTACHMENT_INVALID",
  ATTACHMENT_TOO_LARGE: "ATTACHMENT_TOO_LARGE",
  ATTACHMENT_LIMIT_EXCEEDED: "ATTACHMENT_LIMIT_EXCEEDED",
  ATTACHMENT_UPLOAD_FAILED: "ATTACHMENT_UPLOAD_FAILED",

  // General Errors
  INVALID_REQUEST: "INVALID_REQUEST",
  DATABASE_ERROR: "DATABASE_ERROR",
  NETWORK_ERROR: "NETWORK_ERROR",
  QUOTA_EXCEEDED: "QUOTA_EXCEEDED",
  INTERNAL_ERROR: "INTERNAL_ERROR",
} as const;

export type ErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes];

// ============================================================================
// Context Injection Types
// ============================================================================

export interface ConversationContext {
  conversationId: string;
  model: string;
  messages: CopilotMessage[];
  systemPrompt?: string;
}

export interface SessionResumeOptions {
  conversationId: string;
  model: string;
  injectHistory: boolean;
  maxHistoryMessages?: number;
}
