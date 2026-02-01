/**
 * Rate Limiter Tests
 *
 * Unit tests for rate limiting middleware
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { rateLimit, resetRateLimiter } from "../src/middleware/rateLimit.js";
import type { Request, Response, NextFunction } from "express";

// Mock request/response
function createMockRequest(ip: string = "127.0.0.1"): Partial<Request> {
  return {
    ip,
    socket: { remoteAddress: ip } as any,
  };
}

function createMockResponse(): Partial<Response> & { 
  _headers: Record<string, any>; 
  _statusCode: number;
  _body: any;
} {
  const res: any = {
    _headers: {},
    _statusCode: 200,
    _body: null,
    setHeader(key: string, value: any) {
      this._headers[key] = value;
      return this;
    },
    status(code: number) {
      this._statusCode = code;
      return this;
    },
    json(body: any) {
      this._body = body;
      return this;
    },
  };
  return res;
}

describe("rateLimit", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    // Reset the global rate limiter store before each test
    resetRateLimiter();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("should allow requests within the limit", () => {
    const limiter = rateLimit({
      windowMs: 60000,
      max: 5,
    });

    const req = createMockRequest();
    const res = createMockResponse();
    const next = vi.fn();

    // Make 5 requests (within limit)
    for (let i = 0; i < 5; i++) {
      limiter(req as Request, res as Response, next as NextFunction);
    }

    expect(next).toHaveBeenCalledTimes(5);
    expect(res._statusCode).toBe(200);
  });

  it("should block requests over the limit", () => {
    const limiter = rateLimit({
      windowMs: 60000,
      max: 3,
    });

    const req = createMockRequest();
    const next = vi.fn();

    // Make 4 requests (exceeds limit of 3)
    for (let i = 0; i < 4; i++) {
      const res = createMockResponse();
      limiter(req as Request, res as Response, next as NextFunction);
      
      if (i === 3) {
        expect(res._statusCode).toBe(429);
        expect(res._body.code).toBe("RATE_LIMIT_EXCEEDED");
      }
    }

    expect(next).toHaveBeenCalledTimes(3);
  });

  it("should set rate limit headers", () => {
    const limiter = rateLimit({
      windowMs: 60000,
      max: 10,
    });

    const req = createMockRequest();
    const res = createMockResponse();
    const next = vi.fn();

    limiter(req as Request, res as Response, next as NextFunction);

    expect(res._headers["X-RateLimit-Limit"]).toBe(10);
    expect(res._headers["X-RateLimit-Remaining"]).toBe(9);
    expect(res._headers["X-RateLimit-Reset"]).toBeDefined();
  });

  it("should reset after window expires", () => {
    const limiter = rateLimit({
      windowMs: 1000, // 1 second
      max: 2,
    });

    const req = createMockRequest();
    const next = vi.fn();

    // Make 2 requests
    for (let i = 0; i < 2; i++) {
      const res = createMockResponse();
      limiter(req as Request, res as Response, next as NextFunction);
    }

    expect(next).toHaveBeenCalledTimes(2);

    // Third request should be blocked
    const res1 = createMockResponse();
    limiter(req as Request, res1 as Response, next as NextFunction);
    expect(res1._statusCode).toBe(429);

    // Advance time past the window
    vi.advanceTimersByTime(1100);

    // Now request should be allowed
    const res2 = createMockResponse();
    limiter(req as Request, res2 as Response, next as NextFunction);
    expect(next).toHaveBeenCalledTimes(3);
  });

  it("should track different IPs separately", () => {
    const limiter = rateLimit({
      windowMs: 60000,
      max: 2,
    });

    const req1 = createMockRequest("192.168.1.1");
    const req2 = createMockRequest("192.168.1.2");
    const next = vi.fn();

    // Make 2 requests from each IP
    for (let i = 0; i < 2; i++) {
      limiter(req1 as Request, createMockResponse() as Response, next as NextFunction);
      limiter(req2 as Request, createMockResponse() as Response, next as NextFunction);
    }

    expect(next).toHaveBeenCalledTimes(4);
  });

  it("should skip rate limiting when skip function returns true", () => {
    const limiter = rateLimit({
      windowMs: 60000,
      max: 1,
      skip: () => true,
    });

    const req = createMockRequest();
    const res = createMockResponse();
    const next = vi.fn();

    // Make many requests - all should pass because skip returns true
    for (let i = 0; i < 10; i++) {
      limiter(req as Request, res as Response, next as NextFunction);
    }

    expect(next).toHaveBeenCalledTimes(10);
  });

  it("should use custom key generator", () => {
    const limiter = rateLimit({
      windowMs: 60000,
      max: 2,
      keyGenerator: () => "custom-key", // All requests share same key
    });

    const req1 = createMockRequest("192.168.1.1");
    const req2 = createMockRequest("192.168.1.2");
    const next = vi.fn();

    // Make 3 requests from different IPs but same custom key
    limiter(req1 as Request, createMockResponse() as Response, next as NextFunction);
    limiter(req2 as Request, createMockResponse() as Response, next as NextFunction);
    
    const res3 = createMockResponse();
    limiter(req1 as Request, res3 as Response, next as NextFunction);

    expect(next).toHaveBeenCalledTimes(2);
    expect(res3._statusCode).toBe(429);
  });

  it("should include retryAfter in 429 response", () => {
    const limiter = rateLimit({
      windowMs: 60000,
      max: 1,
    });

    const req = createMockRequest();
    const next = vi.fn();

    // First request passes
    limiter(req as Request, createMockResponse() as Response, next as NextFunction);

    // Second request is rate limited
    const res = createMockResponse();
    limiter(req as Request, res as Response, next as NextFunction);

    expect(res._body.retryAfter).toBeDefined();
    expect(typeof res._body.retryAfter).toBe("number");
    expect(res._body.retryAfter).toBeGreaterThan(0);
  });
});
