import Foundation
import Vision
import ImageIO

let directory = CommandLine.arguments[1]
let files = try FileManager.default.contentsOfDirectory(atPath: directory).filter { $0.hasPrefix("verified_") && $0.hasSuffix(".png") }.sorted()
for file in files {
    let url = URL(fileURLWithPath: directory).appendingPathComponent(file)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image).perform([request])
    let labels = (request.results ?? []).filter { $0.boundingBox.minX < 0.65 && $0.boundingBox.minY > 0.80 && $0.boundingBox.maxY < 0.94 }
        .compactMap { $0.topCandidates(1).first?.string }
    print("\(file)\t\(labels.joined(separator: " | "))")
}
