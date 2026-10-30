import Foundation

/// Synthetic world for end-to-end checks without the PC side running.
enum Mock {
    static func make(_ t: Double) -> Msg {
        var ents: [Ent] = []
        for i in 0..<5 {
            let a = t * 0.6 + Double(i) * 1.3
            let r = 12.0 + Double(i) * 9.0
            let hp = Float(max(0, 100 - i * 18))
            // entity #1 is permanently behind cover -> red dashed skeleton
            let visible: Float = (i == 1) ? 0 : 1
            ents.append(Ent(id: i,
                            pos: V3(x: Float(cos(a) * r),
                                    y: Float(sin(a) * r),
                                    z: 0),
                            hp: hp,
                            visible: visible))
        }
        return Msg(selfPos: V3(x: 0, y: 0, z: 0),
                   yaw: Float((t * 9.0).truncatingRemainder(dividingBy: 360)),
                   pitch: 0,
                   hfov: 70,
                   ents: ents)
    }
}
