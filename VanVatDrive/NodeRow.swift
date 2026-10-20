import SwiftUI
import VanVatDriveKit

struct NodeRow: View {
    let node: DriveNode
    var sharedBy: String?
    var showDeleted = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: node.kind.symbol)
                .font(.title2)
                .foregroundStyle(node.kind.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if node.isSystemFolder { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
            else if node.myRole != .owner { Image(systemName: "person.2.fill").font(.caption).foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let sharedBy { parts.append("Shared by \(sharedBy)") }
        parts.append(Fmt.date(showDeleted ? (node.deletedAt ?? node.updatedAt) : node.updatedAt))
        if !node.isFolder { parts.append(Fmt.bytes(node.size)) }
        return parts.joined(separator: " · ")
    }
}
