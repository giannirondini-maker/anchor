/**
 * Agents Routes
 */

import { Router } from "express";
import { copilotService } from "../services/copilot.service.js";
import { AgentsResponse } from "../types/index.js";

const router = Router();

/**
 * GET /api/agents
 * Returns the list of available custom agents
 */
router.get("/", async (_req, res, next) => {
  try {
    const agents = await copilotService.listAgents();

    const response: AgentsResponse = {
      agents,
    };

    res.json(response);
  } catch (error) {
    next(error);
  }
});

export default router;
