/**
 * Chat View
 *
 * Main chat interface with message list and input
 */

import SwiftUI
import Combine
import UniformTypeIdentifiers

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
                attachments: viewModel.pendingAttachments,
                isAttachmentReady: viewModel.isAttachmentReady,
                onSend: {
                    Task {
                        await viewModel.sendMessage()
                        appState.moveConversationToTop(id: conversation.id)
                    }
                },
                onAddAttachments: { urls in
                    Task {
                        await viewModel.addAttachments(from: urls)
                    }
                },
                onRemoveAttachment: { attachment in
                    Task {
                        await viewModel.removeAttachment(attachment)
                    }
                },
                onRenameAttachment: { attachment, name in
                    Task {
                        await viewModel.renameAttachment(attachment, newName: name)
                    }
                }
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.setAppState(appState)
            viewModel.selectedModel = conversation.model ?? Configuration.defaultModel
            
            // Check for pending attachments (from draft mode)
            if let pending = appState.pendingAttachmentURLs,
               pending.conversationId == conversation.id {
                let urlsToUpload = pending.urls
                appState.pendingAttachmentURLs = nil // Clear immediately
                
                Task {
                    // Upload the attachments
                    await viewModel.addAttachments(from: urlsToUpload)
                }
            }
            
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
    @Published var pendingAttachments: [PendingAttachment] = []

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

    var isAttachmentReady: Bool {
        !pendingAttachments.contains { attachment in
            if case .uploading = attachment.status { return true }
            if case .failed = attachment.status { return true }
            return false
        }
    }

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
        
        // Update cache to reflect reduced messages
        appState?.cacheMessages(messages, for: conversationId)
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
                    
                    // Cache the placeholder message
                    self.appState?.appendToCachedMessages(placeholderMessage, for: self.conversationId)
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
                        
                        // Update cache with streaming content (batched)
                        self.appState?.updateCachedMessage(self.messages[index], for: self.conversationId)
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
                    
                    // Update the cached message with final content
                    self.appState?.updateCachedMessage(self.messages[index], for: self.conversationId)
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
                    
                    // Update the cached message with error status
                    self.appState?.updateCachedMessage(self.messages[index], for: self.conversationId)
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
            
            // First, check if we have cached messages for this conversation
            if let cachedMessages = self.appState?.getCachedMessages(for: self.conversationId) {
                print("📦 Using cached messages for conversation \(self.conversationId): \(cachedMessages.count) messages")
                self.messages = cachedMessages
                // We still need to check if there are older messages available
                // but we don't need to reload the visible ones
                return
            }
            
            // No cache, load from network
            do {
                let limit = Configuration.initialMessageLimit
                let fetchedMessages = try await self.networkService.fetchMessages(
                    conversationId: self.conversationId,
                    limit: limit
                )
                guard !Task.isCancelled else { return }
                self.messages = fetchedMessages
                self.hasOlderMessages = fetchedMessages.count >= limit
                
                // Cache the loaded messages
                self.appState?.cacheMessages(fetchedMessages, for: self.conversationId)
                print("💾 Cached \(fetchedMessages.count) messages for conversation \(self.conversationId)")
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
            
            // Update cache with prepended messages
            appState?.prependToCachedMessages(olderMessages, for: conversationId)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func sendMessage() async {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        if !isAttachmentReady {
            error = "Please wait for attachments to finish uploading or remove failed items."
            return
        }
        
        inputText = ""

        let uploadedAttachments = pendingAttachments.compactMap { attachment -> Attachment? in
            if case .uploaded(let uploaded) = attachment.status {
                return uploaded
            }
            return nil
        }

        let attachmentRefs = uploadedAttachments.map {
            MessageAttachmentReference(id: $0.id, displayName: $0.displayName)
        }
        
        // Add user message immediately
        let userMessage = Message(
            id: "temp_\(UUID().uuidString)",
            conversationId: conversationId,
            role: .user,
            content: content,
            status: .sent,
            attachments: uploadedAttachments.isEmpty ? nil : uploadedAttachments
        )
        messages.append(userMessage)
        
        // Cache the new user message
        appState?.appendToCachedMessages(userMessage, for: conversationId)
        
        do {
            let response = try await networkService.sendMessage(
                conversationId: conversationId,
                content: content,
                attachments: attachmentRefs.isEmpty ? nil : attachmentRefs
            )
            
            // Update user message with real ID if needed
            if let index = messages.firstIndex(where: { $0.id == userMessage.id }) {
                // Keep the temp message, the real one comes from WebSocket
                _ = index
            }
            
            _ = response // Response indicates streaming started
            pendingAttachments.removeAll()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func switchConversation(to newConversationId: String) {
        // Cancel any in-flight operations immediately
        messageLoadTask?.cancel()
        conversationSwitchTask?.cancel()
        batchUpdateTask?.cancel()

        // Update conversation ID
        conversationId = newConversationId
        
        // Clear streaming state
        isStreaming = false
        streamingMessageId = nil
        streamingContent = ""
        pendingStreamContent = nil
        pendingStreamMessageId = nil
        pendingAttachments.removeAll()

        // Check cache first before clearing messages
        if let cachedMessages = appState?.getCachedMessages(for: newConversationId) {
            print("📦 Switching to cached conversation \(newConversationId): \(cachedMessages.count) messages")
            messages = cachedMessages
            hasOlderMessages = cachedMessages.count >= Configuration.initialMessageLimit
            isLoadingOlder = false
            
            // Just reconnect WebSocket, no need to reload messages
            webSocketService.connect(conversationId: newConversationId)
        } else {
            // No cache, clear and load
            messages = []
            hasOlderMessages = false
            isLoadingOlder = false

            // Debounce the actual load to coalesce rapid switches
            conversationSwitchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
                guard !Task.isCancelled, let self = self else { return }

                self.webSocketService.connect(conversationId: newConversationId)
                await self.loadMessages()
            }
        }
    }
    
    func retryMessage(_ message: Message, with editedContent: String) async {
        // Find the index of the message being retried
        guard let messageIndex = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        
        // Remove this message and all messages after it (including any assistant responses)
        messages.removeSubrange(messageIndex...)
        
        // Update cache to reflect the removed messages
        appState?.removeCachedMessagesFromIndex(messageIndex, for: conversationId)
        
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
        
        // Cache the new retry message
        appState?.appendToCachedMessages(userMessage, for: conversationId)
        
        do {
            _ = try await networkService.sendMessage(
                conversationId: conversationId,
                content: content,
                attachments: nil
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addAttachments(from urls: [URL]) async {
        guard !urls.isEmpty else { return }

        for url in urls {
            // Request security-scoped resource access for sandboxed apps
            let accessGranted = url.startAccessingSecurityScopedResource()

            if pendingAttachments.count >= Configuration.maxAttachmentsPerMessage {
                error = "You can attach up to \(Configuration.maxAttachmentsPerMessage) files."
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
                break
            }

            guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                error = "Failed to read attachment size."
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
                continue
            }

            if fileSize > Configuration.maxAttachmentSizeBytes {
                error = "\(url.lastPathComponent) is too large."
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
                continue
            }

            let currentTotal = pendingAttachments.reduce(0) { total, attachment in
                total + attachment.size
            }

            if currentTotal + fileSize > Configuration.maxTotalAttachmentSizeBytes {
                error = "Total attachment size exceeds the limit."
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
                continue
            }

            let mimeType = mimeTypeForExtension(url.pathExtension)
            let pending = PendingAttachment(
                id: UUID(),
                fileURL: url,
                displayName: url.lastPathComponent,
                size: fileSize,
                mimeType: mimeType,
                status: .uploading
            )

            pendingAttachments.append(pending)

            do {
                let uploaded = try await networkService.uploadAttachment(
                    conversationId: conversationId,
                    fileURL: url,
                    displayName: pending.displayName
                )

                updatePendingAttachment(pending.id) { attachment in
                    attachment.status = .uploaded(uploaded)
                    attachment.displayName = uploaded.displayName
                }
            } catch {
                updatePendingAttachment(pending.id) { attachment in
                    attachment.status = .failed(error.localizedDescription)
                }
            }
            
            // Release security-scoped resource access after upload is complete
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    func removeAttachment(_ attachment: PendingAttachment) async {
        if case .uploaded(let uploaded) = attachment.status {
            do {
                try await networkService.deleteAttachment(attachmentId: uploaded.id)
            } catch {
                self.error = error.localizedDescription
            }
        }

        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func renameAttachment(_ attachment: PendingAttachment, newName: String) async {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        updatePendingAttachment(attachment.id) { pending in
            pending.displayName = newName
        }

        if case .uploaded(let uploaded) = attachment.status {
            do {
                let updated = try await networkService.updateAttachmentName(
                    attachmentId: uploaded.id,
                    displayName: newName
                )

                updatePendingAttachment(attachment.id) { pending in
                    pending.status = .uploaded(updated)
                    pending.displayName = updated.displayName
                }
            } catch {
                updatePendingAttachment(attachment.id) { pending in
                    pending.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func updatePendingAttachment(_ id: UUID, update: (inout PendingAttachment) -> Void) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else { return }
        var attachment = pendingAttachments[index]
        update(&attachment)
        pendingAttachments[index] = attachment
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "txt", "log": return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "csv": return "text/csv"
        case "json": return "application/json"
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "js", "ts", "tsx", "jsx", "py", "swift", "java", "go", "rs", "rb", "c", "h", "cpp", "hpp":
            return "text/plain"
        default:
            return "application/octet-stream"
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
