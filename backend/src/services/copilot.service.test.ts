/**
 * Unit tests for the sendMessage event-handling logic in CopilotService.
 *
 * These tests verify the fix for the streaming interruption bug:
 * - assistant.message with toolRequests should NOT finalize the stream
 * - session.idle is the definitive completion signal
 * - tool.execution_start / tool.execution_complete are forwarded correctly
 * - Duplicate onComplete calls are prevented by the `completed` flag
 *
 * We test the event-handling logic directly by constructing a CopilotService
 * with a mock session injected into its internal sessions Map.
 */

import { describe, it, expect, vi } from "vitest";

// ---------------------------------------------------------------------------
// Minimal mock types – we only need `session.on()` and `session.send()`
// ---------------------------------------------------------------------------

type EventCallback = (event: { type: string; data: any }) => void;

interface MockSession {
    on: ReturnType<typeof vi.fn>;
    send: ReturnType<typeof vi.fn>;
    _emit: (event: { type: string; data: any }) => void;
}

function createMockSession(): MockSession {
    let listener: EventCallback | null = null;
    const unsubscribe = vi.fn();

    const session: MockSession = {
        on: vi.fn((cb: EventCallback) => {
            listener = cb;
            return unsubscribe;
        }),
        send: vi.fn(async () => { }),
        _emit(event: { type: string; data: any }) {
            if (listener) listener(event);
        },
    };

    return session;
}

// ---------------------------------------------------------------------------
// Import and access the service under test
// ---------------------------------------------------------------------------

// We dynamically import the service and inject mock sessions via private access.
// This avoids needing to set up the full CopilotClient.

async function createServiceWithMockSession(conversationId: string) {
    const { copilotService } = await import("../services/copilot.service.js");

    const mockSession = createMockSession();

    // Inject a mock SessionWrapper into the private sessions Map
    const sessions = (copilotService as any).sessions as Map<string, any>;
    sessions.set(conversationId, {
        session: mockSession,
        model: "gpt-4o",
        createdAt: new Date(),
        lastActiveAt: new Date(),
        messageCount: 0,
    });

    return { copilotService, mockSession };
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

describe("CopilotService.sendMessage", () => {
    const CONV_ID = "test-conv-123";

    describe("standard response (no tool invocation)", () => {
        it("calls onComplete once when assistant.message has no toolRequests", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            const onDelta = vi.fn();
            const onComplete = vi.fn();
            const onError = vi.fn();

            const sendPromise = copilotService.sendMessage(
                CONV_ID, "Hello", onDelta, onComplete, onError
            );

            // Emit streamed chunks
            mockSession._emit({
                type: "assistant.message_delta",
                data: { deltaContent: "Hi" },
            });
            mockSession._emit({
                type: "assistant.message_delta",
                data: { deltaContent: " there" },
            });

            // Emit final message with NO toolRequests
            mockSession._emit({
                type: "assistant.message",
                data: { content: "Hi there" },
            });

            await sendPromise;

            expect(onDelta).toHaveBeenCalledTimes(2);
            expect(onDelta).toHaveBeenCalledWith("Hi");
            expect(onDelta).toHaveBeenCalledWith(" there");
            expect(onComplete).toHaveBeenCalledTimes(1);
            expect(onComplete).toHaveBeenCalledWith("Hi there");
            expect(onError).not.toHaveBeenCalled();

            // Clean up
            (copilotService as any).sessions.delete(CONV_ID);
        });

        it("calls onComplete via session.idle when no assistant.message is emitted", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            const onDelta = vi.fn();
            const onComplete = vi.fn();
            const onError = vi.fn();

            const sendPromise = copilotService.sendMessage(
                CONV_ID, "Hello", onDelta, onComplete, onError
            );

            // Only deltas, then idle (no assistant.message)
            mockSession._emit({
                type: "assistant.message_delta",
                data: { deltaContent: "Response" },
            });
            mockSession._emit({
                type: "session.idle",
                data: {},
            });

            await sendPromise;

            expect(onComplete).toHaveBeenCalledTimes(1);
            expect(onComplete).toHaveBeenCalledWith("Response");
            expect(onError).not.toHaveBeenCalled();

            (copilotService as any).sessions.delete(CONV_ID);
        });
    });

    describe("tool invocation flow", () => {
        it("does NOT call onComplete when assistant.message has toolRequests", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            const onDelta = vi.fn();
            const onComplete = vi.fn();
            const onError = vi.fn();
            const onToolStart = vi.fn();
            const onToolComplete = vi.fn();

            const sendPromise = copilotService.sendMessage(
                CONV_ID, "Search for cats", onDelta, onComplete, onError,
                onToolStart, onToolComplete
            );

            // Intermediate assistant.message with toolRequests
            mockSession._emit({
                type: "assistant.message",
                data: {
                    content: "",
                    toolRequests: [{ id: "call_1", tool: "web_search", arguments: {} }],
                },
            });

            // onComplete should NOT have been called
            expect(onComplete).not.toHaveBeenCalled();

            // Tool execution
            mockSession._emit({
                type: "tool.execution_start",
                data: { toolCallId: "call_1", toolName: "web_search" },
            });
            expect(onToolStart).toHaveBeenCalledWith("web_search");

            mockSession._emit({
                type: "tool.execution_complete",
                data: { toolCallId: "call_1", toolName: "web_search", success: true },
            });
            expect(onToolComplete).toHaveBeenCalledWith("web_search", true);

            // Continued streaming after tool result
            mockSession._emit({
                type: "assistant.message_delta",
                data: { deltaContent: "Here are results about cats..." },
            });

            // Final assistant.message with NO toolRequests
            mockSession._emit({
                type: "assistant.message",
                data: { content: "Here are results about cats..." },
            });

            await sendPromise;

            // Now onComplete should have been called exactly once
            expect(onComplete).toHaveBeenCalledTimes(1);
            expect(onComplete).toHaveBeenCalledWith("Here are results about cats...");
            expect(onError).not.toHaveBeenCalled();

            (copilotService as any).sessions.delete(CONV_ID);
        });

        it("forwards onToolStart and onToolComplete callbacks", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            const onToolStart = vi.fn();
            const onToolComplete = vi.fn();

            const sendPromise = copilotService.sendMessage(
                CONV_ID, "Search", vi.fn(), vi.fn(), vi.fn(),
                onToolStart, onToolComplete
            );

            mockSession._emit({
                type: "tool.execution_start",
                data: { toolCallId: "call_1", toolName: "bing_search" },
            });
            mockSession._emit({
                type: "tool.execution_complete",
                data: { toolCallId: "call_1", toolName: "bing_search", success: true },
            });

            // Complete via idle
            mockSession._emit({ type: "session.idle", data: {} });
            await sendPromise;

            expect(onToolStart).toHaveBeenCalledTimes(1);
            expect(onToolStart).toHaveBeenCalledWith("bing_search");
            expect(onToolComplete).toHaveBeenCalledTimes(1);
            expect(onToolComplete).toHaveBeenCalledWith("bing_search", true);

            (copilotService as any).sessions.delete(CONV_ID);
        });

        it("works when tool callbacks are not provided (optional)", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            const onComplete = vi.fn();
            const onError = vi.fn();

            const sendPromise = copilotService.sendMessage(
                CONV_ID, "Search", vi.fn(), onComplete, onError
                // onToolStart and onToolComplete intentionally omitted
            );

            // Tool events should not throw even without callbacks
            mockSession._emit({
                type: "tool.execution_start",
                data: { toolCallId: "call_1", toolName: "web_search" },
            });
            mockSession._emit({
                type: "tool.execution_complete",
                data: { toolCallId: "call_1", toolName: "web_search", success: false },
            });
            mockSession._emit({ type: "session.idle", data: {} });

            await sendPromise;

            expect(onError).not.toHaveBeenCalled();

            (copilotService as any).sessions.delete(CONV_ID);
        });
    });

    describe("completion deduplication", () => {
        it("does NOT call onComplete twice when session.idle fires after assistant.message", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            const onComplete = vi.fn();
            const onError = vi.fn();

            const sendPromise = copilotService.sendMessage(
                CONV_ID, "Hello", vi.fn(), onComplete, onError
            );

            // Final assistant.message (sets completed = true)
            mockSession._emit({
                type: "assistant.message",
                data: { content: "Hi" },
            });

            // session.idle fires afterward (should be ignored for completion)
            mockSession._emit({ type: "session.idle", data: {} });

            await sendPromise;

            // Must be called exactly once, not twice
            expect(onComplete).toHaveBeenCalledTimes(1);
            expect(onComplete).toHaveBeenCalledWith("Hi");

            (copilotService as any).sessions.delete(CONV_ID);
        });
    });

    describe("error handling", () => {
        it("calls onError when session.error event is emitted", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            const onComplete = vi.fn();
            const onError = vi.fn();

            const sendPromise = copilotService.sendMessage(
                CONV_ID, "Hello", vi.fn(), onComplete, onError
            );

            mockSession._emit({
                type: "session.error",
                data: { message: "Rate limit exceeded" },
            });

            await sendPromise;

            expect(onError).toHaveBeenCalledTimes(1);
            expect(onError).toHaveBeenCalledWith(expect.any(Error));
            expect(onError.mock.calls[0][0].message).toBe("Rate limit exceeded");
            expect(onComplete).not.toHaveBeenCalled();

            (copilotService as any).sessions.delete(CONV_ID);
        });

        it("calls onError when conversation session is not found", async () => {
            const { copilotService } = await createServiceWithMockSession(CONV_ID);

            const onComplete = vi.fn();
            const onError = vi.fn();

            await copilotService.sendMessage(
                "non-existent-conv", "Hello", vi.fn(), onComplete, onError
            );

            expect(onError).toHaveBeenCalledTimes(1);
            expect(onError).toHaveBeenCalledWith(expect.any(Error));
            expect(onComplete).not.toHaveBeenCalled();

            (copilotService as any).sessions.delete(CONV_ID);
        });

        it("calls onError when session.send throws an exception", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            // Make session.send throw
            mockSession.send.mockRejectedValueOnce(new Error("Network failure"));

            const onComplete = vi.fn();
            const onError = vi.fn();

            await copilotService.sendMessage(
                CONV_ID, "Hello", vi.fn(), onComplete, onError
            );

            expect(onError).toHaveBeenCalledTimes(1);
            expect(onError.mock.calls[0][0].message).toBe("Network failure");
            expect(onComplete).not.toHaveBeenCalled();

            (copilotService as any).sessions.delete(CONV_ID);
        });
    });

    describe("session.idle with no content", () => {
        it("does not call onComplete when session.idle fires with no accumulated content", async () => {
            const { copilotService, mockSession } = await createServiceWithMockSession(CONV_ID);

            const onComplete = vi.fn();
            const onError = vi.fn();

            const sendPromise = copilotService.sendMessage(
                CONV_ID, "Hello", vi.fn(), onComplete, onError
            );

            // Immediate idle with no content
            mockSession._emit({ type: "session.idle", data: {} });

            await sendPromise;

            // No content was accumulated, so onComplete should not be called
            expect(onComplete).not.toHaveBeenCalled();
            expect(onError).not.toHaveBeenCalled();

            (copilotService as any).sessions.delete(CONV_ID);
        });
    });
});
