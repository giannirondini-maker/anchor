/**
 * Message List View
 *
 * Displays the scrollable list of messages
 */

import SwiftUI
import MarkdownUI

struct MessageListView: View {
    let messages: [Message]
    let isLoading: Bool
    var hasOlderMessages: Bool = false
    var isLoadingOlder: Bool = false
    var onRetry: ((Message, String) -> Void)?  // Now passes the edited content
    var onLoadOlder: (() -> Void)?
    
    @State private var isPinnedToBottom = true
    @State private var scrollViewHeight: CGFloat = 0
    
    private var showStreamingIndicator: Bool {
        guard isLoading else { return false }
        // Don't show streaming indicator if we already have a placeholder message being streamed
        if let lastMessage = messages.last,
           lastMessage.role == .assistant,
           lastMessage.status == .sending {
            return false
        }
        return true
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Use regular VStack for small message counts to avoid prefetching overhead
                // Use LazyVStack only for large message counts
                Group {
                    if messages.count <= 20 {
                        // No prefetching overhead for small lists
                        VStack(spacing: 16) {
                            messageListContent
                        }
                    } else {
                        // Only use lazy loading for large lists
                        LazyVStack(spacing: 16, pinnedViews: []) {
                            messageListContent
                        }
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .id("scroll-\(messages.first?.id ?? "empty")")
            .coordinateSpace(name: "messageScroll")
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollViewHeightPreferenceKey.self,
                        value: geo.size.height
                    )
                }
            )
            .accessibilityLabel("Message history")
            .onPreferenceChange(ScrollViewHeightPreferenceKey.self) { height in
                scrollViewHeight = height
            }
            .onPreferenceChange(BottomAnchorPreferenceKey.self) { bottomY in
                isPinnedToBottom = bottomY <= scrollViewHeight + 12
            }
            .onChange(of: messages.count) { oldCount, newCount in
                guard isPinnedToBottom else { return }
                
                // Scroll to bottom when new messages arrive
                DispatchQueue.main.async {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.content) { _, _ in
                // Scroll when streaming content updates
                guard isPinnedToBottom else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var messageListContent: some View {
        // "Load Older Messages" button
        if hasOlderMessages {
            Button {
                onLoadOlder?()
            } label: {
                HStack(spacing: 6) {
                    if isLoadingOlder {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle")
                    }
                    Text(isLoadingOlder ? "Loading..." : "Load Older Messages")
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(isLoadingOlder)
            .id("load-older")
        }

        ForEach(messages) { message in
            MessageBubbleView(message: message, onRetry: onRetry)
                .equatable() // Use Equatable conformance to skip re-renders
                .id(message.id)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(message.role == .user ? "Your message" : "Assistant response")")
        }

        if showStreamingIndicator {
            StreamingIndicatorView()
                .id("loading")
                .accessibilityLabel("Assistant is thinking")
        }

        // Invisible anchor for scrolling
        Color.clear
            .frame(height: 1)
            .id("bottom")
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: BottomAnchorPreferenceKey.self,
                        value: geo.frame(in: .named("messageScroll")).maxY
                    )
                }
            )
    }
}

private struct BottomAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View, Equatable {
    let message: Message
    var onRetry: ((Message, String) -> Void)?

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editedContent: String = ""
    @State private var showCopiedFeedback = false
    @State private var cachedHeight: CGFloat?

    // Equatable conformance to prevent unnecessary re-renders
    static func == (lhs: MessageBubbleView, rhs: MessageBubbleView) -> Bool {
        lhs.message.id == rhs.message.id &&
        lhs.message.content == rhs.message.content &&
        lhs.message.status == rhs.message.status &&
        lhs.message.errorMessage == rhs.message.errorMessage &&
        lhs.message.attachments == rhs.message.attachments
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var bubbleColor: Color {
        if message.status == .error {
            return Color.red.opacity(0.1)
        }
        if isEditing {
            return Color.accentColor.opacity(0.08)
        }
        return isUser ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor)
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Role indicator
                HStack(spacing: 4) {
                    if !isUser {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(isUser ? "You" : "Assistant")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    if isEditing {
                        Text("• Editing")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }

                    if isUser {
                        Image(systemName: "person.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Message content
                VStack(alignment: .leading, spacing: 8) {
                    if isUser, let attachments = message.attachments, !attachments.isEmpty {
                        attachmentList(attachments)
                    }

                    if message.status == .sending && message.content.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(Color.secondary)
                                    .frame(width: 6, height: 6)
                                    .opacity(0.5)
                            }
                        }
                        .padding(.vertical, 8)
                    } else if isEditing {
                        // Editable text field
                        TextEditor(text: $editedContent)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 40)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isUser {
                        // User messages: plain text with slightly increased font
                        Text(message.content)
                            .font(.system(size: 15))
                            .textSelection(.enabled)
                    } else {
                        // Assistant messages: render as cached markdown to prevent layout thrashing
                        CachedMarkdownView(content: message.content)
                            .equatable()
                    }

                    if message.status == .error {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(message.errorMessage ?? "An error occurred")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(12)
                .background(bubbleColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isEditing ? Color.accentColor : Color.primary.opacity(0.05), lineWidth: isEditing ? 2 : 1)
                )
                // Add extra side padding so messages don't touch the window edge
                .padding(.leading, isUser ? 0 : 20)
                .padding(.trailing, isUser ? 20 : 0)
                .background(
                    // Measure height only once, then cache it
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MessageHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                )
                .onPreferenceChange(MessageHeightPreferenceKey.self) { height in
                    // Only cache height for completed messages, not during editing/streaming
                    if cachedHeight == nil && !isEditing && message.status != .sending {
                        cachedHeight = height
                    }
                }

                // Timestamp and actions
                HStack(spacing: 12) {
                    if !isEditing {
                        Text(message.createdAt, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if isEditing {
                        // Edit mode buttons
                        Button {
                            // Cancel editing
                            isEditing = false
                            editedContent = ""
                        } label: {
                            Text("Cancel")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        
                        Button {
                            // Submit edited message
                            let content = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !content.isEmpty {
                                onRetry?(message, content)
                            }
                            isEditing = false
                            editedContent = ""
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Resend")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    } else {
                        // Copy button - always visible on hover
                        Button {
                            copyToClipboard()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                                if showCopiedFeedback {
                                    Text("Copied!")
                                        .font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(showCopiedFeedback ? .green : .secondary)
                        .help(showCopiedFeedback ? "Copied to clipboard" : "Copy to clipboard")
                        .accessibilityLabel(showCopiedFeedback ? "Copied to clipboard" : "Copy message")
                        .accessibilityHint("Copies the message content to clipboard")
                        .opacity(isHovering || showCopiedFeedback ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: showCopiedFeedback)
                        
                        // Edit & Retry button - only for user messages
                        if isUser {
                            Button {
                                editedContent = message.content
                                isEditing = true
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "pencil")
                                    Image(systemName: "arrow.clockwise")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(message.status == .error ? .orange : .secondary)
                            .help("Edit and retry message")
                            .accessibilityLabel("Edit and retry")
                            .accessibilityHint("Edit this message and send it again")
                            .opacity(isHovering || message.status == .error ? 1 : 0)
                        }
                    }
                }
            }
            
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)
        
        // Show copied feedback
        withAnimation {
            showCopiedFeedback = true
        }
        
        // Hide feedback after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    @ViewBuilder
    private func attachmentList(_ attachments: [Attachment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attachments")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(attachments) { attachment in
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(attachment.displayName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Streaming Indicator View

struct StreamingIndicatorView: View {
    @State private var animationPhase = 0.0
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Assistant")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == Double(i) ? 1.2 : 0.8)
                            .opacity(animationPhase == Double(i) ? 1.0 : 0.4)
                    }
                    
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            
            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: false)) {
                animationPhase = 3.0
            }
        }
    }
}

// MARK: - Cached Markdown View

/// An equatable wrapper around MarkdownUI's Markdown view.
/// SwiftUI uses the Equatable conformance to skip re-rendering when the content
/// hasn't changed, which prevents the layout thrashing that causes UI hangs
/// during rapid conversation switching.
struct CachedMarkdownView: View, Equatable {
    let content: String
    
    static func == (lhs: CachedMarkdownView, rhs: CachedMarkdownView) -> Bool {
        lhs.content == rhs.content
    }
    
    var body: some View {
        Markdown(content)
            .markdownTheme(.gitHub)
            .markdownTextStyle {
                FontSize(15)
            }
            .textSelection(.enabled)
    }
}

// MARK: - Height Preference Key

struct MessageHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// // #Preview {
//     MessageListView(
//         messages: [
//             Message(id: "1", conversationId: "conv1", role: .user, content: "Hello, how are you?"),
//             Message(id: "2", conversationId: "conv1", role: .assistant, content: "I'm doing well, thank you for asking! How can I help you today?\n\n```swift\nlet greeting = \"Hello, World!\"\nprint(greeting)\n```"),
//             Message(id: "3", conversationId: "conv1", role: .user, content: "Can you explain what Swift is?"),
//             Message(id: "4", conversationId: "conv1", role: .assistant, content: "Swift is a powerful and intuitive programming language developed by Apple for iOS, macOS, watchOS, and tvOS app development.\n\n## Key Features\n\n- **Type Safety**: Swift is a type-safe language\n- **Modern Syntax**: Clean and expressive\n- **Performance**: Fast and efficient", status: .sent)
//         ],
//         isLoading: false
//     )
//     .frame(width: 600, height: 400)
// }
