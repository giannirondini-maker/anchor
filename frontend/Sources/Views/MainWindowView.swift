/**
 * Main Window View
 *
 * Primary container with sidebar and chat area
 */

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        // Main Content
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 350)
        } detail: {
            if appState.isDraftMode && appState.selectedConversationId == nil {
                DraftChatView()
            } else if let conversation = appState.selectedConversation {
                ChatView(conversation: conversation)
            } else {
                EmptyStateView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: appState.selectedConversationId) { _, newId in
            // Exit draft mode when user selects a conversation
            if newId != nil {
                appState.isDraftMode = false
            }
        }
        .alert("Error", isPresented: .constant(appState.error != nil)) {
            Button("OK") {
                appState.dismissError()
            }
        } message: {
            if let error = appState.error {
                Text(error.message)
            }
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                
                Text("No Conversation Selected")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("Select a conversation from the sidebar or start a new one.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Draft Chat View

struct DraftChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    @State private var selectedModel: String = Configuration.defaultModel
    @State private var wittyMessage: String = ""
    
    private let wittyMessages = [
        "What brilliant idea shall we explore today?",
        "I'm all ears (or rather, all neural networks) 🤖",
        "Let's create something amazing together",
        "Ready to dive into your questions",
        "What's on your mind?",
        "Let's turn your thoughts into reality",
        "Your wish is my command (within reason) 😊",
        "Ask me anything – I'm here to help",
        "Fueled by coffee ☕️",
        "Let me grab my coffee and we're good to go ☕️",
        "Your ideas deserve a strong cup of coffee ☕️",
        "Tea 🫖 and code - the perfect combination",
        "Let's brew up some brilliant ideas together 🍵",
        "Time to caffeinate and create something awesome ☕️",
        "Every great idea starts with coffee ☕️",
        "What's your next big idea? (I've got coffee ready) ☕️"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with model selector (matching ChatHeaderView style)
            HStack(spacing: 16) {
                Text("New Conversation")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Model selector
                HStack(spacing: 6) {
                    if appState.isLoadingModels {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "cpu")
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                            .padding(.leading, 1)
                    }
                    
                    if appState.isLoadingModels {
                        Text("Loading models...")
                            .foregroundColor(.secondary)
                            .frame(width: 280, alignment: .leading)
                    } else {
                        Picker("Model", selection: $selectedModel) {
                            ForEach(appState.availableModels) { model in
                                Text(model.displayName)
                                    .tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 280, alignment: .leading)
                        .disabled(appState.availableModels.isEmpty)
                        .accessibilityLabel("Select AI model")
                        .accessibilityHint("Choose which AI model to use for this conversation")
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Center message area
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 24) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text(wittyMessage)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .padding(.bottom, 60)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Input area - reusing MessageInputView for consistent behavior
            MessageInputView(
                text: $inputText,
                isLoading: false,
                isConnected: true,
                onSend: sendMessage
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Pick a random message once when view appears
            wittyMessage = wittyMessages.randomElement() ?? "What can I help you with today?"
            // Set default model from available models
            selectedModel = AppState.chooseModel(requested: nil, available: appState.availableModels)
        }
    }
    
    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        
        // Clear input immediately for better UX
        inputText = ""
        
        // Create the conversation with the first message
        // The message is now stored in AppState.pendingMessage and will be sent by ChatView
        Task {
            await appState.commitDraftConversation(firstMessage: message, model: selectedModel)
        }
    }
}

// // #Preview {
//     MainWindowView()
//         .environmentObject(AppState())
// }
