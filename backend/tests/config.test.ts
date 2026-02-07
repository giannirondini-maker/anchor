/**
 * Configuration Tests
 *
 * Unit tests for application configuration
 */

import { describe, it, expect } from "vitest";
import {
  SERVER_PORT,
  SERVER_HOST,
  APP_VERSION,
  APP_NAME,
  DEFAULT_MODEL,
  CORS_ORIGIN,
  ANCHOR_ENV,
  IS_DEVELOPMENT,
  config,
} from "../src/config.js";

describe("Configuration", () => {
  describe("Environment Detection", () => {
    it("should detect environment correctly", () => {
      // In test environment, ANCHOR_ENV is not set, so it defaults to production
      expect(["development", "production"]).toContain(ANCHOR_ENV);
      expect(typeof IS_DEVELOPMENT).toBe("boolean");
    });
  });

  describe("Server Configuration", () => {
    it("should have port based on environment", () => {
      // Dev = 3848, Production = 3847
      expect([3847, 3848]).toContain(SERVER_PORT);
    });

    it("should have default host of localhost", () => {
      expect(SERVER_HOST).toBe("localhost");
    });
  });

  describe("Application Metadata", () => {
    it("should have version 1.0.0", () => {
      expect(APP_VERSION).toBe("1.0.0");
    });

    it("should have app name Anchor", () => {
      expect(APP_NAME).toBe("Anchor");
    });
  });

  describe("Default Values", () => {
    it("should have a default model configured", () => {
      expect(DEFAULT_MODEL).toBeDefined();
      expect(typeof DEFAULT_MODEL).toBe("string");
      expect(DEFAULT_MODEL.length).toBeGreaterThan(0);
    });

    it("should have CORS origin defaulting to *", () => {
      expect(CORS_ORIGIN).toBe("*");
    });
  });

  describe("Config Object", () => {
    it("should have environment configuration", () => {
      expect(config.env).toBeDefined();
      expect(config.env.name).toBe(ANCHOR_ENV);
      expect(config.env.isDevelopment).toBe(IS_DEVELOPMENT);
    });

    it("should have server configuration", () => {
      expect(config.server).toBeDefined();
      expect(config.server.port).toBe(SERVER_PORT);
      expect(config.server.host).toBe(SERVER_HOST);
    });

    it("should have database configuration", () => {
      expect(config.database).toBeDefined();
      expect(config.database.path).toBeDefined();
    });

    it("should have app metadata", () => {
      expect(config.app).toBeDefined();
      expect(config.app.version).toBe(APP_VERSION);
      expect(config.app.name).toBe(APP_NAME);
    });

    it("should have defaults configuration", () => {
      expect(config.defaults).toBeDefined();
      expect(config.defaults.model).toBe(DEFAULT_MODEL);
    });

    it("should have CORS configuration", () => {
      expect(config.cors).toBeDefined();
      expect(config.cors.origin).toBe(CORS_ORIGIN);
    });

    it("should not allow Excel attachment types", () => {
      expect(config.attachments.allowedExtensions).not.toContain(".xls");
      expect(config.attachments.allowedExtensions).not.toContain(".xlsx");
      expect(config.attachments.allowedMimeTypes).not.toContain(
        "application/vnd.ms-excel"
      );
      expect(config.attachments.allowedMimeTypes).not.toContain(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      );
    });
  });
});
