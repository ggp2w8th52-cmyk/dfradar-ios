import Foundation
import Network

/// iOS 14+ 的「本地网络」授权只能由 Bonjour 浏览 / 本地端口监听 / 访问局域网地址触发。
/// 单纯 bind 一个 UDP 端口、或往 255.255.255.255 广播，在 iOS 26 上不触发弹窗。
final class LocalNetPrompt {

    private var browser: NWBrowser?
    private var listener: NWListener?

    /// 给界面显示的状态文本
    private(set) var stateText: String = "localNet: idle"
    var onState: ((String) -> Void)?

    func fire() {
        startBrowser()
        startListener()
        sendSubnetBroadcast()
    }

    /// 往「本网段广播地址」发一个 UDP 包 —— iOS 14+ 上最可靠的本地网络触发方式
    private func sendSubnetBroadcast() {
        guard let (ip, mask) = LocalNetPrompt.ipv4AndMask() else {
            report("localNet: no ipv4 iface")
            return
        }
        let bcast = LocalNetPrompt.broadcast(ip: ip, mask: mask)
        let s = socket(AF_INET, SOCK_DGRAM, 0)
        guard s >= 0 else { return }
        defer { close(s) }
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var to = sockaddr_in()
        to.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        to.sin_family = sa_family_t(AF_INET)
        to.sin_port = 47811
        inet_pton(AF_INET, bcast, &to.sin_addr)

        let payload = [UInt8]("{\"probe\":\"dfradar\"}".utf8)
        _ = payload.withUnsafeBytes { raw in
            withUnsafePointer(to: &to) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    sendto(s, raw.baseAddress, raw.count, 0, sp,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        report("localNet: probe -> \(bcast)  self \(ip)/\(mask)")
    }

    static func ipv4AndMask() -> (String, String)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var best: (String, String)?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            if let sa = cur.pointee.ifa_addr,
               sa.pointee.sa_family == sa_family_t(AF_INET),
               (flags & IFF_UP) != 0,
               (flags & IFF_LOOPBACK) == 0,
               let nm = cur.pointee.ifa_netmask {
                let a = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                let m = UnsafeRawPointer(nm).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var ab = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var mb = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var aa = a, mm = m
                if inet_ntop(AF_INET, &aa, &ab, socklen_t(INET_ADDRSTRLEN)) != nil,
                   inet_ntop(AF_INET, &mm, &mb, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: ab)
                    if best == nil || ip.hasPrefix("192.168.") || ip.hasPrefix("10.") {
                        best = (ip, String(cString: mb))
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return best
    }

    static func broadcast(ip: String, mask: String) -> String {
        func toInt(_ s: String) -> UInt32 {
            var r: UInt32 = 0
            for part in s.split(separator: ".") {
                r = (r << 8) | (UInt32(part) ?? 0)
            }
            return r
        }
        let b = toInt(ip) | ~toInt(mask)
        return "\((b >> 24) & 0xFF).\((b >> 16) & 0xFF).\((b >> 8) & 0xFF).\(b & 0xFF)"
    }

    private func report(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.stateText = text
            self?.onState?(text)
        }
    }

    private func startBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_dfradar._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            let text: String
            switch state {
            case .ready:
                text = "localNet: ready (granted)"
            case .waiting(let err):
                text = "localNet: waiting \(err.localizedDescription)"
            case .failed(let err):
                text = "localNet: failed \(err.localizedDescription)"
            case .cancelled:
                text = "localNet: cancelled"
            default:
                text = "localNet: \(state)"
            }
            DispatchQueue.main.async {
                self?.stateText = text
                self?.onState?(text)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// 起一个本地 TCP 监听（同时也会触发系统弹窗）
    private func startListener() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let listener = try NWListener(using: params, on: 47899)
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    DispatchQueue.main.async {
                        let merged = (self?.stateText ?? "") + " | listener ready"
                        self?.stateText = merged
                        self?.onState?(merged)
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            onState?("localNet: listener error \(error.localizedDescription)")
        }
    }

    func stop() {
        browser?.cancel()
        listener?.cancel()
        browser = nil
        listener = nil
    }
}
