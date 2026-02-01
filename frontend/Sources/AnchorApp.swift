/**
 * Anchor - macOS Native Chat Client for GitHub Copilot
 *
 * Main application entry point
 */

import SwiftUI
import AppKit

@main
struct AnchorApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var backendManager = BackendManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .environmentObject(backendManager)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    // Give AppDelegate a reference for cleanup on termination
                    appDelegate.backendManager = backendManager
                    
                    // Start backend when the main window appears
                    if !backendManager.isRunning {
                        print("🚀 Starting embedded backend...")
                        backendManager.startBackend()
                    }
                }
                // Observe backend readiness and trigger data loading
                .onReceive(backendManager.$isRunning) { isRunning in
                    if isRunning && !appState.isDataLoaded {
                        appState.onBackendReady()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    NotificationCenter.default.post(name: .newConversation, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Reference to the backend manager for cleanup on termination
    weak var backendManager: BackendManager?
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set the app as a regular foreground application
        // This is required for SPM-built apps to receive keyboard focus
        NSApp.setActivationPolicy(.regular)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app and bring it to the foreground
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure the main window becomes key window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(window.contentView)
            }
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Re-activate window when app becomes active
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 Application terminating, stopping backend...")
        backendManager?.stopBackendSync()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newConversation = Notification.Name("newConversation")
}
