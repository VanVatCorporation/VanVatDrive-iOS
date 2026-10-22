import SwiftUI
import UIKit
import VanVatDriveKit

/// A 40pt rounded thumbnail: memory cache, then the disk cache, then one download. While loading (or when it fails, e.g.
/// today's allowance is used up) the type icon stays.
struct ThumbnailView<Placeholder: View>: View {
    let node: DriveNode
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(AppModel.self) private var model
    @State private var image: UIImage?
    private static var memory: NSCache<NSString, UIImage> { Shared.cache }
    private enum Shared { static let cache: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 400; return c }() }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: node.id) {
            if let hit = Self.memory.object(forKey: node.id as NSString) { image = hit; return }
            guard let data = try? await model.client.thumbnailData(for: node), let img = UIImage(data: data) else { return }
            Self.memory.setObject(img, forKey: node.id as NSString)
            image = img
        }
    }
}

struct NodeRow: View {
    let node: DriveNode
    var sharedBy: String?
    var showDeleted = false
    /// The account's "Preview thumbnails" setting (never in the trash).
    var thumbnails = false

    var body: some View {
        HStack(spacing: 14) {
            if thumbnails && DriveClient.hasThumbnail(node) {
                ThumbnailView(node: node) { icon }
            } else {
                icon
            }
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

    private var icon: some View {
        Image(systemName: node.kind.symbol)
            .font(.title2)
            .foregroundStyle(node.kind.tint)
            .frame(width: 40, height: 40)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let sharedBy { parts.append("Shared by \(sharedBy)") }
        parts.append(Fmt.date(showDeleted ? (node.deletedAt ?? node.updatedAt) : node.updatedAt))
        if !node.isFolder { parts.append(Fmt.bytes(node.size)) }
        return parts.joined(separator: " · ")
    }
}
