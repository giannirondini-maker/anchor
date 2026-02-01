/**
 * Rate Limiting Middleware
 *
 * Provides rate limiting for API endpoints to prevent abuse.
 * Uses a simple in-memory store suitable for single-instance deployments.
 * For production with multiple instances, consider using Redis.
 */

import { Request, Response, NextFunction } from "express";

interface RateLimitEntry {
  count: number;
  resetTime: number;
}

interface RateLimitOptions {
  /** Time window in milliseconds */
  windowMs: number;
  /** Maximum requests per window */
  max: number;
  /** Message to send when rate limited */
  message?: string;
  /** Skip rate limiting for certain requests */
  skip?: (req: Request) => boolean;
  /** Key generator function (defaults to IP address) */
  keyGenerator?: (req: Request) => string;
}

class RateLimiter {
  private store: Map<string, RateLimitEntry> = new Map();
  private cleanupInterval: NodeJS.Timeout | null = null;

  constructor() {
    // Cleanup expired entries every minute
    this.cleanupInterval = setInterval(() => this.cleanup(), 60000);
  }

  private cleanup(): void {
    const now = Date.now();
    for (const [key, entry] of this.store.entries()) {
      if (entry.resetTime <= now) {
        this.store.delete(key);
      }
    }
  }

  increment(key: string, windowMs: number): { count: number; resetTime: number } {
    const now = Date.now();
    const existing = this.store.get(key);

    if (existing && existing.resetTime > now) {
      existing.count++;
      return existing;
    }

    const entry: RateLimitEntry = {
      count: 1,
      resetTime: now + windowMs,
    };
    this.store.set(key, entry);
    return entry;
  }

  /**
   * Reset the rate limiter store (useful for testing)
   */
  reset(): void {
    this.store.clear();
  }

  destroy(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }
    this.store.clear();
  }
}

// Global rate limiter instance
const rateLimiter = new RateLimiter();

/**
 * Reset the rate limiter store (useful for testing)
 */
export function resetRateLimiter(): void {
  rateLimiter.reset();
}

/**
 * Creates a rate limiting middleware
 */
export function rateLimit(options: RateLimitOptions) {
  const {
    windowMs,
    max,
    message = "Too many requests, please try again later.",
    skip,
    keyGenerator = (req: Request) => req.ip || req.socket.remoteAddress || "unknown",
  } = options;

  return (req: Request, res: Response, next: NextFunction): void => {
    // Skip if configured to skip
    if (skip && skip(req)) {
      next();
      return;
    }

    const key = keyGenerator(req);
    const { count, resetTime } = rateLimiter.increment(key, windowMs);

    // Set rate limit headers
    res.setHeader("X-RateLimit-Limit", max);
    res.setHeader("X-RateLimit-Remaining", Math.max(0, max - count));
    res.setHeader("X-RateLimit-Reset", Math.ceil(resetTime / 1000));

    if (count > max) {
      res.status(429).json({
        code: "RATE_LIMIT_EXCEEDED",
        message,
        retryAfter: Math.ceil((resetTime - Date.now()) / 1000),
      });
      return;
    }

    next();
  };
}

/**
 * Pre-configured rate limiters for different use cases
 */

/** General API rate limit: 100 requests per minute */
export const apiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 100,
  message: "Too many API requests. Please wait a moment and try again.",
});

/** Message sending rate limit: 20 messages per minute */
export const messageLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 20,
  message: "You're sending messages too quickly. Please wait a moment.",
});

/** Strict rate limit for creation: 10 per minute */
export const createLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: "Too many creation requests. Please wait a moment.",
});

/** Auth/health endpoints: higher limit (200/min) */
export const healthLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 200,
  message: "Too many health check requests.",
});
