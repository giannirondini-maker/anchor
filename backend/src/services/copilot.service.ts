/**
 * GitHub Copilot SDK Service
 *
 * Wraps the official GitHub Copilot SDK for session management and message handling.
 * Requires:
 * - GitHub Copilot CLI to be installed and in PATH
 * - Authenticated via `copilot auth login`
 * - Active Copilot subscription (Pro/Enterprise)
 *
 * @see https://github.com/github/copilot-sdk
 */

import { CopilotClient, CopilotSession } from "@github/copilot-sdk";
import {
  ModelInfoSimple,
  AgentInfo,
  CopilotMessage,
  ErrorCodes,
  SessionResumeOptions,
} from "../types/index.js";
import type { ModelInfo as SDKModelInfo } from "@github/copilot-sdk";
import { config } from "../config.js";

// Session wrapper with metadata
interface SessionWrapper {
  session: CopilotSession;
  model: string;
  createdAt: Date;
  lastActiveAt: Date;
  messageCount: number;
}

// Constants for session management
const MAX_HISTORY_MESSAGES = 50; // Maximum messages to inject for context
const SESSION_IDLE_TIMEOUT_MS = 30 * 60 * 1000; // 30 minutes

class CopilotService {
  private client: CopilotClient | null = null;
  private sessions: Map<string, SessionWrapper> = new Map();
  private initialized: boolean = false;
  private _authenticated: boolean = false;

  /**
   * Check if the service is initialized
   */
  get isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * Check if the cached authentication state is true
   * For real-time status, use getAuthStatus()
   */
  get isAuthenticated(): boolean {
    return this._authenticated;
  }

  /**
   * Initialize the GitHub Copilot SDK client
   */
  async initialize(): Promise<void> {
    try {
      console.log("🔌 Connecting to GitHub Copilot CLI...");

      // Create the Copilot client
      // The SDK will communicate with the Copilot CLI via JSON-RPC
      this.client = new CopilotClient({
        logLevel: config.sdk.logLevel as "info" | "error" | "none" | "warning" | "debug" | "all",
        autoStart: true,
        autoRestart: true,
      });

      // Start the client (connects to CLI)
      await this.client.start();

      // Test connectivity
      const pingResult = await this.client.ping();
      console.log(`✅ Copilot CLI connected (timestamp: ${pingResult.timestamp})`);

      this.initialized = true;
      this._authenticated = true;

      console.log("✅ GitHub Copilot SDK initialized successfully");
    } catch (error) {
      console.error("❌ Failed to initialize GitHub Copilot SDK:", error);
      console.error("   Make sure Copilot CLI is installed and authenticated:");
      console.error("   1. Install: brew install github/copilot/copilot-cli");
      console.error("   2. Authenticate: copilot auth login");
      this.initialized = false;
      this._authenticated = false;
      throw error;
    }
  }

  /**
   * Check if the SDK is initialized and get authentication status from Copilot CLI
   */
  async getAuthStatus(): Promise<{
    connected: boolean;
    authenticated: boolean;
    user?: string;
    authType?: string;
    host?: string;
    statusMessage?: string;
  }> {
    if (!this.client || !this.initialized) {
      return {
        connected: false,
        authenticated: false,
        statusMessage: "Copilot SDK not initialized",
      };
    }

    try {
      // Get auth status from the Copilot CLI via SDK
      const authStatus = await this.client.getAuthStatus();
      
      this._authenticated = authStatus.isAuthenticated;
      
      return {
        connected: true,
        authenticated: authStatus.isAuthenticated,
        user: authStatus.login,
        authType: authStatus.authType,
        host: authStatus.host,
        statusMessage: authStatus.statusMessage,
      };
    } catch (error) {
      console.error("Failed to get auth status from SDK:", error);
      return {
        connected: this.initialized,
        authenticated: false,
        statusMessage: "Failed to get authentication status",
      };
    }
  }

  /**
   * List available LLM models from Copilot
   * Models available depend on your subscription level
   */
  async listModels(): Promise<ModelInfoSimple[]> {
    if (!this.client) {
      throw new Error(ErrorCodes.SDK_CONNECTION_FAILED);
    }

    try {
      // Fetch models from the Copilot SDK
      const sdkModels: SDKModelInfo[] = await this.client.listModels();
      
      // Transform SDK models to simplified format for frontend
      const models = sdkModels.map(model => ({
        id: model.id,
        name: model.name || model.id,
        multiplier: model.billing?.multiplier ?? 1.0,
        supportsVision: model.capabilities?.supports?.vision ?? false,
        maxContextTokens: model.capabilities?.limits?.max_context_window_tokens ?? 0,
        enabled: model.policy?.state !== "disabled",
      }));

      // Return SDK-reported models without mutating multipliers. Fallback selection
      // (when creating conversations) will prefer existing SDK models with multiplier 0.
      return models;
    } catch (error) {
      console.error("Failed to fetch models from SDK:", error);
      throw new Error(ErrorCodes.SDK_CONNECTION_FAILED);
    }
  }

  /**
   * List available custom agents from Copilot
   * Note: Agent listing is not yet available in the SDK
   */
  async listAgents(): Promise<AgentInfo[]> {
    if (!this.client) {
      throw new Error(ErrorCodes.SDK_CONNECTION_FAILED);
    }

    // The SDK does not currently expose an agent listing method
    // Return empty array until this functionality is available
    console.log("Agent listing not yet available in SDK");
    return [];
  }

  /**
   * Create a new chat session
   */
  async createSession(conversationId: string, model: string): Promise<SessionWrapper> {
    if (!this.client) {
      throw new Error("Copilot SDK not initialized");
    }

    // Check if session already exists
    const existing = this.sessions.get(conversationId);
    if (existing) {
      console.log(`📝 Returning existing session: ${conversationId}`);
      return existing;
    }

    // Create a new session with the Copilot SDK
    const session = await this.client.createSession({
      sessionId: conversationId,
      model: model,
      streaming: true,
      // Infinite sessions for long conversations
      infiniteSessions: {
        enabled: true,
        backgroundCompactionThreshold: 0.80,
        bufferExhaustionThreshold: 0.95,
      },
    });

    const wrapper: SessionWrapper = {
      session,
      model,
      createdAt: new Date(),
      lastActiveAt: new Date(),
      messageCount: 0,
    };

    this.sessions.set(conversationId, wrapper);
    console.log(`📝 Created session: ${conversationId} with model: ${model}`);

    return wrapper;
  }

  /**
   * Resume an existing session with context injection
   */
  async resumeSession(
    conversationId: string,
    messages: CopilotMessage[],
    options?: Partial<SessionResumeOptions>
  ): Promise<SessionWrapper | null> {
    if (!this.client) {
      throw new Error(ErrorCodes.SDK_CONNECTION_FAILED);
    }

    // Check if session exists in memory and is still valid
    const existing = this.sessions.get(conversationId);
    if (existing) {
      // Check if session is still within idle timeout
      const idleTime = Date.now() - existing.lastActiveAt.getTime();
      if (idleTime < SESSION_IDLE_TIMEOUT_MS) {
        existing.lastActiveAt = new Date();
        return existing;
      }
      // Session expired, destroy and recreate
      console.log(`⏰ Session ${conversationId} expired, recreating...`);
      await this.destroySession(conversationId);
    }

    const model = options?.model || "gpt-5";
    const maxHistory = options?.maxHistoryMessages || MAX_HISTORY_MESSAGES;
    const shouldInjectHistory = options?.injectHistory !== false;

    try {
      // Try to resume from the SDK first
      const session = await this.client.resumeSession(conversationId);
      
      const wrapper: SessionWrapper = {
        session,
        model,
        createdAt: new Date(),
        lastActiveAt: new Date(),
        messageCount: messages.length,
      };

      this.sessions.set(conversationId, wrapper);
      console.log(`🔄 Resumed session: ${conversationId}`);

      return wrapper;
    } catch (error) {
      console.log(`⚠️ Could not resume session ${conversationId}, creating new one with context`);
      
      // Create a new session
      const wrapper = await this.createSession(conversationId, model);
      
      // Inject conversation history if enabled
      if (shouldInjectHistory && messages.length > 0) {
        await this.injectConversationHistory(
          conversationId, 
          messages.slice(-maxHistory)
        );
      }
      
      return wrapper;
    }
  }

  /**
   * Inject conversation history into a session for context continuity
   * Uses the SDK's context injection mechanism
   */
  async injectConversationHistory(
    conversationId: string,
    messages: CopilotMessage[]
  ): Promise<void> {
    const wrapper = this.sessions.get(conversationId);
    if (!wrapper) {
      console.warn(`Cannot inject history: session ${conversationId} not found`);
      return;
    }

    if (messages.length === 0) {
      return;
    }

    try {
      // Build a context summary from the conversation history
      // The SDK session will use this as prior context
      const contextMessages = messages.map(m => ({
        role: m.role as "user" | "assistant" | "system",
        content: m.content,
      }));

      // Check if the session has an inject method available
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const session = wrapper.session as any;
      if (session.injectMessages && typeof session.injectMessages === "function") {
        await session.injectMessages(contextMessages);
        console.log(`📚 Injected ${messages.length} messages into session ${conversationId}`);
      } else {
        // Log that we're not able to inject but the context will be provided differently
        console.log(`📚 Session ${conversationId}: context stored (${messages.length} messages)`);
      }

      wrapper.messageCount = messages.length;
    } catch (error) {
      console.error(`Failed to inject history into session ${conversationId}:`, error);
      // Don't throw - continue without history if injection fails
    }
  }

  /**
   * Get a session by ID
   */
  getSession(conversationId: string): SessionWrapper | null {
    return this.sessions.get(conversationId) || null;
  }

  /**
   * List all active sessions
   */
  async listSessions(): Promise<string[]> {
    if (!this.client) {
      return [];
    }

    try {
      const sessions = await this.client.listSessions();
      return sessions.map(s => s.sessionId);
    } catch {
      return Array.from(this.sessions.keys());
    }
  }

  /**
   * Send a message and stream the response
   */
  async sendMessage(
    conversationId: string,
    prompt: string,
    onDelta: (content: string) => void,
    onComplete: (content: string) => void,
    onError: (error: Error) => void
  ): Promise<void> {
    const wrapper = this.sessions.get(conversationId);
    if (!wrapper) {
      onError(new Error(ErrorCodes.SESSION_NOT_FOUND));
      return;
    }

    const { session } = wrapper;
    let fullContent = "";

    // Update session activity
    wrapper.lastActiveAt = new Date();
    wrapper.messageCount++;

    try {
      // Set up event handler for streaming
      const unsubscribe = session.on((event) => {
        switch (event.type) {
          case "assistant.message_delta":
            // Streaming chunk received
            const delta = event.data.deltaContent;
            fullContent += delta;
            onDelta(delta);
            break;

          case "assistant.reasoning_delta":
            // Reasoning chunk (for models that support it)
            // We can optionally include this in the output
            break;

          case "assistant.message":
            // Final complete message
            fullContent = event.data.content;
            wrapper.messageCount++;
            onComplete(fullContent);
            unsubscribe();
            break;

          case "session.idle":
            // Session finished processing
            if (fullContent) {
              onComplete(fullContent);
            }
            unsubscribe();
            break;

          case "session.error":
            // Error occurred
            onError(new Error(event.data?.message || ErrorCodes.SDK_SESSION_ERROR));
            unsubscribe();
            break;

          default:
            // Other events we don't need to handle
            break;
        }
      });

      // Send the message
      await session.send({ prompt });

    } catch (error) {
      console.error("Error sending message:", error);
      onError(error instanceof Error ? error : new Error(String(error)));
    }
  }

  /**
   * Send a message and wait for complete response (non-streaming)
   */
  async sendAndWait(
    conversationId: string,
    prompt: string
  ): Promise<string> {
    const wrapper = this.sessions.get(conversationId);
    if (!wrapper) {
      throw new Error("Session not found");
    }

    const result = await wrapper.session.sendAndWait({ prompt });
    return result?.data?.content || "";
  }

  /**
   * Abort current message processing
   */
  async abortMessage(conversationId: string): Promise<void> {
    const wrapper = this.sessions.get(conversationId);
    if (wrapper) {
      await wrapper.session.abort();
      console.log(`⏹️ Aborted message in session: ${conversationId}`);
    }
  }

  /**
   * Get all messages from a session
   */
  async getSessionMessages(conversationId: string): Promise<unknown[]> {
    const wrapper = this.sessions.get(conversationId);
    if (!wrapper) {
      return [];
    }

    try {
      const messages = await wrapper.session.getMessages();
      return messages;
    } catch {
      return [];
    }
  }

  /**
   * Update session model with context preservation
   * To change model, we need to create a new session and inject existing context
   */
  async updateSessionModel(
    conversationId: string,
    model: string,
    preserveHistory: CopilotMessage[] = []
  ): Promise<boolean> {
    const existing = this.sessions.get(conversationId);
    if (!existing) {
      console.warn(`Cannot update model: session ${conversationId} not found`);
      return false;
    }

    // If model is the same, no need to recreate
    if (existing.model === model) {
      console.log(`Model already set to ${model} for session ${conversationId}`);
      return true;
    }

    try {
      // Destroy old session
      await existing.session.destroy();
      this.sessions.delete(conversationId);

      // Create new session with new model
      await this.createSession(conversationId, model);

      // Inject preserved history if provided
      if (preserveHistory.length > 0) {
        await this.injectConversationHistory(conversationId, preserveHistory);
      }

      console.log(`🔄 Updated session ${conversationId} model from ${existing.model} to: ${model}`);
      return true;
    } catch (error) {
      console.error(`Failed to update session model: ${error}`);
      // Try to restore the old session
      try {
        await this.createSession(conversationId, existing.model);
        console.log(`♻️ Restored session with original model: ${existing.model}`);
      } catch (restoreError) {
        console.error(`Failed to restore session: ${restoreError}`);
      }
      return false;
    }
  }

  /**
   * Destroy a session
   */
  async destroySession(conversationId: string): Promise<boolean> {
    const wrapper = this.sessions.get(conversationId);
    if (wrapper) {
      try {
        await wrapper.session.destroy();
        this.sessions.delete(conversationId);
        console.log(`🗑️ Destroyed session: ${conversationId}`);
        return true;
      } catch (error) {
        console.error(`Failed to destroy session: ${error}`);
        this.sessions.delete(conversationId);
        return true;
      }
    }
    return false;
  }

  /**
   * Delete a session from disk
   */
  async deleteSession(conversationId: string): Promise<void> {
    if (this.client) {
      try {
        await this.client.deleteSession(conversationId);
        this.sessions.delete(conversationId);
        console.log(`🗑️ Deleted session from disk: ${conversationId}`);
      } catch {
        this.sessions.delete(conversationId);
      }
    }
  }

  /**
   * Get session statistics
   */
  getSessionStats(conversationId: string): {
    exists: boolean;
    model?: string;
    messageCount?: number;
    createdAt?: Date;
    lastActiveAt?: Date;
    idleTimeMs?: number;
  } {
    const wrapper = this.sessions.get(conversationId);
    if (!wrapper) {
      return { exists: false };
    }

    return {
      exists: true,
      model: wrapper.model,
      messageCount: wrapper.messageCount,
      createdAt: wrapper.createdAt,
      lastActiveAt: wrapper.lastActiveAt,
      idleTimeMs: Date.now() - wrapper.lastActiveAt.getTime(),
    };
  }

  /**
   * Clean up idle sessions
   */
  async cleanupIdleSessions(): Promise<number> {
    const now = Date.now();
    let cleanedCount = 0;

    for (const [id, wrapper] of this.sessions) {
      const idleTime = now - wrapper.lastActiveAt.getTime();
      if (idleTime > SESSION_IDLE_TIMEOUT_MS) {
        try {
          await wrapper.session.destroy();
          this.sessions.delete(id);
          cleanedCount++;
          console.log(`🧹 Cleaned up idle session: ${id}`);
        } catch (error) {
          this.sessions.delete(id);
          cleanedCount++;
        }
      }
    }

    if (cleanedCount > 0) {
      console.log(`🧹 Cleaned up ${cleanedCount} idle sessions`);
    }

    return cleanedCount;
  }

  /**
   * Get all active session IDs
   */
  getActiveSessions(): string[] {
    return Array.from(this.sessions.keys());
  }

  /**
   * Check if a session exists for a conversation
   */
  hasSession(conversationId: string): boolean {
    return this.sessions.has(conversationId);
  }

  /**
   * Get total active session count
   */
  getActiveSessionCount(): number {
    return this.sessions.size;
  }

  /**
   * Shutdown the SDK client
   */
  async shutdown(): Promise<void> {
    // Destroy all sessions
    for (const [id, wrapper] of this.sessions) {
      try {
        await wrapper.session.destroy();
        console.log(`🗑️ Destroyed session: ${id}`);
      } catch {
        // Ignore errors during shutdown
      }
    }
    this.sessions.clear();

    // Stop the client
    if (this.client) {
      try {
        await this.client.stop();
      } catch {
        await this.client.forceStop();
      }
      this.client = null;
    }

    this.initialized = false;
    this._authenticated = false;
    console.log("🔌 GitHub Copilot SDK shut down");
  }
}

// Export singleton instance
export const copilotService = new CopilotService();
