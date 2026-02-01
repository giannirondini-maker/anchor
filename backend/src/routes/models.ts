/**
 * Models Routes
 */

import { Router } from "express";
import { copilotService } from "../services/copilot.service.js";
import { ModelsResponse } from "../types/index.js";

const router = Router();

/**
 * GET /api/models
 * Returns the list of available LLM models
 */
router.get("/", async (_req, res, next) => {
  try {
    const models = await copilotService.listModels();

    const response: ModelsResponse = {
      models,
    };

    res.json(response);
  } catch (error) {
    next(error);
  }
});

export default router;
