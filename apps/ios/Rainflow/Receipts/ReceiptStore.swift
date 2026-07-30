import CryptoKit
import Foundation
import UIKit

struct StagedReceipt: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let localURL: URL
    let originalFileName: String
    let mimeType: String
    let byteSize: Int64
    let sha256Hex: String
}

enum ReceiptStoreError: LocalizedError {
    case unreadableImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "The selected image could not be read."
        case .encodingFailed: "The receipt image could not be prepared for upload."
        }
    }
}

actor ReceiptStore {
    private let fileManager = FileManager.default
    private let maximumDimension: CGFloat = 2_400

    func stage(imageData: Data, originalFileName: String = "receipt.jpg") throws -> StagedReceipt {
        guard let image = UIImage(data: imageData) else { throw ReceiptStoreError.unreadableImage }
        let resized = image.resizedToFit(maximumDimension: maximumDimension)
        guard let jpegData = resized.jpegData(compressionQuality: 0.86) else {
            throw ReceiptStoreError.encodingFailed
        }

        let id = UUID()
        let directory = try receiptsDirectory()
        let url = directory.appendingPathComponent("\(id.uuidString.lowercased()).jpg")
        try jpegData.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])

        let digest = SHA256.hash(data: jpegData)
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

        return StagedReceipt(
            id: id,
            localURL: url,
            originalFileName: sanitizedFileName(originalFileName),
            mimeType: "image/jpeg",
            byteSize: Int64(jpegData.count),
            sha256Hex: sha256Hex
        )
    }

    func delete(_ receipt: StagedReceipt) {
        try? fileManager.removeItem(at: receipt.localURL)
    }

    func exists(_ receipt: StagedReceipt) -> Bool {
        fileManager.fileExists(atPath: receipt.localURL.path)
    }

    func removeAll() {
        guard let directory = try? receiptsDirectory() else { return }
        try? fileManager.removeItem(at: directory)
    }

    private func receiptsDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("Rainflow", isDirectory: true)
            .appendingPathComponent("Receipts", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sanitizedFileName(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let value = input.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(value)
        return result.isEmpty ? "receipt.jpg" : String(result.prefix(120))
    }
}

private extension UIImage {
    func resizedToFit(maximumDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maximumDimension, longest > 0 else { return self }
        let scale = maximumDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
