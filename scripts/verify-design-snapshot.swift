#!/usr/bin/env swift
import AppKit
import Foundation
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Bessie design snapshot check failed: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count >= 2 else {
    fail("usage: verify-design-snapshot.swift <window.png> [dark|light] [--region x,y,width,height] [--minimum-size width,height]")
}

let path = CommandLine.arguments[1]
var arguments = Array(CommandLine.arguments.dropFirst(2))
var appearance = "dark"
if let first = arguments.first, first == "dark" || first == "light" {
    appearance = first
    arguments.removeFirst()
}
guard appearance == "dark" || appearance == "light" else {
    fail("appearance must be dark or light")
}

func dimensions(_ value: String, count: Int, option: String) -> [Int] {
    let values = value.split(separator: ",").compactMap { Int($0) }
    guard values.count == count else { fail("\(option) expects \(count) comma-separated integers") }
    return values
}

var requestedRegion: [Int]?
var minimumSize = [1080, 680]
var exactSize: [Int]?
var requireOpaque = false
var surfaceOnly = false
var maximumChroma: Double?
var requiredCopy: [String] = []
while !arguments.isEmpty {
    let option = arguments.removeFirst()
    guard !arguments.isEmpty else { fail("missing value for \(option)") }
    let value = arguments.removeFirst()
    switch option {
    case "--region": requestedRegion = dimensions(value, count: 4, option: option)
    case "--minimum-size": minimumSize = dimensions(value, count: 2, option: option)
    case "--exact-size": exactSize = dimensions(value, count: 2, option: option)
    case "--require-opaque": requireOpaque = value == "true"
    case "--surface-only": surfaceOnly = value == "true"
    case "--max-chroma": maximumChroma = Double(value)
    case "--require-copy": requiredCopy.append(value)
    default: fail("unknown option \(option)")
    }
}
guard let image = NSImage(contentsOfFile: path) else {
    fail("could not decode \(path)")
}
var proposed = NSRect(origin: .zero, size: image.size)
guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
    fail("could not rasterize \(path)")
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
let width = bitmap.pixelsWide
let height = bitmap.pixelsHigh

if let exactSize, width != exactSize[0] || height != exactSize[1] {
    fail("expected exact snapshot size \(exactSize[0])×\(exactSize[1]), got \(width)×\(height)")
}

guard width >= minimumSize[0], height >= minimumSize[1] else {
    fail("expected snapshot to be at least \(minimumSize[0])×\(minimumSize[1]), got \(width)×\(height)")
}

// The default region is a quiet stretch of the expanded rail. Callers can use
// --region for any semantic surface without introducing full-image equality.
let region = requestedRegion ?? [12, 80, min(224, width - 12), max(1, height - 150)]
guard region.allSatisfy({ $0 >= 0 }), region[2] > 0, region[3] > 0,
      region[0] + region[2] <= width, region[1] + region[3] <= height else {
    fail("sample region is outside the \(width)×\(height) snapshot")
}
let xRange = region[0]..<(region[0] + region[2])
let topStart = region[1]
let topEnd = region[1] + region[3]
var luminances: [Double] = []
var chromaSum = 0.0
var sampled = 0
var decoded = 0
var transparent = 0

for topY in stride(from: topStart, to: topEnd, by: 2) {
    let y = height - 1 - topY
    for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: 2) {
        guard let source = bitmap.colorAt(x: x, y: y) else {
            fail("could not read snapshot pixel at \(x),\(y)")
        }
        let color = source.usingColorSpace(.sRGB) ?? source
        if color.alphaComponent < 0.999 { transparent += 1 }
        decoded += 1
        let r = Double(color.redComponent * 255)
        let g = Double(color.greenComponent * 255)
        let b = Double(color.blueComponent * 255)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let belongsToRail = surfaceOnly || appearance == "light" || luminance < 30
        guard belongsToRail else { continue }
        luminances.append(luminance)
        chromaSum += abs(r - g) + abs(g - b) + abs(b - r)
        sampled += 1
    }
}

guard sampled >= 2_000 else {
    fail("not enough \(appearance) rail pixels were present (decoded \(decoded), sampled \(sampled))")
}
let mean = luminances.reduce(0, +) / Double(luminances.count)
let variance = luminances.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(luminances.count)
let standardDeviation = sqrt(variance)
let meanChroma = chromaSum / Double(sampled)

var plateLuminances: [Double] = []
if !surfaceOnly {
    for topY in stride(from: 40, to: max(41, height - 12), by: 2) {
        let y = height - 1 - topY
        for x in stride(from: 0, to: min(8, width), by: 2) {
            guard let source = bitmap.colorAt(x: x, y: y) else {
                fail("could not read window-plate pixel at \(x),\(y)")
            }
            let color = source.usingColorSpace(.sRGB) ?? source
            let r = Double(color.redComponent * 255)
            let g = Double(color.greenComponent * 255)
            let b = Double(color.blueComponent * 255)
            plateLuminances.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
    }
}
let plateMean = plateLuminances.isEmpty ? 0 : plateLuminances.reduce(0, +) / Double(plateLuminances.count)
let plateVariance = plateLuminances.isEmpty ? 0 : plateLuminances.reduce(0) {
    $0 + ($1 - plateMean) * ($1 - plateMean)
} / Double(plateLuminances.count)
let plateStandardDeviation = sqrt(plateVariance)

if requireOpaque, transparent > 0 { fail("snapshot contains \(transparent) sampled translucent pixels") }
if let maximumChroma, meanChroma > maximumChroma {
    fail(String(format: "snapshot exceeds monochrome chroma budget (%.2f > %.2f)", meanChroma, maximumChroma))
}

if !requiredCopy.isEmpty {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
    catch { fail("Vision copy recognition failed: \(error.localizedDescription)") }
    let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    for copy in requiredCopy where !recognized.localizedCaseInsensitiveContains(copy) {
        fail("required visible copy was not recognized: \(copy)")
    }
}

if surfaceOnly {
    // Modal, splash, and popover captures do not contain the shell rail. Their
    // opacity, copy, dimensions, and caller-provided chroma budget still gate.
} else if appearance == "light" {
    let sorted = luminances.sorted()
    let median = sorted[sorted.count / 2]
    guard median > 225 else {
        fail(String(format: "rail is not using the achromatic light palette (median luminance %.2f)", median))
    }
} else {
    guard mean < 35 else {
        fail(String(format: "rail is not using the fixed dark surface tint (mean luminance %.2f)", mean))
    }
}
guard surfaceOnly || plateStandardDeviation >= 1.5 else {
    fail(String(format: "window plate has no measurable cowprint texture (%@-pixel σ %.2f)", appearance, plateStandardDeviation))
}
guard surfaceOnly || meanChroma < 1.5 else {
    fail(String(format: "rail contains hue outside the monochrome system (mean chroma %.2f)", meanChroma))
}

print(String(format: "Bessie design snapshot passed: %d×%d, region %d,%d,%d,%d, luminance %.2f, rail variation σ %.2f, plate variation σ %.2f, chroma %.2f", width, height, region[0], region[1], region[2], region[3], mean, standardDeviation, plateStandardDeviation, meanChroma))
