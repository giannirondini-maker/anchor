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
            if let conversation = appState.selectedConversation {
                ChatView(conversation: conversation)
            } else {
                EmptyStateView()
            }
        }
        .navigationSplitViewStyle(.balanced)
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
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Conversation Selected")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Select a conversation from the sidebar or create a new one.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            Button {
                Task {
                    await appState.createConversation()
                }
            } label: {
                Label("New Conversation", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// // #Preview {
//     MainWindowView()
//         .environmentObject(AppState())
// }
