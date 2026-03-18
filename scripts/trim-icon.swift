import AppKit
import Foundation

private let alphaThreshold: CGFloat = 0.015
private let paddingRatio: CGFloat = 0.08

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: trim-icon.swift <input.png> <output.png>\n", stderr)
    exit(1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let image = NSImage(contentsOf: inputURL),
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData)
else {
    fputs("Failed to load image at \(inputURL.path)\n", stderr)
    exit(1)
}

let width = bitmap.pixelsWide
let height = bitmap.pixelsHigh

var minX = width
var minY = height
var maxX = -1
var maxY = -1

for y in 0..<height {
    for x in 0..<width {
        let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0

        if alpha > alphaThreshold {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

guard maxX >= minX, maxY >= minY else {
    try? FileManager.default.copyItem(at: inputURL, to: outputURL)
    exit(0)
}

let contentWidth = CGFloat(maxX - minX + 1)
let contentHeight = CGFloat(maxY - minY + 1)
let paddedSide = max(contentWidth, contentHeight) * (1 + paddingRatio * 2)
let cropSide = min(ceil(paddedSide), CGFloat(min(width, height)))
let centerX = CGFloat(minX + maxX) / 2
let centerY = CGFloat(minY + maxY) / 2

var cropX = floor(centerX - cropSide / 2)
var cropY = floor(centerY - cropSide / 2)

cropX = max(0, min(cropX, CGFloat(width) - cropSide))
cropY = max(0, min(cropY, CGFloat(height) - cropSide))

let cropRect = NSRect(x: cropX, y: cropY, width: cropSide, height: cropSide)
let croppedImage = NSImage(size: cropRect.size)

croppedImage.lockFocus()
image.draw(
    in: NSRect(origin: .zero, size: cropRect.size),
    from: cropRect,
    operation: .copy,
    fraction: 1
)
croppedImage.unlockFocus()

guard
    let croppedTiff = croppedImage.tiffRepresentation,
    let croppedBitmap = NSBitmapImageRep(data: croppedTiff),
    let pngData = croppedBitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to encode cropped image.\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
