import UIKit
import AVFoundation
import AVKit
import CoreMedia

/// PiP
final class PiPHost: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {

    let layer = AVSampleBufferDisplayLayer()
    private let holder = UIView()
    private var controller: AVPictureInPictureController?

    private let frameSize = CGSize(width: 480, height: 270)

 /// layer PiP
    func attach(to window: UIWindow) {
        if holder.superview != nil { return }

 //
        holder.frame = CGRect(x: -frameSize.width, y: -frameSize.height,
                              width: frameSize.width, height: frameSize.height)
        holder.isUserInteractionEnabled = false
        holder.backgroundColor = .black
        window.addSubview(holder)

        layer.frame = CGRect(origin: .zero, size: frameSize)
        layer.videoGravity = .resizeAspect
        holder.layer.addSublayer(layer)
    }

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

 /// ContentSource failableinit? controller
    func start() {
        guard isSupported else { return }
        if controller == nil {
            guard let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: layer,
                playbackDelegate: self) else { return }
            let ctl = AVPictureInPictureController(contentSource: source)
            ctl.canStartPictureInPictureAutomaticallyFromInline = true
            controller = ctl
        }
        controller?.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

 /// PiPUIImage BGRA CVPixelBuffer CMSampleBuffer enqueue
    func push(_ image: UIImage) {
        guard let pb = image.pixelBuffer(),
              let sb = CMSampleBuffer.from(pb) else { return }
        if layer.status == .failed {
            layer.flush()
        }
        layer.enqueue(sb)
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    setPlaying playing: Bool) {
 // /
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .indefinite)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
 //
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
