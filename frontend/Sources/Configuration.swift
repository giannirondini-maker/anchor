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
        // First, detect if we're running from a development build location
        let bundlePath = Bundle.main.bundlePath
        let isFromDerivedData = bundlePath.contains("DerivedData")
        let isFromSwiftBuild = bundlePath.contains(".build")
        let isFromXcode = bundlePath.contains("Build/Products")
        let isDevBuild = isFromDerivedData || isFromSwiftBuild || isFromXcode
        
        // If it's a dev build, always use development mode (can't use embedded backend)
        if isDevBuild {
            if let env = ProcessInfo.processInfo.environment["ANCHOR_ENV"], env == "production" {
                print("⚠️ ANCHOR_ENV=production set but running from dev build. Using development mode.")
            }
            return true
        }
        
        // For production builds, check explicit environment variable
        if let env = ProcessInfo.processInfo.environment["ANCHOR_ENV"] {
            return env == "development"
        }
        
        // Default for production builds is production mode
        return false
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
    
    // MARK: - Messages
    
    /// Maximum number of messages to load initially per conversation
    static let initialMessageLimit: Int = 50

    // MARK: - Attachments

    /// Max attachments per message
    static let maxAttachmentsPerMessage: Int = 5

    /// Max size per attachment (bytes)
    static let maxAttachmentSizeBytes: Int = 5 * 1024 * 1024

    /// Max total attachment size per message (bytes)
    static let maxTotalAttachmentSizeBytes: Int = 10 * 1024 * 1024
    
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
