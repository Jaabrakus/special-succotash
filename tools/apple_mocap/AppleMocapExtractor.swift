import Foundation
import AVFoundation
import Vision
import ImageIO
import simd

struct Arguments {
    let input: String
    let output: String
    let fps: Double

    init?() {
        let values = CommandLine.arguments
        guard values.count >= 3 else { return nil }
        input = values[1]
        output = values[2]
        if let index = values.firstIndex(of: "--fps"), index + 1 < values.count {
            fps = max(1.0, min(60.0, Double(values[index + 1]) ?? 30.0))
        } else {
            fps = 30.0
        }
    }
}

func matrixTranslation(_ matrix: simd_float4x4) -> [String: Float] {
    return ["x": matrix.columns.3.x, "y": matrix.columns.3.y, "z": matrix.columns.3.z]
}

func cleanKey<T>(_ value: T) -> String {
    let description = String(describing: value)
    guard let marker = description.range(of: "_rawValue: ") else { return description }
    let suffix = description[marker.upperBound...]
    return String(suffix.prefix(while: { $0 != ")" }))
}

guard let args = Arguments() else {
    FileHandle.standardError.write(Data("usage: apple_mocap_extract INPUT_VIDEO OUTPUT_JSON [--fps 30]\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: args.input)
let outputURL = URL(fileURLWithPath: args.output)
let asset = AVURLAsset(url: inputURL)
let duration = try await asset.load(.duration)
let durationSeconds = CMTimeGetSeconds(duration)
guard durationSeconds.isFinite && durationSeconds > 0 else {
    throw NSError(domain: "SOCOMAppleMocap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Video duration is invalid"])
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let request = VNDetectHumanBodyPose3DRequest()
let frameCount = Int(floor(durationSeconds * args.fps)) + 1
var frames: [[String: Any]] = []
var detectedFrames = 0

for frameIndex in 0..<frameCount {
    let seconds = min(durationSeconds, Double(frameIndex) / args.fps)
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    do {
        let image = try await generator.image(at: time).image
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            frames.append(["frame": frameIndex, "time": seconds, "detected": false, "joints": [:]])
            continue
        }
        var joints: [String: Any] = [:]
        for jointName in observation.availableJointNames {
            guard let point = try? observation.recognizedPoint(jointName) else { continue }
            let imagePoint = try? observation.pointInImage(jointName)
            var joint: [String: Any] = [
                "model": matrixTranslation(point.position),
                "local": matrixTranslation(point.localPosition),
                "parent": cleanKey(point.parentJoint),
            ]
            if let imagePoint {
                joint["image"] = ["x": imagePoint.x, "y": imagePoint.y]
            }
            joints[cleanKey(jointName)] = joint
        }
        detectedFrames += 1
        frames.append([
            "frame": frameIndex,
            "time": seconds,
            "detected": true,
            "body_height": observation.bodyHeight,
            "height_estimation": observation.heightEstimation.rawValue,
            "root_to_camera": [
                observation.cameraOriginMatrix.columns.3.x,
                observation.cameraOriginMatrix.columns.3.y,
                observation.cameraOriginMatrix.columns.3.z,
                observation.cameraOriginMatrix.columns.3.w,
            ],
            "joints": joints,
        ])
    } catch {
        frames.append(["frame": frameIndex, "time": seconds, "detected": false, "error": error.localizedDescription, "joints": [:]])
    }
    if frameIndex % max(1, Int(args.fps)) == 0 {
        print("PROGRESS \(frameIndex)/\(frameCount)")
    }
}

let result: [String: Any] = [
    "schema": "socom_apple_body_pose_3d_v1",
    "source_video": inputURL.path,
    "fps": args.fps,
    "duration": durationSeconds,
    "frame_count": frameCount,
    "detected_frames": detectedFrames,
    "detected_ratio": Double(detectedFrames) / Double(max(1, frameCount)),
    "coordinate_space": "Apple Vision model space; root-relative meters; image points use normalized lower-left origin",
    "frames": frames,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outputURL, options: .atomic)
print("APPLE_MOCAP_COMPLETE \(outputURL.path) \(detectedFrames)/\(frameCount)")
