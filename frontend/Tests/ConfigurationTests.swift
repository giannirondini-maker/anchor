/**
 * Configuration Tests
 *
 * Unit tests for app configuration
 */

import XCTest
@testable import Anchor

final class ConfigurationTests: XCTestCase {
    
    // MARK: - API Configuration Tests
    
    func testDefaultAPIBaseURL() {
        let url = Configuration.apiBaseURL
        
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "localhost")
        XCTAssertEqual(url.port, Configuration.backendPort)
        XCTAssertEqual(url.path, "/api")
    }
    
    func testDefaultWebSocketURL() {
        let url = Configuration.webSocketURL
        
        XCTAssertEqual(url.scheme, "ws")
        XCTAssertEqual(url.host, "localhost")
        XCTAssertEqual(url.port, Configuration.backendPort)
        XCTAssertEqual(url.path, "/ws")
    }
    
    func testBackendPortConfiguration() {
        // Port should be either 3847 (production) or 3848 (development)
        let port = Configuration.backendPort
        XCTAssertTrue(port == 3847 || port == 3848, "Port should be 3847 (production) or 3848 (development), but was \(port)")
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultModel() {
        let model = Configuration.defaultModel
        
        XCTAssertFalse(model.isEmpty)
        // Default should be a Claude model based on the configuration
        XCTAssertTrue(model.contains("claude") || model.contains("gpt"))
    }
    
    // MARK: - Messages Configuration Tests
    
    func testInitialMessageLimit() {
        XCTAssertEqual(Configuration.initialMessageLimit, 50, "Initial message limit should be 50 for pagination")
        XCTAssertGreaterThan(Configuration.initialMessageLimit, 0, "Initial message limit must be positive")
    }
    
    // MARK: - Timeout Configuration Tests
    
    func testRequestTimeout() {
        XCTAssertEqual(Configuration.requestTimeout, 30)
    }
    
    func testResourceTimeout() {
        XCTAssertEqual(Configuration.resourceTimeout, 300)
    }
    
    // MARK: - WebSocket Configuration Tests
    
    func testMaxReconnectAttempts() {
        XCTAssertEqual(Configuration.maxReconnectAttempts, 5)
    }
    
    func testReconnectBaseDelay() {
        XCTAssertEqual(Configuration.reconnectBaseDelay, 1.0)
    }
    
    func testReconnectMaxDelay() {
        XCTAssertEqual(Configuration.reconnectMaxDelay, 30.0)
    }
    
    // MARK: - App Information Tests
    
    func testAppVersion() {
        XCTAssertEqual(Configuration.appVersion, "1.0.0")
    }
    
    func testAppName() {
        XCTAssertEqual(Configuration.appName, "Anchor")
    }
}
