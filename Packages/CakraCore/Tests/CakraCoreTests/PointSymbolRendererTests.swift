@testable import CakraCore
import CoreGraphics
import XCTest

/// Point symbols are drawn with solid strokes even when the context still has a dash pattern from a dashed line.
final class PointSymbolRendererTests: XCTestCase {
    private func centreIsInked(_ code: String, in file: OccaSymbolFile) throws -> Bool {
        let s = try XCTUnwrap(file.symbols.first { $0.code == code })
        let size = 120
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setLineDash(phase: 0, lengths: [3, 400])         // left over from a dashed line drawn before
        let k = 80.0                                          // px per mm
        PointSymbolRenderer.draw(s.pointElements ?? [], in: ctx, mmToUnits: k) {
            CGPoint(x: Double(size) / 2 + $0.x * k, y: Double(size) / 2 + $0.y * k)
        }
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // The crossing of the "x" (and the bottom of a "V") is at / near the centre.
        let probe = code.hasPrefix("112") ? (size / 2, size / 2 - Int(0.26 * k)) : (size / 2, size / 2)
        let i = ((size - 1 - probe.1) * size + probe.0) * 4
        return px[i + 3] > 0
    }

    func testCrossAndVeeAreSolidAfterADashedLine() throws {
        let isom = OccaStandardSymbols.isomFile(), spr = OccaStandardSymbols.issprFile()
        XCTAssertTrue(try centreIsInked("313.0", in: isom), "313 water feature x: arms meet in the middle")
        XCTAssertTrue(try centreIsInked("531.0", in: isom), "531 man-made feature x")
        XCTAssertTrue(try centreIsInked("419.0", in: spr), "419 vegetation feature x")
        XCTAssertTrue(try centreIsInked("112.0", in: isom), "112 pit V: the two arms meet")
    }
}
