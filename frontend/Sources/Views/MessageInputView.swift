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
    let onSend: () -> Void
    
    @State private var isFocused: Bool = false
    @State private var textHeight: CGFloat = 22
    
    // Allow sending when not loading and text is not empty
    // Note: We removed isConnected requirement - messages are sent via HTTP,
    // WebSocket is only for receiving streaming responses
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
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
            
            HStack(alignment: .bottom, spacing: 12) {
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
                .frame(height: min(max(textHeight, 22), 120))
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
                    self.parent.textHeight = newHeight
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
    }
}
