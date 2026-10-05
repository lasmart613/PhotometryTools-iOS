import UIKit
import Vision

/// On-device text recognition. `VNRecognizeTextRequest` does not upload the image.
enum BusinessCardOCR {
    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That photo could not be read. Retake the card in better light."
            }
        }
    }

    static func recognize(image: UIImage) throws -> BusinessCardFields {
        guard let cgImage = upright(image, maxSide: 2000) else {
            throw Failure.unreadable
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var lines: [[VNRecognizedTextObservation]] = []
        for observation in observations {
            if let index = lines.indices.last,
               abs(lines[index][0].boundingBox.midY - observation.boundingBox.midY) < 0.02 {
                lines[index].append(observation)
            } else {
                lines.append([observation])
            }
        }
        let text = lines.map { line in
            line
                .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }
        return BusinessCardParser.parse(lines: text)
    }

    private static func upright(_ image: UIImage, maxSide: CGFloat) -> CGImage? {
        let size = image.size
        guard size.width > 1, size.height > 1 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: target)).fill()
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.cgImage
    }
}
