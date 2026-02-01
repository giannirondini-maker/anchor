/**
 * Authentication Status Routes
 */

import { Router } from "express";
import { copilotService } from "../services/copilot.service.js";
import { AuthStatusResponse } from "../types/index.js";

const router = Router();

/**
 * GET /api/auth/status
 * Returns the authentication status of the Copilot CLI
 */
router.get("/status", async (_req, res, next) => {
  try {
    const authStatus = await copilotService.getAuthStatus();

    const response: AuthStatusResponse = {
      authenticated: authStatus.authenticated,
      user: authStatus.user,
      message: authStatus.authenticated
        ? authStatus.statusMessage || "Successfully authenticated with Copilot"
        : authStatus.statusMessage || "Not authenticated. Please run 'copilot auth login' to authenticate.",
    };

    res.json(response);
  } catch (error) {
    next(error);
  }
});

export default router;
