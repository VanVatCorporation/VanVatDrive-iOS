import SwiftUI
import VanVatDriveKit

enum Fmt {
    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    /// Compute credits: whole numbers without decimals, otherwise one decimal.
    static func credits(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    static func date(_ d: Date) -> String { dateFormatter.string(from: d) }
}

enum FileKind {
    case folder, image, video, audio, pdf, text, archive, file

    static func of(isFolder: Bool, mime: String?, name: String) -> FileKind {
        if isFolder { return .folder }
        let m = mime ?? ""
        if m.hasPrefix("image/") { return .image }
        if m.hasPrefix("video/") { return .video }
        if m.hasPrefix("audio/") { return .audio }
        if m == "application/pdf" { return .pdf }
        if m.hasPrefix("text/") || m == "application/json" { return .text }
        let n = name.lowercased()
        if [".zip", ".rar", ".7z", ".tar", ".gz"].contains(where: { n.hasSuffix($0) }) { return .archive }
        return .file
    }

    var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .pdf: return "doc.richtext"
        case .text: return "doc.text"
        case .archive: return "doc.zipper"
        case .file: return "doc"
        }
    }

    var tint: Color {
        switch self {
        case .folder: return .gray
        case .image: return .red
        case .video: return .pink
        case .audio: return .orange
        case .pdf, .text: return .blue
        case .archive: return .purple
        case .file: return .secondary
        }
    }
}

extension DriveRole {
    var title: String {
        switch self {
        case .viewer: return "Viewer"
        case .editor: return "Editor"
        case .manager: return "Manager"
        case .owner: return "Owner"
        }
    }
}

extension DriveNode {
    var kind: FileKind { FileKind.of(isFolder: isFolder, mime: mimeType, name: name) }
}
extension PublicNode {
    var kind: FileKind { FileKind.of(isFolder: isFolder, mime: mimeType, name: name) }
}
