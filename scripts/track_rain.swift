import AVFoundation
import Foundation
import CoreGraphics
import AppKit

// Dense frame extraction + blob detection, for measuring an animation off a recording.
//
//   swiftc -O scripts/track_rain.swift -o /tmp/track
//   /tmp/track <video> [fps] [excludeTopFrac] [excludeBottomFrac] > blobs.tsv
//
// Emits one TSV row per detected sprite per frame (position, bbox, area, mean colour) for
// scripts/fit_rain.py to fit. Background = the per-pixel median across all frames, so only
// transient things (the sprites) are detected. See docs/town-rain-reference-measurements.md.

let args = CommandLine.arguments
let videoPath = args[1]
let fps = Double(args.count > 2 ? args[2] : "60") ?? 60
let exTop = Double(args.count > 3 ? args[3] : "0.075") ?? 0.075
let exBot = Double(args.count > 4 ? args[4] : "0.88") ?? 0.88
let scale = 4.0  // downscale factor

let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
let duration = CMTimeGetSeconds(asset.duration)
guard let track = asset.tracks(withMediaType: .video).first else { exit(1) }
let natural = track.naturalSize
let W = Int(natural.width / scale), H = Int(natural.height / scale)

let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
gen.maximumSize = CGSize(width: W, height: H)

func pixels(_ cg: CGImage) -> ([UInt8], Int, Int) {
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buf, w, h)
}

let n = Int(duration * fps)
var frames: [(t: Double, px: [UInt8])] = []
var fw = 0, fh = 0
for i in 0..<n {
    let t = Double(i) / fps
    let time = CMTime(seconds: t, preferredTimescale: 6000)
    guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { continue }
    let (p, w, h) = pixels(cg)
    fw = w; fh = h
    frames.append((t, p))
}
FileHandle.standardError.write("frames: \(frames.count) size \(fw)x\(fh)\n".data(using: .utf8)!)

// Background plate: per-pixel median across all frames (sprites are transient).
var bg = [UInt8](repeating: 0, count: fw * fh * 4)
let count = frames.count
var scratch = [UInt8](repeating: 0, count: count)
for idx in stride(from: 0, to: fw * fh * 4, by: 1) {
    for f in 0..<count { scratch[f] = frames[f].px[idx] }
    scratch.sort()
    bg[idx] = scratch[count / 2]
}

// Blob detection per frame
struct Blob { var cx: Double; var cy: Double; var minX: Int; var maxX: Int; var minY: Int; var maxY: Int; var n: Int; var r: Int; var g: Int; var b: Int }

let THRESH = 26.0
var out: [String] = []

// Exclusion zones (status bar / dynamic island / chrome) in downscaled coords
func excluded(_ x: Int, _ y: Int) -> Bool {
    let fy = Double(y) / Double(fh)
    if fy < exTop { return true }
    if fy > exBot { return true }
    return false
}

for (fi, frame) in frames.enumerated() {
    var visited = [Bool](repeating: false, count: fw * fh)
    var blobs: [Blob] = []
    for y in 0..<fh {
        for x in 0..<fw {
            let i = y * fw + x
            if visited[i] { continue }
            if excluded(x, y) { visited[i] = true; continue }
            let o = i * 4
            let dr = Double(frame.px[o]) - Double(bg[o])
            let dg = Double(frame.px[o+1]) - Double(bg[o+1])
            let db = Double(frame.px[o+2]) - Double(bg[o+2])
            let d = (abs(dr) + abs(dg) + abs(db)) / 3.0
            if d < THRESH { visited[i] = true; continue }
            // flood fill
            var stack = [i]
            visited[i] = true
            var sx = 0.0, sy = 0.0, cnt = 0
            var mnX = x, mxX = x, mnY = y, mxY = y
            var sr = 0, sg = 0, sb = 0
            while let cur = stack.popLast() {
                let cx = cur % fw, cy = cur / fw
                sx += Double(cx); sy += Double(cy); cnt += 1
                mnX = min(mnX, cx); mxX = max(mxX, cx)
                mnY = min(mnY, cy); mxY = max(mxY, cy)
                let co = cur * 4
                sr += Int(frame.px[co]); sg += Int(frame.px[co+1]); sb += Int(frame.px[co+2])
                for (ddx, ddy) in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)] {
                    let nx = cx + ddx, ny = cy + ddy
                    if nx < 0 || ny < 0 || nx >= fw || ny >= fh { continue }
                    let ni = ny * fw + nx
                    if visited[ni] { continue }
                    if excluded(nx, ny) { visited[ni] = true; continue }
                    let no = ni * 4
                    let d2 = (abs(Double(frame.px[no]) - Double(bg[no]))
                            + abs(Double(frame.px[no+1]) - Double(bg[no+1]))
                            + abs(Double(frame.px[no+2]) - Double(bg[no+2]))) / 3.0
                    if d2 >= THRESH { visited[ni] = true; stack.append(ni) }
                }
            }
            if cnt >= 12 {
                blobs.append(Blob(cx: sx/Double(cnt), cy: sy/Double(cnt), minX: mnX, maxX: mxX, minY: mnY, maxY: mxY, n: cnt, r: sr/cnt, g: sg/cnt, b: sb/cnt))
            }
        }
    }
    for b in blobs {
        // report in FULL-RES pixel coords and normalized coords
        let fullX = b.cx * scale, fullY = b.cy * scale
        let wpx = Double(b.maxX - b.minX + 1) * scale
        let hpx = Double(b.maxY - b.minY + 1) * scale
        out.append(String(format: "%d\t%.4f\t%.1f\t%.1f\t%.1f\t%.1f\t%d\t%.4f\t%.4f\t#%02X%02X%02X",
                          fi, frame.t, fullX, fullY, wpx, hpx, b.n,
                          fullX / (Double(fw) * scale), fullY / (Double(fh) * scale),
                          b.r, b.g, b.b))
    }
}
print("frame\ttime\tx\ty\tw\th\tpix\tnx\tny\tcolor")
print(out.joined(separator: "\n"))
