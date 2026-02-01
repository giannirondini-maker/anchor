/**
 * Configuration
 *
 * Centralized configuration for the Anchor app.
 * Environment-specific values can be overridden via environment variables
 * or UserDefaults for development/production builds.
 */

import Foundation

enum Configuration {
    // MARK: - Environment Detection
    
    /// Whether we're running in development mode (from Xcode/SwiftPM, not bundled app)
    static var isDevelopment: Bool {
        // Check explicit environment variable first
        if let env = ProcessInfo.processInfo.environment["ANCHOR_ENV"] {
            return env == "development"
        }
        
        // If running from a bundled .app, we're in production
        // In dev mode, the bundle path is typically in DerivedData or .build
        let bundlePath = Bundle.main.bundlePath
        let isFromDerivedData = bundlePath.contains("DerivedData")
        let isFromSwiftBuild = bundlePath.contains(".build")
        let isFromXcode = bundlePath.contains("Build/Products")
        
        return isFromDerivedData || isFromSwiftBuild || isFromXcode
    }
    
    // MARK: - Port Configuration
    
    /// The backend server port
    /// - Dev mode: 3848 (unless overridden via ANCHOR_PORT)
    /// - Production: 3847 (unless overridden via ANCHOR_PORT)
    static var backendPort: Int {
        if let portString = ProcessInfo.processInfo.environment["ANCHOR_PORT"],
           let port = Int(portString) {
            return port
        }
        return isDevelopment ? 3848 : 3847
    }
    
    // MARK: - API Configuration
    
    /// The base URL for the backend API
    static var apiBaseURL: URL {
        if let urlString = ProcessInfo.processInfo.environment["ANCHOR_API_URL"],
           let url = URL(string: urlString) {
            return url
        }
        return URL(string: "http://localhost:\(backendPort)/api")!
    }
    
    /// The WebSocket URL for real-time streaming
    static var webSocketURL: URL {
        if let urlString = ProcessInfo.processInfo.environment["ANCHOR_WS_URL"],
           let url = URL(string: urlString) {
            return url
        }
        return URL(string: "ws://localhost:\(backendPort)/ws")!
    }
    
    // MARK: - Default Values
    
    /// Default model to use when creating new conversations
    static var defaultModel: String {
        ProcessInfo.processInfo.environment["ANCHOR_DEFAULT_MODEL"] ?? "claude-haiku-4.5"
    }
    
    // MARK: - Timeouts
    
    /// Request timeout interval in seconds
    static let requestTimeout: TimeInterval = 30
    
    /// Resource timeout interval in seconds
    static let resourceTimeout: TimeInterval = 300
    
    // MARK: - WebSocket Configuration
    
    /// Maximum number of reconnection attempts
    static let maxReconnectAttempts: Int = 5
    
    /// Base delay for reconnection (in seconds)
    static let reconnectBaseDelay: TimeInterval = 1.0
    
    /// Maximum reconnection delay (in seconds)
    static let reconnectMaxDelay: TimeInterval = 30.0
    
    // MARK: - App Information
    
    /// Application version
    static let appVersion: String = "1.0.0"
    
    /// Application name
    static let appName: String = "Anchor"
}
