#!/usr/bin/env swift
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Bessie design snapshot check failed: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: verify-design-snapshot.swift <window.png>")
}

let path = CommandLine.arguments[1]
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

guard width >= 1080, height >= 680 else {
    fail("expected the desktop shell to be at least 1080×680, got \(width)×\(height)")
}

// Sample an intentionally quiet stretch of the 244pt rail. Bright labels and
// borders are excluded so this measures the dark ASCII cowprint field itself.
let xRange = 12..<min(236, width)
let topStart = min(max(360, height / 2), height - 180)
let topEnd = min(height - 70, topStart + 230)
var luminances: [Double] = []
var chromaSum = 0.0
var sampled = 0

for topY in stride(from: topStart, to: topEnd, by: 2) {
    let y = height - 1 - topY
    for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: 2) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let r = Double(color.redComponent * 255)
        let g = Double(color.greenComponent * 255)
        let b = Double(color.blueComponent * 255)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard luminance < 30 else { continue }
        luminances.append(luminance)
        chromaSum += abs(r - g) + abs(g - b) + abs(b - r)
        sampled += 1
    }
}

guard sampled >= 2_000 else {
    fail("not enough dark rail pixels were present (sampled \(sampled))")
}
let mean = luminances.reduce(0, +) / Double(luminances.count)
let variance = luminances.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(luminances.count)
let standardDeviation = sqrt(variance)
let meanChroma = chromaSum / Double(sampled)

guard mean < 22 else {
    fail(String(format: "rail is not using the retained dark palette (mean luminance %.2f)", mean))
}
guard standardDeviation >= 0.75 else {
    fail(String(format: "rail has no measurable ASCII cowprint texture (dark-pixel σ %.2f)", standardDeviation))
}
guard meanChroma < 1.5 else {
    fail(String(format: "rail contains hue outside the monochrome system (mean chroma %.2f)", meanChroma))
}

print(String(format: "Bessie design snapshot passed: %d×%d, rail luminance %.2f, cowprint σ %.2f, chroma %.2f", width, height, mean, standardDeviation, meanChroma))
