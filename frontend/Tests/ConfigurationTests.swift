/**
 * Configuration Tests
 *
 * Unit tests for app configuration
 */

import Foundation
import Testing
@testable import Anchor

struct ConfigurationTests {

    // MARK: - API Configuration Tests

    @Test func testDefaultAPIBaseURL() {
        let url = Configuration.apiBaseURL

        #expect(url.scheme == "http")
        #expect(url.host == "localhost")
        #expect(url.port == Configuration.backendPort)
        #expect(url.path == "/api")
    }

    @Test func testDefaultWebSocketURL() {
        let url = Configuration.webSocketURL

        #expect(url.scheme == "ws")
        #expect(url.host == "localhost")
        #expect(url.port == Configuration.backendPort)
        #expect(url.path == "/ws")
    }

    @Test func testBackendPortConfiguration() {
        // Port should be either 3847 (production) or 3848 (development)
        let port = Configuration.backendPort
        #expect(port == 3847 || port == 3848, "Port should be 3847 (production) or 3848 (development), but was \(port)")
    }

    // MARK: - Default Values Tests

    @Test func testDefaultModel() {
        let model = Configuration.defaultModel

        #expect(!model.isEmpty)
        // Default should be a Claude model based on the configuration
        #expect(model.contains("claude") || model.contains("gpt"))
    }

    // MARK: - Messages Configuration Tests

    @Test func testInitialMessageLimit() {
        #expect(Configuration.initialMessageLimit == 50, "Initial message limit should be 50 for pagination")
        #expect(Configuration.initialMessageLimit > 0, "Initial message limit must be positive")
    }

    // MARK: - Timeout Configuration Tests

    @Test func testRequestTimeout() {
        #expect(Configuration.requestTimeout == 30)
    }

    @Test func testResourceTimeout() {
        #expect(Configuration.resourceTimeout == 300)
    }

    // MARK: - WebSocket Configuration Tests

    @Test func testMaxReconnectAttempts() {
        #expect(Configuration.maxReconnectAttempts == 5)
    }

    @Test func testReconnectBaseDelay() {
        #expect(Configuration.reconnectBaseDelay == 1.0)
    }

    @Test func testReconnectMaxDelay() {
        #expect(Configuration.reconnectMaxDelay == 30.0)
    }

    // MARK: - App Information Tests

    @Test func testAppVersion() {
        #expect(Configuration.appVersion == "1.0.0")
    }

    @Test func testAppName() {
        #expect(Configuration.appName == "Anchor")
    }
}
