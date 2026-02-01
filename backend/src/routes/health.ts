/**
 * Health Check Routes
 */

import { Router } from "express";
import { config } from "../config.js";
import { copilotService } from "../services/copilot.service.js";
import { HealthResponse } from "../types/index.js";

const router = Router();

/**
 * GET /api/health
 * Returns the health status of the server and SDK
 */
router.get("/", async (_req, res, next) => {
  try {
    const authStatus = await copilotService.getAuthStatus();

    const response: HealthResponse = {
      status: authStatus.connected ? "healthy" : "unhealthy",
      version: config.app.version,
      sdk: {
        connected: authStatus.connected,
        authenticated: authStatus.authenticated,
      },
    };

    const statusCode = authStatus.connected ? 200 : 503;
    res.status(statusCode).json(response);
  } catch (error) {
    next(error);
  }
});

export default router;
