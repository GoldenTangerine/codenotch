/**
 @name: 动态机器人 · BotMarkData
 @Descripttion: 移植 Pulse 机器人动作与几何实现并适配本项目。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-18 10:13:39
 @LastEditTime: 2026-09-18 10:13:39
 @FilePath: Sources/Features/BotMark/BotMarkData.swift
 */
// Adapted from Pulse (Apache-2.0); see Resources/BotMark-NOTICE.txt.
import CoreGraphics
import Foundation
import SwiftUI

/// The upstream geometry and state tables, loaded from `bot-data.json`.
///
/// The JSON is produced by `Scripts/extract-bot-data.py` out of the upstream
/// `original-data.js` and `catalog.js`: 18 body shapes (a 96-point ring, the
/// original Bézier outline, eye-placement spans), 25 two-eye expressions of
/// 48 points each, and the per-state expression pools and cadences for all
/// 39 states. Nothing here is computed — it is the same numbers the web
/// component draws from.
struct BotMarkLibrary {
    let headCentre: Double
    let eyeHalf: Double
    let circleRing: [CGPoint]
    /// The confetti star, a unit outline scaled per particle.
    let starPath: CGPath
    let starGold: Color
    let shapes: [String: BotMarkShape]
    let shapeOrder: [String]
    let shapeLabels: [String: BotMarkLabel]
    /// 25 expressions, each a pair of eye rings.
    let expressions: [[[CGPoint]]]
    let eyeReach: Double
    let states: [BotMarkStateInfo]

    /// Loaded once and never written to afterwards; the drawing code that
    /// reads it all runs on the main actor.
    static let available: BotMarkLibrary? = {
        guard let url = Bundle.main.url(forResource: "bot-data", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? BotMarkLibrary(decoding: data)
    }()

    // 只有资源校验成功后才创建引擎；展示入口在失败时保留供应商图标。
    static var shared: BotMarkLibrary { available! }

    func shape(_ identifier: String) -> BotMarkShape {
        shapes[identifier] ?? shapes["blob"]!
    }

    func state(_ identifier: String) -> BotMarkStateInfo {
        states.first { $0.id == identifier } ?? states[0]
    }
}

struct BotMarkLabel: Decodable {
    let en: String
    let zh: String
}

/// One body shape. `ring` is the 96-point outline every shape shares, which
/// is what makes shape-to-shape blending a point-by-point interpolation.
struct BotMarkShape {
    let ring: [CGPoint]
    /// The original outline. Used whenever the shape is neither turning nor
    /// mid-blend, because it is the real curve rather than a 96-point
    /// approximation of it.
    let path: CGPath
    let face: BotMarkFace
    let tiltScale: Double
    let beltRadius: Double
    let radius: Double
    let top: Double
    let bottom: Double
    let sides: Int
    /// Sphere list for the three shapes whose turn profile is solved in 3D.
    let solid: [[Double]]?
    /// 160 pre-sampled `(left, right)` pairs down the shape, so the eyes can
    /// be kept inside the silhouette without re-scanning the ring.
    let spanSamples: [(Double, Double)]?
}

/// Where the face sits on a given body, and how much of it there is.
struct BotMarkFace {
    var x: Double
    var y: Double
    var sx: Double
    var sy: Double
    var eye: Double

    static func blend(_ from: BotMarkFace, _ to: BotMarkFace, _ amount: Double) -> BotMarkFace {
        BotMarkFace(x: BotMath.mix(from.x, to.x, amount),
                       y: BotMath.mix(from.y, to.y, amount),
                       sx: BotMath.mix(from.sx, to.sx, amount),
                       sy: BotMath.mix(from.sy, to.sy, amount),
                       eye: BotMath.mix(from.eye, to.eye, amount))
    }
}

struct BotMarkStateInfo {
    let id: String
    let en: String
    let zh: String
    /// The one-shot effect this state morphs into, if any.
    let morph: String?
    /// Milliseconds between blinks. Nil means the state does not blink.
    let blinkCadence: (Double, Double)?
    /// Milliseconds between expression changes.
    let expressionCadence: (Double, Double)
    /// Which of the 25 expressions this state draws from.
    let expressionPool: [Int]
}

// MARK: - Decoding

private struct RawFile: Decodable {
    let headC: Double
    let eyeHalf: Double
    let circleRing: [[Double]]
    let starPath: [RawSegment]
    let starGold: String
    let shapes: [String: RawShape]
    let shapeOrder: [String]
    let shapeLabels: [String: BotMarkLabel]
    let expressions: [[[[Double]]]]
    let states: [RawState]
}

private struct RawShape: Decodable {
    let ring: [[Double]]
    let path: [RawSegment]
    let face: RawFace
    let tiltScale: Double
    let beltRadius: Double
    let radius: Double
    let top: Double
    let bottom: Double
    let sides: Int
    let solid: [[Double]]?
    let spanSamples: [[Double]]?
}

private struct RawFace: Decodable {
    let x: Double
    let y: Double
    let sx: Double
    let sy: Double
    let eye: Double
}

private struct RawSegment: Decodable {
    let op: String
    let values: [Double]
}

private struct RawState: Decodable {
    let id: String
    let en: String
    let zh: String
    let morph: String?
    let blinkCadence: [Double]?
    let expressionCadence: [Double]
    let expressionPool: [Int]
}

extension BotMarkLibrary {
    init(decoding data: Data) throws {
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        func points(_ values: [[Double]], count: Int? = nil) -> Bool {
            (count == nil || values.count == count) && !values.isEmpty
                && values.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isFinite) }
        }
        func segments(_ values: [RawSegment]) -> Bool {
            !values.isEmpty && values.allSatisfy {
                let counts = ["M": 2, "L": 2, "C": 6, "Q": 4, "Z": 0]
                return counts[$0.op] == $0.values.count && $0.values.allSatisfy(\.isFinite)
            }
        }
        guard raw.headC.isFinite, raw.eyeHalf.isFinite,
              points(raw.circleRing, count: 96), segments(raw.starPath),
              BotMarkBody.allCases.allSatisfy({ raw.shapes[$0.rawValue] != nil }),
              !raw.expressions.isEmpty,
              raw.expressions.allSatisfy({ $0.count == 2 && $0.allSatisfy { points($0, count: 48) } }),
              !raw.states.isEmpty,
              raw.states.allSatisfy({ state in
                  state.expressionCadence.count == 2 && state.expressionCadence.allSatisfy(\.isFinite)
                      && !state.expressionPool.isEmpty
                      && state.expressionPool.allSatisfy { raw.expressions.indices.contains($0) }
              }),
              raw.shapes.values.allSatisfy({ shape in
                  points(shape.ring, count: 96) && segments(shape.path)
                      && (shape.spanSamples.map { points($0) } ?? true)
                      && (shape.solid.map { $0.allSatisfy { $0.count == 4 && $0.allSatisfy(\.isFinite) } } ?? true)
              }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid robot geometry"))
        }
        headCentre = raw.headC
        eyeHalf = raw.eyeHalf
        circleRing = raw.circleRing.map(BotMarkLibrary.point)
        starPath = BotMarkLibrary.path(raw.starPath)
        starGold = BotMarkPalette.rgb(UInt32(raw.starGold.dropFirst(), radix: 16) ?? 0xf4c34e)
        shapeOrder = raw.shapeOrder
        shapeLabels = raw.shapeLabels
        expressions = raw.expressions.map { $0.map { $0.map(BotMarkLibrary.point) } }
        eyeReach = expressions.map {
            abs((BotMarkGeometry.centroid($0[0]).x + BotMarkGeometry.centroid($0[1]).x) / 2 - raw.headC)
        }.max() ?? 0
        states = raw.states.map { state in
            BotMarkStateInfo(
                id: state.id, en: state.en, zh: state.zh, morph: state.morph,
                blinkCadence: state.blinkCadence.flatMap {
                    $0.count == 2 ? (min($0[0], $0[1]), max($0[0], $0[1])) : nil
                },
                expressionCadence: (state.expressionCadence[0], state.expressionCadence[1]),
                expressionPool: state.expressionPool)
        }
        shapes = raw.shapes.mapValues { shape in
            BotMarkShape(
                ring: shape.ring.map(BotMarkLibrary.point),
                path: BotMarkLibrary.path(shape.path),
                face: BotMarkFace(x: shape.face.x, y: shape.face.y,
                                     sx: shape.face.sx, sy: shape.face.sy, eye: shape.face.eye),
                tiltScale: shape.tiltScale,
                beltRadius: shape.beltRadius,
                radius: shape.radius,
                top: shape.top,
                bottom: shape.bottom,
                sides: shape.sides,
                solid: shape.solid,
                spanSamples: shape.spanSamples.map { samples in
                    samples.map { ($0[0], $0[1]) }
                })
        }
    }

    private static func point(_ pair: [Double]) -> CGPoint {
        CGPoint(x: pair[0], y: pair[1])
    }

    /// Replays the pre-parsed outline. The extractor has already reduced the
    /// upstream path to absolute M/L/C/Q/Z segments.
    private static func path(_ segments: [RawSegment]) -> CGPath {
        let path = CGMutablePath()
        for segment in segments {
            let values = segment.values
            switch segment.op {
            case "M":
                path.move(to: CGPoint(x: values[0], y: values[1]))
            case "L":
                path.addLine(to: CGPoint(x: values[0], y: values[1]))
            case "C":
                path.addCurve(to: CGPoint(x: values[4], y: values[5]),
                              control1: CGPoint(x: values[0], y: values[1]),
                              control2: CGPoint(x: values[2], y: values[3]))
            case "Q":
                path.addQuadCurve(to: CGPoint(x: values[2], y: values[3]),
                                  control: CGPoint(x: values[0], y: values[1]))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}
