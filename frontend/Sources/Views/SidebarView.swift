/**
 * Sidebar View
 *
 * Displays the list of conversations and controls
 */

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var showDeleteAllConfirmation = false
    
    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return appState.conversations
        }
        return appState.conversations.filter { conversation in
            // Match by title
            if conversation.title.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            // Match by any tag name
            return conversation.tags.contains { tag in
                tag.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    appState.startNewConversation()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("New Conversation")
                .accessibilityLabel("New Conversation")
                .accessibilityHint("Start a new chat conversation")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider()
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                
                TextField("Search conversations...", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search conversations")
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Conversation List
            if appState.isLoading && appState.conversations.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.2)
                    Text("Loading conversations...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredConversations.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "No conversations yet" : "No results found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(selection: $appState.selectedConversationId) {
                        ForEach(filteredConversations) { conversation in
                            ConversationRowView(conversation: conversation)
                                .tag(conversation.id)
                                .id(conversation.id)
                        }
                    }
                    .listStyle(.sidebar)
                    .padding(.top, 4)
                    .onChange(of: appState.conversations.first?.id) { _, newFirstId in
                        // Scroll to top when a new conversation is added at the top
                        if let firstId = newFirstId {
                            withAnimation {
                                proxy.scrollTo(firstId, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: searchText) { _, _ in
                        // Scroll to top when search criteria changes to ensure consistent display
                        if let firstId = filteredConversations.first?.id {
                            withAnimation {
                                proxy.scrollTo(firstId, anchor: .top)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                if !appState.conversations.isEmpty {
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete All Conversations")
                    .accessibilityLabel("Delete all conversations")
                    .accessibilityHint("Permanently deletes all chat conversations")
                }
                
                Spacer()
                
                Text("\(appState.conversations.count) conversation\(appState.conversations.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("\(appState.conversations.count) conversations")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .confirmationDialog(
            "Delete All Conversations?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task {
                    await appState.deleteAllConversations()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

// MARK: - Conversation Row View

struct ConversationRowView: View {
    @EnvironmentObject var appState: AppState
    let conversation: Conversation
    
    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var showDeleteConfirmation = false
    @State private var showTagEditor = false
    
    /// Returns the current conversation from appState to get updated tags
    private var currentConversation: Conversation {
        appState.conversations.first { $0.id == conversation.id } ?? conversation
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isEditing {
                    TextField("Title", text: $editedTitle, onCommit: saveTitle)
                        .textFieldStyle(.plain)
                        .onAppear {
                            editedTitle = conversation.title
                        }
                } else {
                    Text(conversation.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer()
            }
            
            HStack(alignment: .center, spacing: 6) {
                if let model = conversation.model {
                    Text(modelDisplayName(model))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Tag indicator button
                if !currentConversation.tags.isEmpty {
                    Button {
                        showTagEditor = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                            Text("\(currentConversation.tags.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Manage tags")
                    .accessibilityLabel("\(currentConversation.tags.count) tags")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                isEditing = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            Button {
                showTagEditor = true
            } label: {
                Label("Tags", systemImage: "tag")
            }
            
            Divider()
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete Conversation?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteConversation(conversation)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This conversation will be permanently deleted.")
        }
        .sheet(isPresented: $showTagEditor) {
            TagEditorView(conversation: currentConversation)
                .environmentObject(appState)
        }
    }
    
    private func saveTitle() {
        isEditing = false
        if !editedTitle.isEmpty && editedTitle != conversation.title {
            Task {
                await appState.updateConversation(id: conversation.id, title: editedTitle)
            }
        }
    }

    // Maps model IDs to user-friendly names
    // List reflects models available as of February 2026
    private func modelDisplayName(_ modelId: String) -> String {
        if modelId.contains("claude-haiku-4.5") { return "Haiku 4.5" }
        if modelId.contains("claude-opus-4.5") { return "Opus 4.5" }
        if modelId.contains("claude-sonnet-4.5") { return "Sonnet 4.5" }
        if modelId.contains("gemini-3-pro-preview") { return "Gemini 3 Pro" }
        if modelId.contains("gpt-5.2-codex") { return "GPT-5.2-Codex" }
        if modelId.contains("gpt-5.2") { return "GPT-5.2" }
        if modelId.contains("gpt-5.1-codex-max") { return "GPT-5.1-Codex-Max" }
        if modelId.contains("gpt-5.1-codex") { return "GPT-5.1-Codex" }
        if modelId.contains("gpt-5.1") { return "GPT-5.1" }
        if modelId.contains("gpt-5") { return "GPT-5" }
        if modelId.contains("gpt-5.1-codex-mini") { return "GPT-5.1-Codex-Mini" }
        if modelId.contains("gpt-5-mini") { return "GPT-5 mini" }
        if modelId.contains("gpt-4.1") { return "GPT-4.1" }
        return modelId
    }
}

// // #Preview {
//     SidebarView()
//         .environmentObject(AppState())
//         .frame(width: 280)
// }
