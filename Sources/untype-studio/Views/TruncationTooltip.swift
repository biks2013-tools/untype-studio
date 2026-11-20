// untype-studio/Views/TruncationTooltip.swift
//
// Line-limited labels that reveal their full text in a tooltip — but only
// when the text is actually cut off. Use `.truncationTooltip(text, lines:)`
// in place of `.lineLimit(lines)`.
//
// How it detects truncation: a hidden copy of the same view is laid out at
// the same width with no line limit; if that copy is taller than the visible
// one, the visible label is truncated (whatever its truncation mode).

import SwiftUI

struct TruncationTooltip: ViewModifier {
    let fullText: String
    let lines: Int
    /// Tooltip to show when the label is NOT truncated (nil: none).
    let otherwise: String?

    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > shownHeight + 0.5 }

    func body(content: Content) -> some View {
        content
            .lineLimit(lines)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
            .background(alignment: .topLeading) {
                content
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    .accessibilityHidden(true)
            }
            .help(isTruncated ? fullText : (otherwise ?? ""))
    }
}

extension View {
    /// Limits the label to `lines` lines and shows `fullText` as a tooltip
    /// when the label doesn't fit; `otherwise` is the tooltip shown when it does.
    func truncationTooltip(_ fullText: String, lines: Int = 1, otherwise: String? = nil) -> some View {
        modifier(TruncationTooltip(fullText: fullText, lines: lines, otherwise: otherwise))
    }
}
