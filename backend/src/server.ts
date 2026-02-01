/**
 * HTTP and WebSocket Server Configuration
 */

import express, { Express } from "express";
import { createServer as createHttpServer, Server } from "http";
import { WebSocketServer } from "ws";
import { config } from "./config.js";

// Routes
import healthRoutes from "./routes/health.js";
import authRoutes from "./routes/auth.js";
import modelsRoutes from "./routes/models.js";
import agentsRoutes from "./routes/agents.js";
import conversationsRoutes from "./routes/conversations.js";
import messagesRoutes from "./routes/messages.js";

// Middleware
import { errorHandler } from "./middleware/errorHandler.js";
import { apiLimiter, healthLimiter } from "./middleware/rateLimit.js";

// WebSocket
import { setupWebSocket } from "./websocket/handler.js";

export interface ServerInstance {
  app: Express;
  httpServer: Server;
  wss: WebSocketServer;
}

export function createServer(): ServerInstance {
  // Create Express app
  const app = express();

  // Middleware
  app.use(express.json());

  // CORS middleware
  app.use((_req, res, next) => {
    res.header("Access-Control-Allow-Origin", config.cors.origin);
    res.header(
      "Access-Control-Allow-Headers",
      "Origin, X-Requested-With, Content-Type, Accept"
    );
    res.header(
      "Access-Control-Allow-Methods",
      "GET, POST, PUT, DELETE, OPTIONS"
    );
    next();
  });

  // Request logging
  app.use((req, _res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
  });

  // Apply rate limiting (can be disabled via environment variable for development)
  if (process.env.DISABLE_RATE_LIMIT !== "true") {
    // Health and auth endpoints - higher limit
    app.use("/api/health", healthLimiter);
    app.use("/api/auth", healthLimiter);
    
    // Apply general API rate limiting
    app.use("/api", apiLimiter);
  }

  // API Routes
  app.use("/api/health", healthRoutes);
  app.use("/api/auth", authRoutes);
  app.use("/api/models", modelsRoutes);
  app.use("/api/agents", agentsRoutes);
  app.use("/api/conversations", conversationsRoutes);
  // Messages routes are nested under conversations
  app.use("/api/conversations", messagesRoutes);

  // Error handling middleware (must be last)
  app.use(errorHandler);

  // Create HTTP server
  const httpServer = createHttpServer(app);

  // Create WebSocket server
  const wss = new WebSocketServer({
    server: httpServer,
    path: "/ws",
  });

  // Setup WebSocket handlers
  setupWebSocket(wss);

  return { app, httpServer, wss };
}
