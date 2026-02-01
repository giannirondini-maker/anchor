/**
 * Submittable Text View
 *
 * Custom NSTextView subclass for message input.
 * Enter key handling is done via NSTextViewDelegate.textView(_:doCommandBy:)
 * in the Coordinator class for more reliable interception.
 */

import AppKit

/// Custom NSTextView for message input
class SubmittableTextView: NSTextView {
    
    /// Callback when Enter is pressed (without Shift) - kept for backwards compatibility
    /// Note: Primary Enter handling is now in the Coordinator's textView(_:doCommandBy:)
    var onSubmit: (() -> Void)?
    
    /// Creates a SubmittableTextView with proper text system setup
    static func create(frame: NSRect) -> SubmittableTextView {
        // Create text system components
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: NSSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        return SubmittableTextView(frame: frame, textContainer: textContainer)
    }
}
