/**
 * BackendManager
 *
 * Manages the lifecycle of the embedded Node.js backend server.
 * Handles starting, monitoring, and stopping the backend process.
 * 
 * In development mode, it assumes the backend is started separately
 * and only performs health checks to detect when it's ready.
 */

import Foundation
import Combine

class BackendManager: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isRunning = false
    @Published var backendURL: URL?
    @Published var lastError: String?
    
    // MARK: - Private Properties
    
    private var backendProcess: Process?
    private var healthCheckTimer: Timer?
    private let backendPort: Int
    private var startAttempts: Int = 0
    private let maxStartAttempts: Int = 3
    private var healthCheckRetries: Int = 0
    private let maxHealthCheckRetries: Int = 15  // 15 retries * 1 second = 15 seconds max wait
    private let isDevelopment: Bool
    
    // MARK: - Initialization
    
    init() {
        self.isDevelopment = Configuration.isDevelopment
        self.backendPort = Configuration.backendPort
        self.backendURL = URL(string: "http://localhost:\(backendPort)")
        
        if isDevelopment {
            print("🔧 Running in DEVELOPMENT mode - expecting external backend on port \(backendPort)")
        } else {
            print("📦 Running in PRODUCTION mode - will start embedded backend on port \(backendPort)")
        }
    }
    
    deinit {
        stopBackend()
    }
    
    // MARK: - Public Methods
    
    /// Start the embedded Node.js backend server
    /// In development mode, this just checks if an external backend is running
    func startBackend() {
        if isDevelopment {
            startDevMode()
        } else {
            startProductionMode()
        }
    }
    
    // MARK: - Development Mode
    
    /// In dev mode, we just check if an external backend is already running
    private func startDevMode() {
        guard !isRunning else {
            print("⚠️ Already connected to backend")
            return
        }
        
        print("🔍 Development mode: checking for external backend...")
        healthCheckRetries = 0
        checkBackendHealth()
    }
    
    // MARK: - Production Mode
    
    /// In production mode, we start the embedded Node.js backend
    private func startProductionMode() {
        guard !isRunning else {
            print("⚠️ Backend already running")
            return
        }
        
        guard startAttempts < maxStartAttempts else {
            lastError = "Failed to start backend after \(maxStartAttempts) attempts"
            print("❌ \(lastError ?? "")")
            return
        }
        
        startAttempts += 1
        
        guard let resourcePath = Bundle.main.resourcePath else {
            lastError = "Failed to locate app resources"
            print("❌ \(lastError ?? "")")
            return
        }
        
        print("📂 Resource path: \(resourcePath)")
        
        let nodePath = "\(resourcePath)/node/bin/node"
        let backendPath = "\(resourcePath)/backend/dist/index.js"
        let backendDir = "\(resourcePath)/backend"
        
        print("🔍 Checking for Node.js at: \(nodePath)")
        print("🔍 Checking for backend at: \(backendPath)")
        
        // Verify required files exist
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: nodePath) else {
            let bundlePath = Bundle.main.bundlePath
            let isDevBundle = bundlePath.contains("DerivedData") || bundlePath.contains(".build") || bundlePath.contains("Build/Products")
            if isDevBundle {
                print("⚠️ Running from dev build without embedded Node.js. Falling back to development mode.")
                print("💡 To test production mode, build the app with: ./scripts/build-unified.sh")
                startDevMode()
                return
            }
            lastError = "Node.js runtime not found at: \(nodePath)"
            print("❌ \(lastError ?? "")")
            
            // List what's actually in Resources
            if let contents = try? fileManager.contentsOfDirectory(atPath: resourcePath) {
                print("📁 Contents of Resources: \(contents.joined(separator: ", "))")
            }
            return
        }
        
        guard fileManager.fileExists(atPath: backendPath) else {
            lastError = "Backend not found at: \(backendPath)"
            print("❌ \(lastError ?? "")")
            
            // Check if backend directory exists
            if fileManager.fileExists(atPath: backendDir) {
                if let contents = try? fileManager.contentsOfDirectory(atPath: backendDir) {
                    print("📁 Contents of backend: \(contents.joined(separator: ", "))")
                }
            } else {
                print("📁 Backend directory does not exist at: \(backendDir)")
            }
            return
        }
        
        // Create and configure the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [backendPath]
        process.currentDirectoryURL = URL(fileURLWithPath: backendDir)
        
        // Set environment variables
        var environment = ProcessInfo.processInfo.environment
        environment["PORT"] = "\(backendPort)"
        environment["NODE_ENV"] = "production"
        environment["LOG_LEVEL"] = "info"
        
        // Build PATH that includes common Node.js installation locations
        // The Copilot CLI requires Node.js to be available in PATH
        var pathComponents: [String] = []
        
        // 1. Check for NVM installation (most common for developers)
        //    NVM stores versions in ~/.nvm/versions/node/
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        if let nvmVersions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) {
            // Sort versions and use the latest one, or prefer v20.x if available
            let sortedVersions = nvmVersions.sorted { v1, v2 in
                // Prefer v20.x versions for compatibility with bundled runtime
                let v1IsV20 = v1.hasPrefix("v20")
                let v2IsV20 = v2.hasPrefix("v20")
                if v1IsV20 != v2IsV20 {
                    return v1IsV20
                }
                return v1 > v2
            }
            
            if let preferredVersion = sortedVersions.first {
                let nvmBinPath = "\(nvmVersionsDir)/\(preferredVersion)/bin"
                if FileManager.default.fileExists(atPath: "\(nvmBinPath)/node") {
                    pathComponents.append(nvmBinPath)
                    print("🔍 Found NVM Node.js: \(preferredVersion)")
                }
            }
        }
        
        // 2. Standard system paths (in order of preference)
        pathComponents.append(contentsOf: [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin"
        ])
        
        // 3. Include existing PATH (may have user-specific paths)
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            pathComponents.append(existingPath)
        }
        
        let systemPaths = pathComponents.joined(separator: ":")
        environment["PATH"] = systemPaths
        
        print("🔧 Backend PATH: \(pathComponents.prefix(3).joined(separator: ":"))...")
        
        process.environment = environment
        
        // Set up pipes for logging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Handle output
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("🟢 Backend: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        // Handle errors
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let error = String(data: data, encoding: .utf8), !error.isEmpty {
                print("🔴 Backend Error: \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        // Handle process termination
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleBackendTermination(exitCode: process.terminationStatus)
            }
        }
        
        // Start the process
        do {
            try process.run()
            backendProcess = process
            print("✅ Backend process started (PID: \(process.processIdentifier))")
            
            // Reset health check retries and start checking immediately
            healthCheckRetries = 0
            // Give the process a brief moment to start, then begin health checks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkBackendHealth()
            }
            
        } catch {
            lastError = "Failed to start backend: \(error.localizedDescription)"
            print("❌ \(lastError ?? "")")
            backendProcess = nil
        }
    }
    
    /// Stop the backend server gracefully
    /// In development mode, this just stops monitoring (we don't control the external backend)
    func stopBackend() {
        // Stop health checks in all modes
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        
        // In dev mode, we don't control the backend process
        if isDevelopment {
            isRunning = false
            print("ℹ️ Development mode: disconnected from external backend")
            return
        }
        
        guard let process = backendProcess, process.isRunning else {
            print("ℹ️ Backend not running, nothing to stop")
            return
        }
        
        print("🛑 Stopping backend (PID: \(process.processIdentifier))...")
        
        // Send SIGTERM for graceful shutdown
        process.terminate()
        
        // Wait briefly for graceful shutdown
        DispatchQueue.global(qos: .background).async { [weak self] in
            Thread.sleep(forTimeInterval: 1.0)
            
            // Force kill if still running
            if process.isRunning {
                print("⚠️ Backend didn't stop gracefully, sending SIGKILL...")
                kill(process.processIdentifier, SIGKILL)
            }
            
            DispatchQueue.main.async {
                self?.backendProcess = nil
                self?.isRunning = false
                print("✅ Backend stopped")
            }
        }
    }
    
    /// Stop the backend server synchronously (for app termination)
    /// This blocks until the process is terminated
    /// In development mode, this just stops monitoring
    func stopBackendSync() {
        // Stop health checks in all modes
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        
        // In dev mode, we don't control the backend process
        if isDevelopment {
            isRunning = false
            print("ℹ️ Development mode: disconnected from external backend")
            return
        }
        
        guard let process = backendProcess, process.isRunning else {
            print("ℹ️ Backend not running, nothing to stop")
            return
        }
        
        let pid = process.processIdentifier
        print("🛑 Stopping backend synchronously (PID: \(pid))...")
        
        // Send SIGTERM for graceful shutdown
        process.terminate()
        
        // Wait up to 2 seconds for graceful shutdown
        var waitTime = 0.0
        while process.isRunning && waitTime < 2.0 {
            Thread.sleep(forTimeInterval: 0.1)
            waitTime += 0.1
        }
        
        // Force kill if still running
        if process.isRunning {
            print("⚠️ Backend didn't stop gracefully, sending SIGKILL...")
            kill(pid, SIGKILL)
            process.waitUntilExit()
        }
        
        backendProcess = nil
        isRunning = false
        print("✅ Backend stopped (exit code: \(process.terminationStatus))")
    }
    
    // MARK: - Private Methods
    
    /// Check if the backend server is responding
    private func checkBackendHealth() {
        guard let url = backendURL?.appendingPathComponent("api/health") else {
            return
        }
        
        healthCheckRetries += 1
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    self.isRunning = true
                    self.lastError = nil
                    self.startAttempts = 0
                    let mode = self.isDevelopment ? "external" : "embedded"
                    print("✅ Backend health check passed (\(mode) backend ready after \(self.healthCheckRetries) checks)")
                    self.healthCheckRetries = 0
                    
                    // Start periodic health checks
                    self.startHealthCheckTimer()
                } else {
                    // Log progress every few attempts
                    if self.healthCheckRetries % 3 == 0 {
                        let hint = self.isDevelopment ? " (run 'npm run dev' in backend folder)" : ""
                        print("⏳ Waiting for backend... (attempt \(self.healthCheckRetries)/\(self.maxHealthCheckRetries))\(hint)")
                    }
                    
                    // Retry if not at max retries
                    if self.healthCheckRetries < self.maxHealthCheckRetries {
                        // Wait 1 second between retries
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.checkBackendHealth()
                        }
                    } else {
                        if self.isDevelopment {
                            self.lastError = "Backend not found. Start it with: cd backend && npm run dev"
                            print("❌ \(self.lastError ?? "")")
                            print("💡 Make sure to run 'nvm use' before starting the backend")
                        } else {
                            self.lastError = "Backend failed to start within timeout"
                            print("❌ \(self.lastError ?? "")")
                        }
                        self.healthCheckRetries = 0
                    }
                }
            }
        }
        task.resume()
    }
    
    /// Start periodic health check timer
    private func startHealthCheckTimer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }
    
    /// Perform a health check on the backend
    private func performHealthCheck() {
        guard let url = backendURL?.appendingPathComponent("api/health") else {
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    // Backend is healthy
                    if self?.isRunning == false {
                        self?.isRunning = true
                        print("✅ Backend recovered")
                    }
                } else {
                    // Backend is unhealthy
                    if self?.isRunning == true {
                        self?.isRunning = false
                        self?.lastError = "Backend became unresponsive"
                        print("⚠️ Backend health check failed")
                    }
                }
            }
        }
        task.resume()
    }
    
    /// Handle backend process termination
    private func handleBackendTermination(exitCode: Int32) {
        isRunning = false
        
        if exitCode == 0 {
            print("✅ Backend exited normally")
        } else {
            lastError = "Backend crashed with exit code: \(exitCode)"
            print("❌ \(lastError ?? "")")
        }
        
        // Clean up
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        backendProcess = nil
    }
}
