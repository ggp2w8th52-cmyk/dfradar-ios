import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = .black
        w.rootViewController = RadarVC()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

final class RadarVC: UIViewController {

    private let pip = PiPHost()
    private let net = Net()
    private let audio = SilentAudio()

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let preview = UIImageView()
    private let probeLabel = UILabel()
    private let pipButton = UIButton(type: .system)
    private let mockButton = UIButton(type: .system)
    private let probeButton = UIButton(type: .system)

    private var mockTimer: Timer?
    private var uiTimer: Timer?
    private var mockT: Double = 0
    private var lastCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
        configureAudio()

        // background queue -> main thread -> PiP push + preview + status
        net.onMsg = { [weak self] msg in
            DispatchQueue.main.async { self?.publish(msg) }
        }
        net.start(port: 47810)

        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let w = view.window { pip.attach(to: w) }
    }

    // MARK: - render / display

    private func publish(_ msg: Msg) {
        // 一旦收到真实数据就停掉自测，避免 mock 覆盖
        if let t = mockTimer {
            t.invalidate()
            mockTimer = nil
            mockButton.setTitle("Self test", for: .normal)
        }
        let img = render(msg)
        pip.push(img)
        preview.image = img
        lastCount = msg.ents.count
        refreshStatus()
    }

    // MARK: - buttons

    @objc private func onPiP() {
        if let w = view.window { pip.attach(to: w) }
        pip.start()
        statusLabel.textColor = pip.isSupported ? .systemGreen : .systemRed
        statusLabel.text = pip.isSupported ? "PiP start requested" : "PiP not supported"
    }

    @objc private func onMock() {
        if let t = mockTimer {
            t.invalidate()
            mockTimer = nil
            mockButton.setTitle("Self test", for: .normal)
            return
        }
        mockButton.setTitle("Stop self test", for: .normal)
        mockT = 0
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.mockT += 0.05
            self.publish(Mock.make(self.mockT))
        }
        RunLoop.main.add(t, forMode: .common)
        mockTimer = t
    }

    /// Reads the three environment flags a game could use to notice this app.
    @objc private func onProbe() {
        let s = AVAudioSession.sharedInstance()
        let captured = UIScreen.main.isCaptured
        let other = s.isOtherAudioPlaying
        let route = s.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")

        probeLabel.textColor = (captured || other) ? .systemOrange : .systemTeal
        probeLabel.text = String(format: "captured=%@  screens=%d  otherAudio=%@\n%@/%@  route=%@",
                                 captured ? "TRUE" : "false",
                                 UIScreen.screens.count,
                                 other ? "TRUE" : "false",
                                 s.category.rawValue,
                                 s.mode.rawValue,
                                 route.isEmpty ? "-" : route)
    }

    // MARK: - UI

    private func buildUI() {
        titleLabel.text = "DF Radar"
        titleLabel.textColor = .white
        titleLabel.font = .boldSystemFont(ofSize: 30)

        statusLabel.text = "listening :47810 | - | 0"
        statusLabel.textColor = .systemGreen
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.numberOfLines = 2

        preview.backgroundColor = .init(white: 0.08, alpha: 1)
        preview.contentMode = .scaleAspectFit
        preview.layer.borderColor = UIColor(white: 1, alpha: 0.15).cgColor
        preview.layer.borderWidth = 1

        probeLabel.text = "captured -   screens -   otherAudio -"
        probeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        probeLabel.textColor = .systemTeal
        probeLabel.numberOfLines = 3

        style(pipButton, "Start PiP", #selector(onPiP))
        style(mockButton, "Self test", #selector(onMock))
        style(probeButton, "Probe (3 flags)", #selector(onProbe))

        for v in [titleLabel, statusLabel, preview, pipButton, mockButton, probeButton, probeLabel] {
            view.addSubview(v)
        }
    }

    private func style(_ b: UIButton, _ title: String, _ action: Selector) {
        b.setTitle(title, for: .normal)
        b.setTitleColor(.black, for: .normal)
        b.backgroundColor = .systemGreen
        b.titleLabel?.font = .monospacedSystemFont(ofSize: 15, weight: .bold)
        b.layer.cornerRadius = 8
        b.addTarget(self, action: action, for: .touchUpInside)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let x: CGFloat = 16
        var y = view.safeAreaInsets.top + 16

        titleLabel.frame = CGRect(x: x, y: y, width: view.bounds.width - 32, height: 38); y += 44
        statusLabel.frame = CGRect(x: x, y: y, width: view.bounds.width - 32, height: 34); y += 42
        preview.frame = CGRect(x: x, y: y, width: 240, height: 135); y += 151

        for b in [pipButton, mockButton, probeButton] {
            b.frame = CGRect(x: x, y: y, width: 240, height: 42)
            y += 50
        }
        probeLabel.frame = CGRect(x: x, y: y, width: view.bounds.width - 32, height: 60)
    }

    // MARK: - status

    private func refreshStatus() {
        let ago = net.lastRecv.map { String(format: "%.1fs", Date().timeIntervalSince($0)) } ?? "-"
        let bindState = net.isBound ? "bind ok" : "bind FAIL"
        let recvColor: UIColor = net.received > 0 ? .systemGreen : .systemOrange

        // stale when no packet for more than 3 s
        statusLabel.textColor = net.isStale ? .systemRed : .systemGreen
        statusLabel.text = """
        \(bindState)  ip \(localIP()):47810
        pkts \(net.received) bad \(net.dropped)  last \(ago)  ents \(lastCount)
        """
        if net.received == 0 { statusLabel.textColor = recvColor }
    }

    /// 本机在 Wi-Fi / 热点上的 IPv4，便于确认 PC 该往哪发
    private func localIP() -> String {
        var addr = "?"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return addr }
        defer { freeifaddrs(ifaddr) }

        var ptr = first
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            if let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
               (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var sin = UnsafePointer<sockaddr_in>(OpaquePointer(sa))
                if let sin = sin {
                    var a = sin.pointee.sin_addr
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                        addr = String(cString: buf)
                    }
                    _ = host
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return addr
    }

    private func configureAudio() {
        let s = AVAudioSession.sharedInstance()
        // mixWithOthers keeps the game audio untouched; see README if isOtherAudioPlaying flips
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
        audio.start()
    }
}
