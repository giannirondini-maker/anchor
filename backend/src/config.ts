/**
 * Application configuration
 */

import path from "path";
import os from "os";

// Environment detection
// ANCHOR_ENV can be "development" or "production"
// NODE_ENV is also checked as a fallback
export const ANCHOR_ENV =
  process.env.ANCHOR_ENV ||
  (process.env.NODE_ENV === "development" ? "development" : "production");

export const IS_DEVELOPMENT = ANCHOR_ENV === "development";

// Server configuration
// Dev uses port 3848, production uses 3847 (unless overridden)
const DEFAULT_PORT = IS_DEVELOPMENT ? 3848 : 3847;
export const SERVER_PORT = parseInt(process.env.PORT || String(DEFAULT_PORT), 10);
export const SERVER_HOST = process.env.HOST || "localhost";

// Database configuration
// Dev uses Anchor-Dev folder, production uses Anchor folder
// Dev uses Anchor-Dev folder, production uses Anchor folder
const APP_SUPPORT_FOLDER = IS_DEVELOPMENT ? "Anchor-Dev" : "Anchor";
const APP_SUPPORT_DIR = path.join(
  os.homedir(),
  "Library",
  "Application Support",
  APP_SUPPORT_FOLDER
);

export const DATABASE_PATH =
  process.env.DATABASE_PATH || path.join(APP_SUPPORT_DIR, "data.sqlite");

// Application metadata
export const APP_VERSION = "1.0.0";
export const APP_NAME = "Anchor";

// SDK configuration
export const SDK_LOG_LEVEL = process.env.SDK_LOG_LEVEL || "info";

// Default model - can be overridden via environment variable
export const DEFAULT_MODEL = process.env.DEFAULT_MODEL || "claude-haiku-4.5";

// CORS configuration
export const CORS_ORIGIN = process.env.CORS_ORIGIN || "*";

// Logging
export const LOG_LEVEL = process.env.LOG_LEVEL || "info";

// Export all config as a single object for convenience
export const config = {
  env: {
    name: ANCHOR_ENV,
    isDevelopment: IS_DEVELOPMENT,
  },
  server: {
    port: SERVER_PORT,
    host: SERVER_HOST,
  },
  database: {
    path: DATABASE_PATH,
  },
  app: {
    version: APP_VERSION,
    name: APP_NAME,
  },
  sdk: {
    logLevel: SDK_LOG_LEVEL,
  },
  cors: {
    origin: CORS_ORIGIN,
  },
  defaults: {
    model: DEFAULT_MODEL,
  },
  logging: {
    level: LOG_LEVEL,
  },
} as const;

export default config;
