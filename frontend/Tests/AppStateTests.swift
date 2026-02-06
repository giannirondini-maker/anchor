import XCTest
@testable import Anchor

final class AppStateTests: XCTestCase {
    
    // MARK: - Initial State Tests
    
    @MainActor
    func testInitialLoadingState() {
        let appState = AppState()
        
        // Should start with loading indicators enabled
        XCTAssertTrue(appState.isLoading, "Conversations should show loading state on startup")
        XCTAssertTrue(appState.isLoadingModels, "Models should show loading state on startup")
        XCTAssertFalse(appState.isDataLoaded, "Data should not be marked as loaded initially")
    }
    
    @MainActor
    func testInitialDraftMode() {
        let appState = AppState()
        
        // Should start in draft mode with no conversation selected
        XCTAssertTrue(appState.isDraftMode, "Should start in draft mode")
        XCTAssertNil(appState.selectedConversationId, "No conversation should be selected initially")
    }
    
    // MARK: - Model Selection Tests

    func testChooseModel_usesRequestedIfProvided() {
        let requested = "custom-model"
        let available: [ModelInfo] = [ModelInfo(id: "a", name: "A", multiplier: 1.0), ModelInfo(id: "b", name: "B", multiplier: 0.0)]
        let chosen = AppState.chooseModel(requested: requested, available: available)
        XCTAssertEqual(chosen, requested)
    }

    func testChooseModel_prefersConfiguredDefaultIfPresent() {
        let defaultModel = Configuration.defaultModel
        let available: [ModelInfo] = [ModelInfo(id: defaultModel, name: "Default", multiplier: 1.0), ModelInfo(id: "b", name: "B", multiplier: 0.0)]
        let chosen = AppState.chooseModel(requested: nil, available: available)
        XCTAssertEqual(chosen, defaultModel)
    }

    func testChooseModel_prefersZeroMultiplierWhenDefaultMissing() {
        // Ensure configured default is not in available list
        let available: [ModelInfo] = [
            ModelInfo(id: "premium-1", name: "Premium", multiplier: 1.5),
            ModelInfo(id: "free-1", name: "Free", multiplier: 0.0),
            ModelInfo(id: "premium-2", name: "Premium2", multiplier: 1.0)
        ]

        // Capture stdout
        let output = captureStandardOutput {
            let chosen = AppState.chooseModel(requested: nil, available: available)
            XCTAssertEqual(chosen, "free-1")
        }

        XCTAssertTrue(output.contains("AUDIT: Default model"))
    }

    // Helper to capture stdout
    func captureStandardOutput(_ block: () -> Void) -> String {
        // Based on POSIX pipe and file descriptor redirection
        let pipefd = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        pipefd.initialize(to: 0)
        pipe(&pipefd[0])
        let readFD = pipefd[0]
        let writeFD = pipefd[1]

        fflush(stdout)
        let savedStdout = dup(STDOUT_FILENO)
        dup2(writeFD, STDOUT_FILENO)

        block()

        fflush(stdout)
        // Restore
        dup2(savedStdout, STDOUT_FILENO)
        close(writeFD)

        // Read from pipe
        var out = ""
        let bufSize = 1024
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufSize)
        while true {
            let bytes = read(readFD, buffer, bufSize)
            if bytes <= 0 { break }
            let data = Data(bytes: buffer, count: bytes)
            if let s = String(data: data, encoding: .utf8) {
                out += s
            }
        }
        close(readFD)
        return out
    }

    func testChooseModel_fallsBackToFirstIfNoFreeOrDefault() {
        let available: [ModelInfo] = [ModelInfo(id: "first", name: "First", multiplier: 1.0)]
        let chosen = AppState.chooseModel(requested: nil, available: available)
        XCTAssertEqual(chosen, "first")
    }

    func testChooseModel_returnsConfiguredDefaultIfNoAvailable() {
        let defaultModel = Configuration.defaultModel
        let available: [ModelInfo] = []
        let chosen = AppState.chooseModel(requested: nil, available: available)
        XCTAssertEqual(chosen, defaultModel)
    }
}
