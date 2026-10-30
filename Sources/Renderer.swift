import UIKit

/// Standard humanoid skeleton.
/// The network protocol carries no joint data, so the figure is drawn procedurally:
/// fixed local joint offsets scaled by distance, anchored at the projected point.
enum Skeleton {
    /// local offsets in meters: (+right, +up)
    static let joints: [(Float, Float)] = [
        (0.00, 1.70),   // 0 head
        (0.00, 1.45),   // 1 neck
        (0.20, 1.45),   // 2 left shoulder
        (0.20, 1.10),   // 3 left elbow
        (0.22, 0.80),   // 4 left wrist
        (0.24, 0.55),   // 5 left hand
        (-0.20, 1.45),  // 6 right shoulder
        (-0.20, 1.10),  // 7 right elbow
        (-0.22, 0.80),  // 8 right wrist
        (-0.24, 0.55),  // 9 right hand
        (0.11, 0.90),   // 10 left hip
        (0.12, 0.45),   // 11 left knee
        (0.13, 0.05),   // 12 left ankle
        (-0.11, 0.90),  // 13 right hip
        (-0.12, 0.45),  // 14 right knee
        (-0.13, 0.05),  // 15 right ankle
        (0.00, 1.05)    // 16 hip center
    ]

    /// 16 bone segments. The right arm chain is 1-6/6-7/7-8 (neck/right side);
    /// chaining 1-5/5-6/6-7 would cross the body because joint 5 is the LEFT hand.
    static let bones: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4),
        (1, 6), (6, 7), (7, 8),
        (1, 16), (16, 10), (10, 11), (11, 12),
        (16, 13), (13, 14), (14, 15),
        (2, 13), (10, 13)
    ]
}

/// Render one 480x270 perspective frame into an opaque image.
func render(_ msg: Msg, size: CGSize = CGSize(width: 480, height: 270)) -> UIImage {
    let fmt = UIGraphicsImageRendererFormat()
    fmt.opaque = true
    fmt.scale = 1

    return UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
        // UIGraphicsImageRendererContext.cgContext is NOT optional
        let c = rc.cgContext
        let W = Float(size.width)
        let H = Float(size.height)

        c.setFillColor(UIColor.black.cgColor)
        c.fill(CGRect(origin: .zero, size: size))

        // crosshair
        c.setStrokeColor(UIColor(white: 1, alpha: 0.30).cgColor)
        c.setLineWidth(1)
        let cx = size.width / 2
        let cy = size.height / 2
        c.move(to: CGPoint(x: cx - 9, y: cy)); c.addLine(to: CGPoint(x: cx + 9, y: cy))
        c.move(to: CGPoint(x: cx, y: cy - 9)); c.addLine(to: CGPoint(x: cx, y: cy + 9))
        c.strokePath()

        let eye = msg.eye
        // 视锥判断用的前向/右向（与 w2s 同一套约定）
        let yawRad = msg.yaw * .pi / 180
        let fx = cos(yawRad), fy = sin(yawRad)
        let rx = -sin(yawRad), ry = cos(yawRad)
        let halfFov = msg.hfov / 2

        for e in msg.ents {
            // 相对自己的方向（用于视锥判断与边缘箭头）
            let dx = e.pos.x - eye.x
            let dy = e.pos.y - eye.y
            let forward = dx * fx + dy * fy
            let right = dx * rx + dy * ry
            let bearing = atan2(right, forward) * 180 / .pi

            guard let hit = w2s(eye: eye, yaw: msg.yaw, pitch: msg.pitch,
                                target: e.pos, hfov: msg.hfov, W: W, H: H) else { continue }

            let sx = hit.0
            let sy = hit.1
            let dist = hit.2

            let hp = e.hp
            let behind = e.visible < 0.5

            let color: UIColor
            if behind {
                color = .systemRed
            } else if hp > 60 {
                color = .systemGreen
            } else if hp > 30 {
                color = .systemYellow
            } else {
                color = .systemOrange
            }

            // 视锥外：只在屏幕边缘画箭头 + 距离，不画骨架（避免画到画布外白算）
            if abs(bearing) > halfFov {
                let isLeft = bearing < 0
                let ax: CGFloat = isLeft ? 14 : size.width - 14
                let ay: CGFloat = size.height / 2
                c.setFillColor(color.withAlphaComponent(0.9).cgColor)
                c.beginPath()
                if isLeft {
                    c.move(to: CGPoint(x: ax - 8, y: ay))
                    c.addLine(to: CGPoint(x: ax + 6, y: ay - 9))
                    c.addLine(to: CGPoint(x: ax + 6, y: ay + 9))
                } else {
                    c.move(to: CGPoint(x: ax + 8, y: ay))
                    c.addLine(to: CGPoint(x: ax - 6, y: ay - 9))
                    c.addLine(to: CGPoint(x: ax - 6, y: ay + 9))
                }
                c.closePath()
                c.fillPath()
                let txt = String(format: "%.0f\u{00B0} %.0fm", bearing, dist)
                let tx: CGFloat = isLeft ? ax + 4 : ax - 62
                (txt as NSString).draw(at: CGPoint(x: tx, y: ay + 11),
                    withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 9, weight: .bold),
                                     .foregroundColor: color])
                continue
            }

            // a 1.7 m body spans H*0.55 pixels at 1 m
            let scale = H * 0.55 / max(1, dist)

            var pts: [CGPoint] = []
            pts.reserveCapacity(Skeleton.joints.count)
            for (rx, ry) in Skeleton.joints {
                pts.append(CGPoint(x: CGFloat(sx + rx * scale),
                                   y: CGFloat(sy - ry * scale)))
            }

            c.setLineWidth(behind ? 1.2 : 2.0)
            c.setStrokeColor(color.withAlphaComponent(behind ? 0.55 : 0.95).cgColor)
            c.setLineDash(phase: 0, lengths: behind ? [4, 4] : [])
            for (a, b) in Skeleton.bones where a < pts.count && b < pts.count {
                c.move(to: pts[a])
                c.addLine(to: pts[b])
            }
            c.strokePath()
            c.setLineDash(phase: 0, lengths: [])

            // health bar above the head
            let barW = CGFloat(0.6 * scale)
            let barX = CGFloat(sx) - barW / 2
            let barY = pts[0].y - 6
            c.setFillColor(UIColor(white: 0, alpha: 0.65).cgColor)
            c.fill(CGRect(x: barX, y: barY, width: barW, height: 4))
            if hp >= 0 {
                let ratio = CGFloat(min(100, max(0, hp)) / 100)
                c.setFillColor(color.cgColor)
                c.fill(CGRect(x: barX, y: barY, width: barW * ratio, height: 4))
            }

            // distance label; \u{5899}\u{540E} == "behind cover" in Chinese
            let label = behind
                ? String(format: "\u{5899}\u{540E} %.0fm", dist)
                : String(format: "%.0fm", dist)
            (label as NSString).draw(
                at: CGPoint(x: barX, y: barY - 13),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: color
                ])
        }
    }
}
