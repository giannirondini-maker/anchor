/**
 * Attachment Service
 *
 * Manages staging, validation, and preprocessing for file attachments.
 */

import fs from "fs";
import path from "path";
import { v4 as uuidv4 } from "uuid";
import { config } from "../config.js";
import { AppError, ErrorCodes, AttachmentMetadata } from "../types/index.js";

export interface AttachmentRecord {
  id: string;
  conversationId: string;
  originalName: string;
  displayName: string;
  size: number;
  mimeType: string;
  storedPath: string;
  createdAt: Date;
}

interface ConversationStats {
  count: number;
  totalSize: number;
}

class AttachmentService {
  private registry = new Map<string, AttachmentRecord>();

  constructor() {
    this.ensureBaseDir();
  }

  private ensureBaseDir(): void {
    if (!fs.existsSync(config.attachments.dir)) {
      fs.mkdirSync(config.attachments.dir, { recursive: true });
    }
  }

  private getConversationDir(conversationId: string): string {
    return path.join(config.attachments.dir, conversationId);
  }

  private ensureConversationDir(conversationId: string): void {
    const dir = this.getConversationDir(conversationId);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  private normalizeDisplayName(name: string): string {
    const safeName = path.basename(name).replace(/\s+/g, " ").trim();
    return safeName || "attachment";
  }

  private getConversationStats(conversationId: string): ConversationStats {
    let count = 0;
    let totalSize = 0;

    this.registry.forEach((record) => {
      if (record.conversationId === conversationId) {
        count += 1;
        totalSize += record.size;
      }
    });

    return { count, totalSize };
  }

  private isAllowedMimeType(mimeType: string): boolean {
    return config.attachments.allowedMimeTypes.includes(mimeType);
  }

  private isAllowedExtension(filename: string): boolean {
    const ext = path.extname(filename).toLowerCase();
    return config.attachments.allowedExtensions.includes(ext);
  }

  validateUpload(
    conversationId: string,
    filename: string,
    mimeType: string,
    size: number
  ): void {
    if (!this.isAllowedExtension(filename) || !this.isAllowedMimeType(mimeType)) {
      throw new AppError(
        ErrorCodes.ATTACHMENT_INVALID,
        "Unsupported attachment type",
        400
      );
    }

    if (size > config.attachments.maxFileSizeBytes) {
      throw new AppError(
        ErrorCodes.ATTACHMENT_TOO_LARGE,
        "Attachment exceeds maximum file size",
        400
      );
    }

    const stats = this.getConversationStats(conversationId);
    if (stats.count + 1 > config.attachments.maxFilesPerMessage) {
      throw new AppError(
        ErrorCodes.ATTACHMENT_LIMIT_EXCEEDED,
        "Too many attachments",
        400
      );
    }

    if (stats.totalSize + size > config.attachments.maxTotalSizeBytes) {
      throw new AppError(
        ErrorCodes.ATTACHMENT_LIMIT_EXCEEDED,
        "Total attachment size exceeded",
        400
      );
    }
  }

  registerAttachment(
    conversationId: string,
    file: Express.Multer.File,
    displayName?: string
  ): AttachmentMetadata {
    this.ensureConversationDir(conversationId);

    const id = `att_${uuidv4()}`;
    const normalizedName = this.normalizeDisplayName(displayName || file.originalname);
    const ext = path.extname(file.originalname).toLowerCase();
    const storedName = `${id}${ext}`;
    const targetPath = path.join(this.getConversationDir(conversationId), storedName);

    fs.renameSync(file.path, targetPath);

    const record: AttachmentRecord = {
      id,
      conversationId,
      originalName: file.originalname,
      displayName: normalizedName,
      size: file.size,
      mimeType: file.mimetype,
      storedPath: targetPath,
      createdAt: new Date(),
    };

    this.registry.set(id, record);

    return this.toMetadata(record);
  }

  updateDisplayName(id: string, displayName: string): AttachmentMetadata {
    const record = this.registry.get(id);
    if (!record) {
      throw new AppError(ErrorCodes.ATTACHMENT_NOT_FOUND, "Attachment not found", 404);
    }

    record.displayName = this.normalizeDisplayName(displayName);
    this.registry.set(id, record);

    return this.toMetadata(record);
  }

  getAttachment(id: string): AttachmentRecord | null {
    return this.registry.get(id) || null;
  }

  resolveAttachments(ids: string[], conversationId: string): AttachmentRecord[] {
    const records: AttachmentRecord[] = [];

    ids.forEach((id) => {
      const record = this.registry.get(id);
      if (!record) {
        throw new AppError(ErrorCodes.ATTACHMENT_NOT_FOUND, `Attachment ${id} not found`, 404);
      }
      if (record.conversationId !== conversationId) {
        throw new AppError(ErrorCodes.ATTACHMENT_INVALID, "Attachment does not belong to conversation", 400);
      }
      records.push(record);
    });

    return records;
  }

  removeAttachment(id: string): void {
    const record = this.registry.get(id);
    if (!record) {
      return;
    }

    try {
      if (fs.existsSync(record.storedPath)) {
        fs.unlinkSync(record.storedPath);
      }
    } catch (error) {
      console.warn(`Failed to delete attachment ${id}:`, error);
    }

    this.registry.delete(id);
  }

  removeAttachments(ids: string[]): void {
    ids.forEach((id) => this.removeAttachment(id));
  }

  purgeExpired(): void {
    const cutoff = Date.now() - config.attachments.retentionMs;

    this.registry.forEach((record, id) => {
      if (record.createdAt.getTime() < cutoff) {
        this.removeAttachment(id);
      }
    });
  }

  async buildAttachmentContext(records: AttachmentRecord[]): Promise<string> {
    if (records.length === 0) {
      return "";
    }

    const sections: string[] = [];

    for (const record of records) {
      let extracted = "";
      try {
        extracted = await this.extractText(record);
      } catch (error) {
        console.warn(`Failed to extract attachment ${record.id}:`, error);
      }
      const header = `File: ${record.displayName} (type: ${record.mimeType}, size: ${record.size} bytes)`;
      const content = extracted ? extracted : "(No extracted content available for this file type.)";
      sections.push(`${header}\n${content}`);
    }

    return `\n\n[Attachments]\n${sections.join("\n\n---\n\n")}\n[/Attachments]`;
  }

  private async extractText(record: AttachmentRecord): Promise<string> {
    const ext = path.extname(record.displayName).toLowerCase();

    if (record.mimeType.startsWith("image/")) {
      return "(Image attachment. OCR not enabled.)";
    }

    if (ext === ".pdf") {
      try {
        // Lazy import to avoid loading pdf-parse at startup (it requires DOM APIs)
        const { PDFParse } = await import("pdf-parse");
        const buffer = fs.readFileSync(record.storedPath);
        const parser = new PDFParse({ data: buffer });
        try {
          const result = await parser.getText();
          return this.truncateExtracted(result.text || "");
        } finally {
          await parser.destroy();
        }
      } catch (error) {
        console.error("Failed to parse PDF:", error);
        return "(PDF text extraction failed)";
      }
    }

    if (
      record.mimeType.startsWith("text/") ||
      [".json", ".md", ".markdown", ".csv", ".log", ".js", ".ts", ".tsx", ".jsx", ".py", ".swift", ".java", ".go", ".rs", ".rb", ".c", ".h", ".cpp", ".hpp"].includes(ext)
    ) {
      const text = fs.readFileSync(record.storedPath, "utf8");
      return this.truncateExtracted(text);
    }

    return "";
  }

  private truncateExtracted(text: string): string {
    const trimmed = text.trim();
    if (trimmed.length <= config.attachments.maxExtractedChars) {
      return trimmed;
    }
    return `${trimmed.slice(0, config.attachments.maxExtractedChars)}\n...[truncated]`;
  }

  private toMetadata(record: AttachmentRecord): AttachmentMetadata {
    return {
      id: record.id,
      conversationId: record.conversationId,
      originalName: record.originalName,
      displayName: record.displayName,
      size: record.size,
      mimeType: record.mimeType,
      createdAt: record.createdAt.toISOString(),
    };
  }
}

export const attachmentService = new AttachmentService();
