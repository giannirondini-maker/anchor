/**
 * Validate Middleware
 *
 * Express middleware for validating request bodies, params, and queries
 * using Zod schemas.
 */

import { Request, Response, NextFunction } from "express";
import { z, ZodError } from "zod";
import { AppError, ErrorCodes } from "../types/index.js";

/**
 * Creates a middleware that validates the request body against a Zod schema
 */
export function validateBody<T extends z.ZodSchema>(schema: T) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    try {
      const result = schema.parse(req.body);
      req.body = result; // Replace with validated/transformed data
      next();
    } catch (error) {
      if (error instanceof ZodError) {
        const messages = error.errors.map(
          (e) => `${e.path.join(".")}: ${e.message}`
        );
        next(
          new AppError(
            ErrorCodes.INVALID_REQUEST,
            `Validation failed: ${messages.join("; ")}`,
            400,
            { errors: error.errors }
          )
        );
      } else {
        next(error);
      }
    }
  };
}

/**
 * Creates a middleware that validates request params against a Zod schema
 */
export function validateParams<T extends z.ZodSchema>(schema: T) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    try {
      const result = schema.parse(req.params);
      req.params = result;
      next();
    } catch (error) {
      if (error instanceof ZodError) {
        const messages = error.errors.map(
          (e) => `${e.path.join(".")}: ${e.message}`
        );
        next(
          new AppError(
            ErrorCodes.INVALID_REQUEST,
            `Invalid parameters: ${messages.join("; ")}`,
            400,
            { errors: error.errors }
          )
        );
      } else {
        next(error);
      }
    }
  };
}

/**
 * Creates a middleware that validates query parameters against a Zod schema
 */
export function validateQuery<T extends z.ZodSchema>(schema: T) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    try {
      const result = schema.parse(req.query);
      req.query = result;
      next();
    } catch (error) {
      if (error instanceof ZodError) {
        const messages = error.errors.map(
          (e) => `${e.path.join(".")}: ${e.message}`
        );
        next(
          new AppError(
            ErrorCodes.INVALID_REQUEST,
            `Invalid query parameters: ${messages.join("; ")}`,
            400,
            { errors: error.errors }
          )
        );
      } else {
        next(error);
      }
    }
  };
}
