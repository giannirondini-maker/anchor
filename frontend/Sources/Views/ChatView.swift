/**
 * Chat View
 *
 * Main chat interface with message list and input
 */

import SwiftUI
import Combine

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    let conversation: Conversation
    
    @StateObject private var viewModel: ChatViewModel
    
    init(conversation: Conversation) {
        self.conversation = conversation
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversationId: conversation.id))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ChatHeaderView(
                conversation: conversation,
                selectedModel: $viewModel.selectedModel,
                availableModels: appState.availableModels,
                onModelChange: { model in
                    Task {
                        await appState.updateConversation(id: conversation.id, model: model)
                    }
                },
                messages: viewModel.messages
            )
            
            Divider()
            
            // Error Banner (if any)
            if let error = viewModel.error {
                ErrorBannerView(message: error) {
                    viewModel.dismissError()
                }
            }
            
            // Messages
            MessageListView(
                messages: viewModel.messages,
                isLoading: viewModel.isStreaming,
                hasOlderMessages: viewModel.hasOlderMessages,
                isLoadingOlder: viewModel.isLoadingOlder,
                onRetry: { message, editedContent in
                    Task {
                        await viewModel.retryMessage(message, with: editedContent)
                        appState.moveConversationToTop(id: conversation.id)
                    }
                },
                onLoadOlder: {
                    Task {
                        await viewModel.loadOlderMessages()
                    }
                }
            )
            
            Divider()
            
            // Input
            MessageInputView(
                text: $viewModel.inputText,
                isLoading: viewModel.isStreaming,
                isConnected: viewModel.isConnected,
                onSend: {
                    Task {
                        await viewModel.sendMessage()
                        appState.moveConversationToTop(id: conversation.id)
                    }
                }
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.setAppState(appState)
            viewModel.selectedModel = conversation.model ?? Configuration.defaultModel
            
            // Check for pending message (from draft conversation)
            // Only send if it's for THIS specific conversation and hasn't been sent yet
            if let pending = appState.pendingMessage,
               pending.conversationId == conversation.id {
                let messageToSend = pending.message
                appState.pendingMessage = nil // Clear atomically before sending
                
                viewModel.inputText = messageToSend
                Task {
                    // Small delay to ensure WebSocket is connected
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    await viewModel.sendMessage()
                }
            }
        }
        .onChange(of: conversation.id) { _, newId in
            viewModel.switchConversation(to: newId)
            // Load the model from the new conversation
            if let newConversation = appState.conversations.first(where: { $0.id == newId }) {
                viewModel.selectedModel = newConversation.model ?? Configuration.defaultModel
            }
            
            // Note: Pending message handling is only in onAppear to avoid race conditions
            // If a pending message exists for this conversation, it will be handled when
            // the ChatView for that conversation appears
        }
    }
}

// MARK: - Chat View Model

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var isConnected: Bool = false
    @Published var selectedModel: String = Configuration.defaultModel
    @Published var error: String?
    @Published var hasOlderMessages: Bool = false
    @Published var isLoadingOlder: Bool = false

    private var conversationId: String
    private let networkService = NetworkService.shared
    private let webSocketService = WebSocketService.shared
    private var streamingMessageId: String?
    private var streamingContent: String = ""
    private var cancellables = Set<AnyCancellable>()
    private weak var appState: AppState?
    private var messageLoadTask: Task<Void, Never>?
    private var conversationSwitchTask: Task<Void, Never>?

    // Batching mechanism for streaming updates to reduce layout thrashing
    private var batchUpdateTask: Task<Void, Never>?
    private var pendingStreamContent: String?
    private var pendingStreamMessageId: String?

    init(conversationId: String) {
        self.conversationId = conversationId
        setupWebSocket()
        observeConnectionStatus()
        observeMemoryPressure()
        Task {
            await loadMessages()
        }
    }

    deinit {
        messageLoadTask?.cancel()
        conversationSwitchTask?.cancel()
        batchUpdateTask?.cancel()
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    private func observeConnectionStatus() {
        webSocketService.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
            }
            .store(in: &cancellables)
    }

    private func observeMemoryPressure() {
        NotificationCenter.default.publisher(for: .memoryPressureDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleMemoryPressure()
                }
            }
            .store(in: &cancellables)
    }

    /// Handle memory pressure by reducing the number of visible messages
    private func handleMemoryPressure() async {
        guard messages.count > 30 else { return }

        print("⚠️ Memory pressure: Reducing visible messages from \(messages.count) to 30")

        // Keep only the most recent 30 messages
        messages = Array(messages.suffix(30))
        hasOlderMessages = true
    }

    private func setupWebSocket() {
        webSocketService.onMessageStart = { [weak self] messageId in
            Task { @MainActor in
                self?.streamingMessageId = messageId
                self?.streamingContent = ""
                self?.isStreaming = true
                
                // Add placeholder message
                if let self = self,
                   !self.messages.contains(where: { $0.id == messageId }) {
                    let placeholderMessage = Message(
                        id: messageId,
                        conversationId: self.conversationId,
                        role: .assistant,
                        content: "",
                        status: .sending
                    )
                    self.messages.append(placeholderMessage)
                }
            }
        }
        
        webSocketService.onMessageDelta = { [weak self] messageId, delta in
            Task { @MainActor in
                guard let self = self else { return }
                self.streamingContent += delta

                // Batch updates to reduce layout thrashing - update UI every 50ms
                self.pendingStreamContent = self.streamingContent
                self.pendingStreamMessageId = messageId

                // Cancel previous batch update if it exists
                self.batchUpdateTask?.cancel()

                self.batchUpdateTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms batching
                    guard !Task.isCancelled, let self = self,
                          let messageId = self.pendingStreamMessageId,
                          let content = self.pendingStreamContent else { return }

                    if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
                        self.messages[index].content = content
                    }
                }
            }
        }
        
        webSocketService.onMessageComplete = { [weak self] messageId, fullContent in
            Task { @MainActor in
                guard let self = self else { return }

                // Cancel any pending batch updates for this message
                self.batchUpdateTask?.cancel()
                self.pendingStreamContent = nil
                self.pendingStreamMessageId = nil

                if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
                    self.messages[index].content = fullContent
                    self.messages[index].status = .sent
                }

                self.isStreaming = false
                self.streamingMessageId = nil
                self.streamingContent = ""

                // Move conversation to top when message is received
                self.appState?.moveConversationToTop(id: self.conversationId)
            }
        }
        
        webSocketService.onMessageError = { [weak self] messageId, errorMsg in
            Task { @MainActor in
                guard let self = self else { return }

                // Cancel any pending batch updates for this message
                self.batchUpdateTask?.cancel()
                self.pendingStreamContent = nil
                self.pendingStreamMessageId = nil

                if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
                    self.messages[index].status = .error
                    self.messages[index].errorMessage = errorMsg
                }

                self.isStreaming = false
                self.error = errorMsg
            }
        }
        
        webSocketService.connect(conversationId: conversationId)
    }
    
    func loadMessages() async {
        messageLoadTask?.cancel()
        
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            
            do {
                let limit = Configuration.initialMessageLimit
                let fetchedMessages = try await self.networkService.fetchMessages(
                    conversationId: self.conversationId,
                    limit: limit
                )
                guard !Task.isCancelled else { return }
                self.messages = fetchedMessages
                self.hasOlderMessages = fetchedMessages.count >= limit
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
        messageLoadTask = task
        await task.value
    }
    
    /// Load older messages (pagination) for the current conversation
    func loadOlderMessages() async {
        guard hasOlderMessages, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        
        guard let oldestMessage = messages.first else { return }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let beforeTimestamp = formatter.string(from: oldestMessage.createdAt)
        
        do {
            let limit = Configuration.initialMessageLimit
            let olderMessages = try await networkService.fetchMessages(
                conversationId: conversationId,
                limit: limit,
                before: beforeTimestamp
            )
            // Prepend older messages
            messages.insert(contentsOf: olderMessages, at: 0)
            hasOlderMessages = olderMessages.count >= limit
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func sendMessage() async {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        inputText = ""
        
        // Add user message immediately
        let userMessage = Message(
            id: "temp_\(UUID().uuidString)",
            conversationId: conversationId,
            role: .user,
            content: content,
            status: .sent
        )
        messages.append(userMessage)
        
        do {
            let response = try await networkService.sendMessage(
                conversationId: conversationId,
                content: content
            )
            
            // Update user message with real ID if needed
            if let index = messages.firstIndex(where: { $0.id == userMessage.id }) {
                // Keep the temp message, the real one comes from WebSocket
                _ = index
            }
            
            _ = response // Response indicates streaming started
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func switchConversation(to newConversationId: String) {
        // Cancel any in-flight operations immediately
        messageLoadTask?.cancel()
        conversationSwitchTask?.cancel()
        batchUpdateTask?.cancel()

        // Clear state immediately to prevent layout thrashing on stale data
        conversationId = newConversationId
        messages = []
        isStreaming = false
        hasOlderMessages = false
        isLoadingOlder = false
        streamingMessageId = nil
        streamingContent = ""
        pendingStreamContent = nil
        pendingStreamMessageId = nil

        // Debounce the actual load to coalesce rapid switches
        conversationSwitchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            guard !Task.isCancelled, let self = self else { return }

            self.webSocketService.connect(conversationId: newConversationId)
            await self.loadMessages()
        }
    }
    
    func retryMessage(_ message: Message, with editedContent: String) async {
        // Find the index of the message being retried
        guard let messageIndex = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        
        // Remove this message and all messages after it (including any assistant responses)
        messages.removeSubrange(messageIndex...)
        
        // Send the edited content as a new message
        let content = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        // Add user message immediately
        let userMessage = Message(
            id: "temp_\(UUID().uuidString)",
            conversationId: conversationId,
            role: .user,
            content: content,
            status: .sent
        )
        messages.append(userMessage)
        
        do {
            _ = try await networkService.sendMessage(
                conversationId: conversationId,
                content: content
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func dismissError() {
        error = nil
    }
}

// MARK: - Error Banner View

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.9))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// // #Preview {
//     ChatView(conversation: Conversation(
//         id: "preview",
//         title: "Test Conversation",
//         model: "claude-sonnet-4-20250514"
//     ))
//     .environmentObject(AppState())
// }
