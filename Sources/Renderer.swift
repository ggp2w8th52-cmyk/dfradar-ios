import UIKit

/// Standard humanoid skeleton. The protocol carries no joint data, so the figure is
/// drawn procedurally: fixed local joint offsets scaled by distance.
enum Skeleton {
    /// local offsets in meters: (+right, +up)
    static let joints: [(Float, Float)] = [
        (0.00, 1.70), (0.00, 1.45), (0.20, 1.45), (0.20, 1.10), (0.22, 0.80), (0.24, 0.55),
        (-0.20, 1.45), (-0.20, 1.10), (-0.22, 0.80), (-0.24, 0.55),
        (0.11, 0.90), (0.12, 0.45), (0.13, 0.05),
        (-0.11, 0.90), (-0.12, 0.45), (-0.13, 0.05),
        (0.00, 1.05)
    ]

    static let bones: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4),
        (1, 6), (6, 7), (7, 8),
        (1, 16), (16, 10), (10, 11), (11, 12),
        (16, 13), (13, 14), (14, 15),
        (2, 13), (10, 13)
    ]
}

private func colorFor(hp: Float, behind: Bool) -> UIColor {
    if behind { return .systemRed }
    if hp > 60 { return .systemGreen }
    if hp > 30 { return .systemYellow }
    return .systemOrange
}

/// Render one frame: 左侧 360° 环视雷达 + 右侧 FOV 投影 + 底部最近目标列表（480x270）
func render(_ msg: Msg, size: CGSize = CGSize(width: 480, height: 270)) -> UIImage {
    let fmt = UIGraphicsImageRendererFormat()
    fmt.opaque = true
    fmt.scale = 1

    return UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
        let c = rc.cgContext
        let H = Float(size.height)
        let W = Float(size.width)

        c.setFillColor(UIColor.black.cgColor)
        c.fill(CGRect(origin: .zero, size: size))

        let eye = msg.eye
        let yawRad = msg.yaw * .pi / 180
        let fx = cos(yawRad), fy = sin(yawRad)
        let rx = -sin(yawRad), ry = cos(yawRad)
        let halfFov = msg.hfov / 2

        // ---------- 预计算：每个实体的相对量 ----------
        struct Item {
            var id: Float
            var dist: Float
            var bearing: Float      // 度，右正左负
            var forward: Float
            var hp: Float
            var behind: Bool
            var name: String
            var pos: V3
        }
        var items: [Item] = []
        items.reserveCapacity(msg.ents.count)
        for (i, e) in msg.ents.enumerated() {
            let dx = e.pos.x - eye.x
            let dy = e.pos.y - eye.y
            let fwd = dx * fx + dy * fy
            let rgt = dx * rx + dy * ry
            let d = (dx * dx + dy * dy + (e.pos.z - eye.z) * (e.pos.z - eye.z)).squareRoot()
            var nm = ""
            if let names = msg.names, i < names.count { nm = names[i] }
            items.append(Item(id: Float(e.id), dist: d, bearing: atan2(rgt, fwd) * 180 / .pi,
                              forward: fwd, hp: e.hp, behind: e.visible < 0.5,
                              name: nm, pos: e.pos))
        }

        // ---------- 左：360° 环视雷达 ----------
        let radarW: CGFloat = 200
        let C = CGPoint(x: radarW / 2, y: size.height / 2)
        let R = radarW / 2 - 12
        let dMax: Float = 300

        func radarRadius(_ d: Float) -> CGFloat {
            let r = log(1 + Double(d) / 8) / log(1 + Double(dMax) / 8)
            return R * CGFloat(min(1, max(0, r)))
        }

        // 量程环
        for ring in [50.0, 100.0, 200.0] {
            let rr = radarRadius(Float(ring))
            c.setStrokeColor(UIColor(white: 1, alpha: 0.13).cgColor)
            c.setLineWidth(1)
            c.strokeEllipse(in: CGRect(x: C.x - rr, y: C.y - rr, width: rr * 2, height: rr * 2))
            ("\(Int(ring))" as NSString).draw(
                at: CGPoint(x: C.x + 2, y: C.y - rr - 9),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 7, weight: .regular),
                                 .foregroundColor: UIColor(white: 1, alpha: 0.35)])
        }
        // 十字线
        c.setStrokeColor(UIColor(white: 1, alpha: 0.10).cgColor)
        c.move(to: CGPoint(x: C.x - R, y: C.y)); c.addLine(to: CGPoint(x: C.x + R, y: C.y))
        c.move(to: CGPoint(x: C.x, y: C.y - R)); c.addLine(to: CGPoint(x: C.x, y: C.y + R))
        c.strokePath()

        // 本机 + 朝向（正上方 = 准星方向）
        c.setFillColor(UIColor.white.cgColor)
        c.fillEllipse(in: CGRect(x: C.x - 2.5, y: C.y - 2.5, width: 5, height: 5))
        c.setStrokeColor(UIColor.systemBlue.cgColor)
        c.setLineWidth(1.5)
        c.move(to: C); c.addLine(to: CGPoint(x: C.x, y: C.y - R * 0.9)); c.strokePath()

        // 雷达上的点
        for it in items {
            let rr = radarRadius(it.dist)
            let ang = CGFloat(it.bearing) * .pi / 180 - .pi / 2
            let p = CGPoint(x: C.x + rr * cos(ang), y: C.y + rr * sin(ang))
            let col = colorFor(hp: it.hp, behind: it.behind)
            let dot: CGFloat = it.dist < 60 ? 4.5 : 3.0
            c.setFillColor(col.withAlphaComponent(0.95).cgColor)
            c.fillEllipse(in: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot))
        }

        // 分隔线
        c.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
        c.setLineWidth(1)
        c.move(to: CGPoint(x: radarW, y: 4)); c.addLine(to: CGPoint(x: radarW, y: size.height - 4))
        c.strokePath()

        // ---------- 右：FOV 投影 ----------
        let projX = radarW + 4
        let projW = size.width - projX
        c.setStrokeColor(UIColor(white: 1, alpha: 0.25).cgColor)
        let pcx = projX + projW / 2
        let pcy = size.height / 2
        c.move(to: CGPoint(x: pcx - 7, y: pcy)); c.addLine(to: CGPoint(x: pcx + 7, y: pcy))
        c.move(to: CGPoint(x: pcx, y: pcy - 7)); c.addLine(to: CGPoint(x: pcx, y: pcy + 7))
        c.strokePath()

        for it in items {
            guard it.forward > 0.3 else { continue }
            if abs(it.bearing) > halfFov {
                // 视锥外：面板边缘箭头
                let isLeft = it.bearing < 0
                let ax = isLeft ? projX + 6 : size.width - 8
                let ay = pcy
                let col = colorFor(hp: it.hp, behind: it.behind)
                c.setFillColor(col.withAlphaComponent(0.9).cgColor)
                c.beginPath()
                if isLeft {
                    c.move(to: CGPoint(x: ax - 5, y: ay))
                    c.addLine(to: CGPoint(x: ax + 4, y: ay - 6))
                    c.addLine(to: CGPoint(x: ax + 4, y: ay + 6))
                } else {
                    c.move(to: CGPoint(x: ax + 5, y: ay))
                    c.addLine(to: CGPoint(x: ax - 4, y: ay - 6))
                    c.addLine(to: CGPoint(x: ax - 4, y: ay + 6))
                }
                c.closePath(); c.fillPath()
                continue
            }

            guard let hit = w2s(eye: eye, yaw: msg.yaw, pitch: msg.pitch,
                                target: it.pos, hfov: msg.hfov,
                                W: Float(projW), H: H) else { continue }
            let sx = hit.0 + Float(projX)
            let sy = hit.1
            let depth = hit.2

            let col = colorFor(hp: it.hp, behind: it.behind)
            // 尺寸下限 10px，避免远距离目标消失
            let scale = max(5.9, Float(H) * 0.55 / max(1, depth))

            var pts: [CGPoint] = []
            pts.reserveCapacity(Skeleton.joints.count)
            for (jx, jy) in Skeleton.joints {
                pts.append(CGPoint(x: CGFloat(sx + jx * scale), y: CGFloat(sy - jy * scale)))
            }

            c.setLineWidth(it.behind ? 1.2 : 1.8)
            c.setStrokeColor(col.withAlphaComponent(it.behind ? 0.55 : 0.95).cgColor)
            c.setLineDash(phase: 0, lengths: it.behind ? [4, 4] : [])
            for (a, b) in Skeleton.bones where a < pts.count && b < pts.count {
                c.move(to: pts[a]); c.addLine(to: pts[b])
            }
            c.strokePath()
            c.setLineDash(phase: 0, lengths: [])

            // 血条
            let barW = CGFloat(max(14, Float(0.6 * scale)))
            let barX = CGFloat(sx) - barW / 2
            let barY = pts[0].y - 6
            c.setFillColor(UIColor(white: 0, alpha: 0.6).cgColor)
            c.fill(CGRect(x: barX, y: barY, width: barW, height: 3))
            if it.hp >= 0 {
                c.setFillColor(col.cgColor)
                c.fill(CGRect(x: barX, y: barY, width: barW * CGFloat(min(100, max(0, it.hp)) / 100), height: 3))
            }
            let label = it.behind
                ? String(format: "\u{5899}\u{540E} %.0fm", depth)
                : String(format: "%.0fm", depth)
            (label as NSString).draw(at: CGPoint(x: barX, y: barY - 11),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 9, weight: .bold),
                                 .foregroundColor: col])
        }

        // ---------- 底部：最近 3 个目标 ----------
        let nearest = items.sorted { $0.dist < $1.dist }.prefix(3)
        var y = size.height - CGFloat(nearest.count) * 11 - 4
        for it in nearest {
            let col = colorFor(hp: it.hp, behind: it.behind)
            let name = it.name.isEmpty ? String(format: "#%.0f", it.id) : it.name
            let line = String(format: "%@ %+.0f\u{00B0} %.0fm hp%.0f%@",
                              String(name.prefix(10)), it.bearing, it.dist, it.hp,
                              it.behind ? " \u{5899}\u{540E}" : "")
            (line as NSString).draw(at: CGPoint(x: 4, y: y),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                                 .foregroundColor: col])
            y += 11
        }
    }
}
