/**
 * Tag Editor View
 *
 * Modal view for managing conversation tags.
 * Displays existing tags as badges with remove buttons,
 * and provides an input field for adding new tags (comma-separated).
 */

import SwiftUI

struct TagEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    let conversation: Conversation
    
    @State private var newTagInput = ""
    @State private var isAddingTags = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Manage Tags")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            
            Divider()
            
            // Current Tags
            if conversation.tags.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No tags yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                ScrollView {
                    FlowLayout(spacing: 8) {
                        ForEach(conversation.tags) { tag in
                            TagBadgeView(tag: tag) {
                                removeTag(tag)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            
            Divider()
            
            // Add New Tag
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Tags")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("Enter tag names (comma-separated)", text: $newTagInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addTags()
                        }
                        .disabled(isAddingTags)
                    
                    Button {
                        addTags()
                    } label: {
                        if isAddingTags {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(newTagInput.trimmingCharacters(in: .whitespaces).isEmpty || isAddingTags)
                    .accessibilityLabel("Add tags")
                }
                
                Text("Separate multiple tags with commas")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 350, height: 320)
    }
    
    private func addTags() {
        guard !newTagInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isAddingTags = true
        let input = newTagInput
        newTagInput = ""
        
        Task {
            await appState.addTagsToConversation(conversationId: conversation.id, tagInput: input)
            isAddingTags = false
        }
    }
    
    private func removeTag(_ tag: Tag) {
        Task {
            await appState.removeTagFromConversation(conversationId: conversation.id, tagId: tag.id)
        }
    }
}

// MARK: - Tag Badge View

struct TagBadgeView: View {
    let tag: Tag
    let onRemove: () -> Void
    
    var tagColor: Color {
        if let colorHex = tag.color, !colorHex.isEmpty {
            return Color(hex: colorHex) ?? .blue
        }
        return .blue
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag.name)
                .font(.caption)
                .lineLimit(1)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(tag.name) tag")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tagColor.opacity(0.8))
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}

// MARK: - Flow Layout

/// A layout that arranges views in a flowing manner, wrapping to new lines as needed
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }
        
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        // Only accept 6-character hex strings (RRGGBB)
        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
