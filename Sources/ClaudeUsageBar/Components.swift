import SwiftUI

/// Rounded group with an optional small uppercase title; every tab is a stack of these.
struct Card<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        (self.title, self.content) = (title, content())
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        VStack(alignment: .leading, spacing: 6) {
            if let title { SectionTitle(title) }
            content
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
    }
}

/// Small tinted capsule: notes, worktree / dirty / ahead / behind markers.
struct Chip: View {
    let text: String
    let color: Color
    init(_ text: String, _ color: Color) { (self.text, self.color) = (text, color) }

    var body: some View {
        Text(text).font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(color.mix(with: .primary, by: 0.35))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
    }
}

/// Centred icon + one line (+ optional hint) for empty and failed tabs.
struct EmptyNote: View {
    let icon: String, text: String, hint: String?
    init(_ icon: String, _ text: String, hint: String? = nil) { (self.icon, self.text, self.hint) = (icon, text, hint) }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title)
            Text(text).font(.callout)
            if let hint { Text(hint).font(.caption) }
        }
        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}
