/**
 * Application State
 *
 * Global state management for the Anchor app
 */

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationId: String?
    @Published var availableModels: [ModelInfo] = []
    @Published var isLoading: Bool = true
    @Published var error: AppError?
    @Published var isDataLoaded: Bool = false
    @Published var isDraftMode: Bool = false
    @Published var pendingMessage: (conversationId: String, message: String)? = nil
    @Published var pendingAttachmentURLs: (conversationId: String, urls: [URL])? = nil
    @Published var isLoadingModels: Bool = true
    
    // Message cache: stores messages per conversation to avoid reloading
    // Key: conversationId, Value: array of messages
    @Published var messageCache: [String: [Message]] = [:]
    
    // MARK: - Services

    private let networkService = NetworkService.shared
    private let webSocketService = WebSocketService.shared
    private let memoryMonitor = MemoryMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var selectedConversation: Conversation? {
        guard let id = selectedConversationId else { return nil }
        return conversations.first { $0.id == id }
    }
    
    // MARK: - Initialization
    
    init() {
        setupBindings()
        // Start in draft mode by default (no conversation selected)
        isDraftMode = true
        // Note: Data loading is deferred until backend is ready
        // Call onBackendReady() when the backend becomes available
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Listen for new conversation notifications
        NotificationCenter.default.publisher(for: .newConversation)
            .sink { [weak self] _ in
                Task {
                    await self?.createConversation()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Called when the backend becomes ready
    /// This triggers initial data loading
    func onBackendReady() {
        guard !isDataLoaded else { return }
        print("📱 Backend ready, loading initial data...")
        Task {
            await loadInitialData()
            isDataLoaded = true
        }
    }
    
    private func loadInitialData() async {
        await loadModels()
        await loadConversations()
    }
    
    // MARK: - Model Operations
    
    func loadModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        
        do {
            availableModels = try await networkService.fetchModels()
        } catch {
            self.error = AppError(message: "Failed to load models: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Conversation Operations
    
    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            conversations = try await networkService.fetchConversations()
        } catch {
            self.error = AppError(message: "Failed to load conversations: \(error.localizedDescription)")
        }
    }
    
    /// Chooses the model to use when creating a conversation.
    /// Selection priority:
    /// 1) `requested` if provided
    /// 2) `Configuration.defaultModel` if present in `available`
    /// 3) first model in `available` that has multiplier == 0
    /// 4) first model in `available`
    /// 5) `Configuration.defaultModel` as last resort
    nonisolated static func chooseModel(requested: String?, available: [ModelInfo]) -> String {
        if let requested = requested {
            return requested
        }

        let defaultModel = Configuration.defaultModel

        if available.contains(where: { $0.id == defaultModel }) {
            return defaultModel
        }

        if let free = available.first(where: { $0.multiplier == 0 || $0.multiplier == 0.0 }) {
            print("AUDIT: Default model '\(defaultModel)' not found in available models; selected free model '\(free.id)'")
            return free.id
        }

        if let first = available.first {
            return first.id
        }

        return defaultModel
    }

    func createConversation(title: String = "New Conversation", model: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let selectedModel = AppState.chooseModel(requested: model, available: availableModels)
            let conversation = try await networkService.createConversation(
                title: title,
                model: selectedModel
            )
            conversations.insert(conversation, at: 0)
            selectedConversationId = conversation.id
            // Exit draft mode when a real conversation is created
            isDraftMode = false
        } catch {
            self.error = AppError(message: "Failed to create conversation: \(error.localizedDescription)")
        }
    }
    
    func selectConversation(_ conversation: Conversation?) {
        selectedConversationId = conversation?.id
        // Exit draft mode when selecting a real conversation
        if conversation != nil {
            isDraftMode = false
        }
    }
    
    func startDraftConversation() {
        isDraftMode = true
        selectedConversationId = nil
    }
    
    func startNewConversation() {
        // Starting a new conversation enters draft mode
        startDraftConversation()
    }
    
    func cancelDraftConversation() {
        isDraftMode = false
    }
    
    func commitDraftConversation(firstMessage: String, model: String? = nil) async {
        // Create the conversation first
        await createConversation(title: "New Conversation", model: model)
        isDraftMode = false
        
        // After conversation is created, store the pending message with its conversation ID
        if let conversationId = selectedConversationId {
            pendingMessage = (conversationId: conversationId, message: firstMessage)
        }
        // pendingMessage will be cleared by ChatView after sending
    }
    
    func updateConversation(id: String, title: String? = nil, model: String? = nil) async {
        do {
            let updated = try await networkService.updateConversation(id: id, title: title, model: model)
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index] = updated
            }
        } catch {
            self.error = AppError(message: "Failed to update conversation: \(error.localizedDescription)")
        }
    }
    
    func deleteConversation(_ conversation: Conversation) async {
        do {
            try await networkService.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            // Clear cached messages for deleted conversation
            clearMessageCache(for: conversation.id)
            if selectedConversationId == conversation.id {
                selectedConversationId = conversations.first?.id
            }
        } catch {
            self.error = AppError(message: "Failed to delete conversation: \(error.localizedDescription)")
        }
    }
    
    func deleteAllConversations() async {
        do {
            try await networkService.deleteAllConversations()
            conversations.removeAll()
            selectedConversationId = nil
            // Clear all cached messages
            clearMessageCache()
        } catch {
            self.error = AppError(message: "Failed to delete conversations: \(error.localizedDescription)")
        }
    }
    
    /// Move a conversation to the top of the list (called when new message activity occurs)
    func moveConversationToTop(id: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let conversation = conversations.remove(at: index)
        conversations.insert(conversation, at: 0)
    }
    
    // MARK: - Tag Operations
    
    /// Add a tag to a conversation (supports comma-separated tags)
    func addTagsToConversation(conversationId: String, tagInput: String) async {
        // Split by comma and trim whitespace
        let tagNames = tagInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !tagNames.isEmpty else { return }
        
        do {
            var updatedConversation: Conversation?
            for tagName in tagNames {
                updatedConversation = try await networkService.addTagToConversation(
                    conversationId: conversationId,
                    name: tagName
                )
            }
            
            // Update local state with the final conversation state
            if let updated = updatedConversation,
               let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[index] = updated
            }
        } catch {
            self.error = AppError(message: "Failed to add tag: \(error.localizedDescription)")
        }
    }
    
    /// Remove a tag from a conversation
    func removeTagFromConversation(conversationId: String, tagId: Int) async {
        do {
            let updated = try await networkService.removeTagFromConversation(
                conversationId: conversationId,
                tagId: tagId
            )
            
            // Update local state
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[index] = updated
            }
        } catch {
            self.error = AppError(message: "Failed to remove tag: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Message Cache Operations
    
    /// Get cached messages for a conversation
    func getCachedMessages(for conversationId: String) -> [Message]? {
        return messageCache[conversationId]
    }
    
    /// Cache messages for a conversation
    func cacheMessages(_ messages: [Message], for conversationId: String) {
        messageCache[conversationId] = messages
    }
    
    /// Append a message to the cache for a conversation
    func appendToCachedMessages(_ message: Message, for conversationId: String) {
        if messageCache[conversationId] != nil {
            messageCache[conversationId]?.append(message)
        } else {
            messageCache[conversationId] = [message]
        }
    }
    
    /// Update a specific message in the cache
    func updateCachedMessage(_ message: Message, for conversationId: String) {
        guard var messages = messageCache[conversationId],
              let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        messages[index] = message
        messageCache[conversationId] = messages
    }
    
    /// Prepend older messages to the cache (for pagination)
    func prependToCachedMessages(_ messages: [Message], for conversationId: String) {
        if var existingMessages = messageCache[conversationId] {
            existingMessages.insert(contentsOf: messages, at: 0)
            messageCache[conversationId] = existingMessages
        } else {
            messageCache[conversationId] = messages
        }
    }
    
    /// Remove messages starting from a specific index (for retry operations)
    func removeCachedMessagesFromIndex(_ index: Int, for conversationId: String) {
        guard var messages = messageCache[conversationId], index < messages.count else {
            return
        }
        messages.removeSubrange(index...)
        messageCache[conversationId] = messages
    }
    
    /// Clear message cache for a specific conversation or all conversations
    func clearMessageCache(for conversationId: String? = nil) {
        if let conversationId = conversationId {
            messageCache.removeValue(forKey: conversationId)
        } else {
            messageCache.removeAll()
        }
    }
    
    // MARK: - Error Handling
    
    func dismissError() {
        error = nil
    }
}

// MARK: - App Error

struct AppError: Identifiable {
    let id = UUID()
    let message: String
}
