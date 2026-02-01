/**
 * Anchor Backend - Entry Point
 *
 * Starts the HTTP/WebSocket server and initializes all services.
 */

import { createServer } from "./server.js";
import { config } from "./config.js";
import { initializeDatabase } from "./services/database.service.js";
import { copilotService } from "./services/copilot.service.js";

// Session cleanup interval (10 minutes)
const SESSION_CLEANUP_INTERVAL_MS = 10 * 60 * 1000;
let cleanupInterval: NodeJS.Timeout | null = null;

async function main(): Promise<void> {
  const envLabel = config.env.isDevelopment ? "DEVELOPMENT" : "PRODUCTION";
  console.log(`
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     ⚓ Anchor Backend - GitHub Copilot Chat Service           ║
║                                                               ║
║     Version: ${config.app.version.padEnd(46)}   ║
║     Environment: ${envLabel.padEnd(42)}   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
  `);

  try {
    // Step 1: Initialize database
    console.log("📦 Initializing database...");
    await initializeDatabase();
    console.log("✅ Database initialized");

    // Step 2: Initialize Copilot SDK
    console.log("🤖 Initializing Copilot SDK...");
    await copilotService.initialize();
    console.log("✅ Copilot SDK initialized");

    // Step 3: Start HTTP/WebSocket server
    console.log("🌐 Starting server...");
    const { httpServer } = createServer();

    httpServer.listen(config.server.port, config.server.host, () => {
      console.log(`
✅ Server is running!
   
   HTTP:      http://${config.server.host}:${config.server.port}
   WebSocket: ws://${config.server.host}:${config.server.port}/ws
   
   Health:    http://${config.server.host}:${config.server.port}/api/health
      `);
    });

    // Step 4: Start periodic session cleanup
    cleanupInterval = setInterval(async () => {
      try {
        const cleaned = await copilotService.cleanupIdleSessions();
        if (cleaned > 0) {
          console.log(`🧹 Periodic cleanup: removed ${cleaned} idle sessions`);
        }
      } catch (error) {
        console.error("Session cleanup error:", error);
      }
    }, SESSION_CLEANUP_INTERVAL_MS);
    console.log(`⏰ Session cleanup scheduled every ${SESSION_CLEANUP_INTERVAL_MS / 60000} minutes`);

    // Graceful shutdown
    const shutdown = async (signal: string) => {
      console.log(`\n⚠️  Received ${signal}. Shutting down gracefully...`);

      // Stop cleanup interval
      if (cleanupInterval) {
        clearInterval(cleanupInterval);
        cleanupInterval = null;
      }

      httpServer.close(() => {
        console.log("🔌 HTTP server closed");
      });

      await copilotService.shutdown();
      console.log("🤖 Copilot SDK stopped");

      console.log("👋 Goodbye!");
      process.exit(0);
    };

    process.on("SIGINT", () => shutdown("SIGINT"));
    process.on("SIGTERM", () => shutdown("SIGTERM"));
  } catch (error) {
    console.error("❌ Failed to start server:", error);
    process.exit(1);
  }
}

main();
