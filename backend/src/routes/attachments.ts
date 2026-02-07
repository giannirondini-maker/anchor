/**
 * Attachments Routes
 */

import { Router } from "express";
import multer from "multer";
import path from "path";
import fs from "fs";
import { config } from "../config.js";
import { attachmentService } from "../services/attachment.service.js";
import { AppError, ErrorCodes, AttachmentUpdateRequest, AttachmentUploadResponse } from "../types/index.js";

const router = Router();

const tempDir = path.join(config.attachments.dir, "tmp");
if (!fs.existsSync(tempDir)) {
  fs.mkdirSync(tempDir, { recursive: true });
}

const upload = multer({
  dest: tempDir,
  limits: {
    fileSize: config.attachments.maxFileSizeBytes,
  },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const allowedExt = config.attachments.allowedExtensions.includes(ext);
    const allowedMime = config.attachments.allowedMimeTypes.includes(file.mimetype);

    if (!allowedExt || !allowedMime) {
      cb(new AppError(ErrorCodes.ATTACHMENT_INVALID, "Unsupported attachment type", 400));
      return;
    }

    cb(null, true);
  },
});

/**
 * POST /api/attachments
 * Upload a single attachment
 */
router.post("/", upload.single("file"), (req, res, next) => {
  try {
    attachmentService.purgeExpired();

    const conversationId = String(req.body.conversationId || "");
    const displayName = req.body.displayName ? String(req.body.displayName) : undefined;

    if (!conversationId) {
      throw new AppError(ErrorCodes.INVALID_REQUEST, "conversationId is required", 400);
    }

    if (!req.file) {
      throw new AppError(ErrorCodes.ATTACHMENT_UPLOAD_FAILED, "Attachment upload failed", 400);
    }

    attachmentService.validateUpload(
      conversationId,
      req.file.originalname,
      req.file.mimetype,
      req.file.size
    );

    const metadata = attachmentService.registerAttachment(conversationId, req.file, displayName);

    const response: AttachmentUploadResponse = { attachments: [metadata] };
    res.status(201).json(response);
  } catch (error) {
    if (req.file?.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    next(error);
  }
});

/**
 * PUT /api/attachments/:id
 * Update display name
 */
router.put("/:id", (req, res, next) => {
  try {
    const { id } = req.params;
    const body = req.body as AttachmentUpdateRequest;

    if (!body?.displayName) {
      throw new AppError(ErrorCodes.INVALID_REQUEST, "displayName is required", 400);
    }

    const metadata = attachmentService.updateDisplayName(id, body.displayName);
    res.json(metadata);
  } catch (error) {
    next(error);
  }
});

/**
 * DELETE /api/attachments/:id
 * Delete a staged attachment
 */
router.delete("/:id", (req, res, next) => {
  try {
    const { id } = req.params;
    attachmentService.removeAttachment(id);
    res.status(204).send();
  } catch (error) {
    next(error);
  }
});

export default router;
