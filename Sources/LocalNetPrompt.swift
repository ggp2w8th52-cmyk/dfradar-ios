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
