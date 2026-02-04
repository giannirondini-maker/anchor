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
                onRetry: { message, editedContent in
                    Task {
                        await viewModel.retryMessage(message, with: editedContent)
                        appState.moveConversationToTop(id: conversation.id)
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
    
    private var conversationId: String
    private let networkService = NetworkService.shared
    private let webSocketService = WebSocketService.shared
    private var streamingMessageId: String?
    private var streamingContent: String = ""
    private var cancellables = Set<AnyCancellable>()
    private weak var appState: AppState?
    
    init(conversationId: String) {
        self.conversationId = conversationId
        setupWebSocket()
        observeConnectionStatus()
        Task {
            await loadMessages()
        }
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
                
                if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
                    self.messages[index].content = self.streamingContent
                }
            }
        }
        
        webSocketService.onMessageComplete = { [weak self] messageId, fullContent in
            Task { @MainActor in
                guard let self = self else { return }
                
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
        // Add a small yield to ensure UI doesn't freeze
        await Task.yield()
        
        do {
            messages = try await networkService.fetchMessages(conversationId: conversationId)
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
        conversationId = newConversationId
        messages = []
        isStreaming = false
        streamingMessageId = nil
        streamingContent = ""
        
        webSocketService.connect(conversationId: newConversationId)
        
        Task {
            await loadMessages()
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
