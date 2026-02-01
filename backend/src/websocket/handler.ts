/**
 * WebSocket Handler
 *
 * Manages WebSocket connections for real-time message streaming.
 */

import { WebSocketServer, WebSocket } from "ws";
import { IncomingMessage } from "http";
import { WebSocketEvent, WebSocketEventType } from "../types/index.js";

// Map of conversation ID -> Set of connected WebSocket clients
const clients = new Map<string, Set<WebSocket>>();

/**
 * Set up WebSocket server event handlers
 */
export function setupWebSocket(wss: WebSocketServer): void {
  wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
    // Parse conversation ID from URL
    const url = new URL(req.url || "", `http://${req.headers.host}`);
    const conversationId = url.searchParams.get("conversationId");

    if (!conversationId) {
      console.log("❌ WebSocket connection rejected: missing conversationId");
      ws.close(1008, "conversationId query parameter is required");
      return;
    }

    console.log(`🔌 WebSocket connected for conversation: ${conversationId}`);

    // Register client for this conversation
    if (!clients.has(conversationId)) {
      clients.set(conversationId, new Set());
    }
    clients.get(conversationId)!.add(ws);

    // Send welcome message to confirm connection
    sendToClient(ws, "session:idle", {});

    // Handle WebSocket ping/pong for keep-alive
    // The 'ws' library automatically responds to ping frames with pong frames
    // We can also listen for pong responses if we send pings from server
    ws.on("pong", () => {
      console.log(`🏓 Pong received from conversation: ${conversationId}`);
    });

    // Handle incoming messages
    ws.on("message", (data: Buffer) => {
      try {
        const message = JSON.parse(data.toString());
        console.log(
          `📨 WebSocket message from ${conversationId}:`,
          message
        );
        
        // Handle application-level ping (if client sends JSON ping)
        if (message.type === "ping") {
          sendToClient(ws, "pong", { timestamp: Date.now() });
          return;
        }
        
        // Handle other client messages if needed
      } catch (error) {
        console.error("Failed to parse WebSocket message:", error);
      }
    });

    // Handle disconnect
    ws.on("close", (code: number, reason: Buffer) => {
      const reasonStr = reason.toString() || "none";
      console.log(`🔌 WebSocket disconnected for conversation: ${conversationId} (code: ${code}, reason: ${reasonStr})`);
      clients.get(conversationId)?.delete(ws);

      // Clean up empty sets
      if (clients.get(conversationId)?.size === 0) {
        clients.delete(conversationId);
      }
    });

    // Handle errors
    ws.on("error", (error) => {
      console.error(`WebSocket error for ${conversationId}:`, error);
      clients.get(conversationId)?.delete(ws);
    });
  });

  console.log("🔌 WebSocket server initialized");
}

/**
 * Send a message to a specific WebSocket client
 */
function sendToClient<T>(ws: WebSocket, event: WebSocketEventType, data: T): void {
  if (ws.readyState === WebSocket.OPEN) {
    const message: WebSocketEvent<T> = { event, data };
    ws.send(JSON.stringify(message));
  }
}

/**
 * Broadcast a message to all clients connected to a conversation
 */
export function broadcastToConversation<T>(
  conversationId: string,
  event: WebSocketEventType,
  data: T
): void {
  const sockets = clients.get(conversationId);
  if (!sockets) {
    return;
  }

  const message: WebSocketEvent<T> = { event, data };
  const messageStr = JSON.stringify(message);

  sockets.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(messageStr);
    }
  });
}

/**
 * Get the number of connected clients for a conversation
 */
export function getClientCount(conversationId: string): number {
  return clients.get(conversationId)?.size || 0;
}

/**
 * Get total number of connected clients across all conversations
 */
export function getTotalClientCount(): number {
  let total = 0;
  clients.forEach((set) => {
    total += set.size;
  });
  return total;
}
