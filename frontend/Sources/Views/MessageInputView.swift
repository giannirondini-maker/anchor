/**
 * Message Input View
 *
 * Text input area for composing messages
 */

import SwiftUI
import AppKit

struct MessageInputView: View {
    @Binding var text: String
    let isLoading: Bool
    var isConnected: Bool = true
    var attachments: [PendingAttachment] = []
    var isAttachmentReady: Bool = true
    let onSend: () -> Void
    var onAddAttachments: (([URL]) -> Void)? = nil
    var onRemoveAttachment: ((PendingAttachment) -> Void)? = nil
    var onRenameAttachment: ((PendingAttachment, String) -> Void)? = nil
    
    @State private var isFocused: Bool = false
    @State private var textHeight: CGFloat = 22
    @State private var editingAttachmentId: UUID?
    @State private var editedAttachmentName: String = ""
    
    // Allow sending when not loading and text is not empty
    // Note: We removed isConnected requirement - messages are sent via HTTP,
    // WebSocket is only for receiving streaming responses
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading && isAttachmentReady
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Reconnecting indicator - shown above the input area
            if !isConnected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Reconnecting...")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            attachmentChip(for: attachment)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            }
            
            HStack(alignment: .bottom, spacing: 12) {
                Button {
                    openAttachmentPanel()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add attachments")
                .accessibilityHint("Attach files to the next message")

                // Text Input using custom NSTextView
                SubmittableTextViewRepresentable(
                    text: $text,
                    isFocused: $isFocused,
                    textHeight: $textHeight,
                    placeholder: "Type a message...",
                    onSubmit: {
                        if self.canSend {
                            self.onSend()
                        }
                    }
                )
                .frame(height: max(textHeight, 22))
                .animation(.easeInOut(duration: 0.12), value: textHeight)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                // Send Button
                Button {
                    if canSend {
                        onSend()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(canSend ? .accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(isLoading ? "Sending message" : "Send message")
                .accessibilityHint(canSend ? "Sends the message you typed" : "Type a message first")
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message input area")
    }
    
    @ViewBuilder
    private func attachmentChip(for attachment: PendingAttachment) -> some View {
        HStack(spacing: 6) {
            statusIcon(for: attachment.status)

            if editingAttachmentId == attachment.id {
                TextField("Name", text: $editedAttachmentName, onCommit: {
                    let trimmed = editedAttachmentName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onRenameAttachment?(attachment, trimmed)
                    }
                    editingAttachmentId = nil
                    editedAttachmentName = ""
                })
                .textFieldStyle(.plain)
                .frame(minWidth: 120)
            } else {
                Text(attachment.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button {
                editingAttachmentId = attachment.id
                editedAttachmentName = attachment.displayName
            } label: {
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename attachment")

            Button {
                onRemoveAttachment?(attachment)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusIcon(for status: PendingAttachmentStatus) -> some View {
        switch status {
        case .uploading:
            ProgressView()
                .scaleEffect(0.6)
        case .uploaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    private func openAttachmentPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Select Attachments"
        panel.message = "Choose files to attach to your message"

        panel.begin { response in
            guard response == .OK else { return }
            onAddAttachments?(panel.urls)
        }
    }
}

// MARK: - Submittable Text View Representable

struct SubmittableTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var textHeight: CGFloat
    var placeholder: String
    var onSubmit: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view manually
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        // Create our custom text view with proper text system using factory method
        let textView = SubmittableTextView.create(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        
        // Ensure text view can become first responder and receive key events
        textView.isFieldEditor = false  // Allow multi-line and custom key handling
        
        // Set delegate and submit handler
        textView.delegate = context.coordinator
        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.handleSubmit()
        }
        
        // Configure scroll view
        scrollView.documentView = textView
        // Ensure there is no vertical elasticity (no bounce) and no scroll indicator
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        // Watch bounds changes so we can recalculate height when width changes and text reflows
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.boundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        
        // Store reference
        context.coordinator.textView = textView
        
        // Request focus after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            textView.window?.makeFirstResponder(textView)
        }
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmittableTextView else { return }
        
        // Update text if changed externally (e.g., cleared after send)
        if textView.string != text {
            textView.string = text
            context.coordinator.updateHeight(textView)
        }
        
        // Update placeholder visibility
        context.coordinator.updatePlaceholder(textView, show: text.isEmpty && !isFocused)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SubmittableTextViewRepresentable
        weak var textView: SubmittableTextView?
        private var placeholderLabel: NSTextField?
        
        init(_ parent: SubmittableTextViewRepresentable) {
            self.parent = parent
        }
        
        func handleSubmit() {
            parent.onSubmit()
        }
        
        // MARK: - NSTextViewDelegate for Enter key handling
        
        /// This delegate method intercepts commands before they are executed.
        /// Return true to indicate we handled the command, false to let the text view handle it.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Shift is held for Shift+Enter = newline
                if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
                    return false  // Let text view handle it (insert newline)
                }
                // Enter without Shift: trigger submit
                handleSubmit()
                return true  // We handled this command
            }
            // Let other commands be handled normally
            return false
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updatePlaceholder(textView, show: textView.string.isEmpty)
            updateHeight(textView)
        }
        
        func updateHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = max(usedRect.height + textView.textContainerInset.height * 2, 22)
            
            if abs(parent.textHeight - newHeight) > 1 {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        self.parent.textHeight = newHeight
                    }
                }
            }
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
            if let textView = notification.object as? NSTextView {
                updatePlaceholder(textView, show: false)
            }
        }
        
        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
            if let textView = notification.object as? NSTextView {
                updatePlaceholder(textView, show: textView.string.isEmpty)
            }
        }
        
        func updatePlaceholder(_ textView: NSTextView, show: Bool) {
            if placeholderLabel == nil {
                let label = NSTextField(labelWithString: parent.placeholder)
                label.textColor = NSColor.placeholderTextColor
                label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                label.backgroundColor = .clear
                label.isBordered = false
                label.isEditable = false
                label.isSelectable = false
                label.translatesAutoresizingMaskIntoConstraints = false
                
                textView.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
                    label.topAnchor.constraint(equalTo: textView.topAnchor, constant: 4)
                ])
                
                placeholderLabel = label
            }
            
            placeholderLabel?.isHidden = !show
        }
        
        @objc func boundsDidChange(_ notification: Notification) {
            guard let textView = self.textView else { return }
            // Recalculate height when width changes and text reflows
            updateHeight(textView)
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        }
    }
}
