import Foundation

// MARK: -

/// [id, x, y, z, hp, visible]
struct Ent: Decodable {
    var id: Int
    var pos: V3
 /// 0~100-1
    var hp: Float
 /// 1 / 0
    var visible: Float

    init(id: Int, pos: V3, hp: Float = -1, visible: Float = 0) {
        self.id = id
        self.pos = pos
        self.hp = hp
        self.visible = visible
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let idV = try c.decode(Double.self)
        let x = try c.decode(Double.self)
        let y = try c.decode(Double.self)
        let z = try c.decode(Double.self)
        let hpV = try c.decodeIfPresent(Double.self) ?? -1
        let visV = try c.decodeIfPresent(Double.self) ?? 0
        self.id = Int(idV)
        self.pos = V3(x: Float(x), y: Float(y), z: Float(z))
        self.hp = Float(hpV)
        self.visible = Float(visV)
    }
}

/// PC
/// {"self":[x,y,z],"yaw":deg,"pitch":deg,"hfov":deg,"ents":[[id,x,y,z,hp,visible],...]}
struct Msg: Decodable {
    var selfPos: V3
    var yaw: Float
    var pitch: Float
    var hfov: Float
    var ents: [Ent]

    enum CodingKeys: String, CodingKey {
 case selfPos = "self" // self Swift selfPos
        case yaw
        case pitch
        case hfov
        case ents
    }

    init(selfPos: V3, yaw: Float, pitch: Float, hfov: Float, ents: [Ent]) {
        self.selfPos = selfPos
        self.yaw = yaw
        self.pitch = pitch
        self.hfov = hfov
        self.ents = ents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.selfPos = try c.decode(V3.self, forKey: .selfPos)
        self.yaw = try c.decodeIfPresent(Float.self, forKey: .yaw) ?? 0
        self.pitch = try c.decodeIfPresent(Float.self, forKey: .pitch) ?? 0
        self.hfov = try c.decodeIfPresent(Float.self, forKey: .hfov) ?? 90
        self.ents = try c.decodeIfPresent([Ent].self, forKey: .ents) ?? []
    }

 /// PC self 1.6
    static let eyeHeightOffset: Float = 0

    var eye: V3 {
        V3(x: selfPos.x, y: selfPos.y, z: selfPos.z + Msg.eyeHeightOffset)
    }
}

// MARK: - UDP BSD socket47810

final class Net {
    private var fd: Int32 = -1
    private var port: UInt16 = 47810
    private let queue = DispatchQueue(label: "dfradar.net", qos: .userInteractive)

    private(set) var lastRecv: Date?
    private(set) var received: Int = 0
    private(set) var dropped: Int = 0
    private(set) var isBound: Bool = false

 ///
    var onMsg: ((Msg) -> Void)?

 /// 3
    var isStale: Bool {
        guard let t = lastRecv else { return true }
        return Date().timeIntervalSince(t) > 3.0
    }

    var secondsSinceLast: Double? {
        guard let t = lastRecv else { return nil }
        return Date().timeIntervalSince(t)
    }

    func start(port p: UInt16 = 47810) {
        stop()
        port = p

        let s = socket(AF_INET, SOCK_DGRAM, 0)
        guard s >= 0 else { return }
        fd = s

        var reuse: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var bcast: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_BROADCAST, &bcast, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let rc: Int32 = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                bind(s, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0 else {
            close(s)
            fd = -1
            isBound = false
            return
        }
        isBound = true

 // iOS 14+
 //
        localNetworkProbe()

        let decoder = JSONDecoder()
        queue.async { [weak self] in
            guard let self = self else { return }
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = recv(s, &buf, buf.count, 0)
                if n <= 0 {
                    if errno == EINTR { continue }
                    break
                }
                guard let msg = try? decoder.decode(Msg.self, from: Data(buf[0..<n])) else {
                    self.dropped += 1
                    continue
                }
                self.lastRecv = Date()
                self.received += 1
                self.onMsg?(msg)
            }
        }
    }

    func stop() {
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        isBound = false
    }

 /// 255.255.255.255:port PC
    private func localNetworkProbe() {
        guard fd >= 0 else { return }
        var to = sockaddr_in()
        to.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        to.sin_family = sa_family_t(AF_INET)
        to.sin_port = port.bigEndian
        to.sin_addr.s_addr = 0xffff_ffff   // INADDR_BROADCAST

        let payload = [UInt8]("{\"probe\":1}".utf8)
        _ = payload.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &to) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    sendto(fd, raw.baseAddress, raw.count, 0, sp,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
