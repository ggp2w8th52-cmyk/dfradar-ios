import Foundation

/// Z
struct V3: Decodable {
    var x: Float
    var y: Float
    var z: Float

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

 /// [x, y, z]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let x = try c.decode(Double.self)
        let y = try c.decode(Double.self)
        let z = try c.decode(Double.self)
        self.init(x: Float(x), y: Float(y), z: Float(z))
    }

    static let zero = V3(x: 0, y: 0, z: 0)

    var length: Float { (x * x + y * y + z * z).squareRoot() }
}

/// PC
/// - Returns: (sx, sy, depthMeters) <0.25m nil
///
/// yaw +Z0 +XZ UE /
/// Unity X / Y / Z forward right/up
///   let f = V3(x: sin(y) * cos(p), y: sin(p), z: cos(y) * cos(p))
///   var r = V3(x: cos(y), y: 0, z: -sin(y))          // right
/// let u = V3(x: 0, y: 1, z: 0) // up f
/// d d.x / d.y / d.z / /
func w2s(eye: V3, yaw: Float, pitch: Float, target: V3,
         hfov: Float, W: Float, H: Float) -> (Float, Float, Float)? {
    let y = yaw * .pi / 180
    let p = pitch * .pi / 180

    // forward
    let f = V3(x: cos(y) * cos(p), y: sin(y) * cos(p), z: sin(p))

 // right = forward up(0,0,1)
    var r = V3(x: -sin(y), y: cos(y), z: 0)
    let rl = sqrt(r.x * r.x + r.y * r.y)
    if rl > 1e-6 {
        r.x /= rl
        r.y /= rl
    }

 // up = right forward
    let u = V3(x: r.y * f.z - r.z * f.y,
               y: r.z * f.x - r.x * f.z,
               z: r.x * f.y - r.y * f.x)

    let d = V3(x: target.x - eye.x, y: target.y - eye.y, z: target.z - eye.z)

    let depth = d.x * f.x + d.y * f.y + d.z * f.z
    if depth <= 0.25 { return nil }

    let sx = d.x * r.x + d.y * r.y + d.z * r.z
    let sy = d.x * u.x + d.y * u.y + d.z * u.z

    let focal = (W / 2) / tan(hfov * .pi / 360)
    return (W / 2 + sx / depth * focal, H / 2 - sy / depth * focal, depth)
}
