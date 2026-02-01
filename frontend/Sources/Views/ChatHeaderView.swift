/**
 * Chat Header View
 *
 * Displays conversation title and model selector
 */

import SwiftUI
import AppKit

struct ChatHeaderView: View {
    let conversation: Conversation
    @Binding var selectedModel: String
    let availableModels: [ModelInfo]
    let onModelChange: (String) -> Void
    var messages: [Message] = []
    
    @EnvironmentObject var appState: AppState
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var showExportSuccess = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Conversation Title
            if isEditingTitle {
                TextField("Title", text: $editedTitle, onCommit: saveTitle)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .frame(maxWidth: 300)
                    .onAppear {
                        editedTitle = conversation.title
                    }
            } else {
                Button {
                    isEditingTitle = true
                } label: {
                    HStack {
                        Text(conversation.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Right-side controls: export indicator, model selector and export button grouped together
            HStack(spacing: 8) {
                if showExportSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Exported!")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .transition(.opacity)
                }

                // Compact model selector
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                        .padding(.leading, 1)

                    Picker("Model", selection: $selectedModel) {
                        ForEach(availableModels) { model in
                            Text(model.name)
                                .tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250, alignment: .leading)
                    .onChange(of: selectedModel) { _, newValue in
                        onModelChange(newValue)
                    }
                    .accessibilityLabel("Select AI model")
                    .accessibilityHint("Choose which AI model to use for this conversation")
                }
                .fixedSize(horizontal: true, vertical: false)

                // Export Button
                Button {
                    exportConversation()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Export to Markdown")
                .accessibilityLabel("Export conversation")
                .accessibilityHint("Save this conversation as a Markdown file")
                .disabled(messages.isEmpty)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat header")
    }
    
    private func saveTitle() {
        isEditingTitle = false
        if !editedTitle.isEmpty && editedTitle != conversation.title {
            Task {
                await appState.updateConversation(id: conversation.id, title: editedTitle)
            }
        }
    }
    
    private func exportConversation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(conversation.title).md"
        panel.title = "Export Conversation"
        panel.message = "Choose where to save the conversation as Markdown"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            let markdown = generateMarkdown()
            
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                showExportSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showExportSuccess = false
                }
            } catch {
                print("Failed to export: \(error)")
            }
        }
    }
    
    private func generateMarkdown() -> String {
        var md = "# \(conversation.title)\n\n"
        md += "**Date:** \(conversation.createdAt.formatted())\n"
        if let model = conversation.model {
            md += "**Model:** \(model)\n"
        }
        md += "\n---\n\n"
        
        for message in messages {
            let role = message.role == .user ? "**You**" : "**Assistant**"
            md += "\(role)\n\n"
            md += "\(message.content)\n\n"
            md += "---\n\n"
        }
        
        return md
    }
}

// // #Preview {
//     ChatHeaderView(
//         conversation: Conversation(id: "1", title: "Test Chat", model: "claude-sonnet-4-20250514"),
//         selectedModel: .constant("claude-sonnet-4-20250514"),
//         availableModels: [
//             ModelInfo(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", multiplier: 1.0, capabilities: []),
//             ModelInfo(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", multiplier: 1.0, capabilities: [])
//         ],
//         onModelChange: { _ in }
//     )
//     .environmentObject(AppState())
// }
