import UIKit
import AVFoundation
import CoreVideo
import CoreMedia

// MARK: - UIImage -> CVPixelBuffer

extension UIImage {
 /// BGRA CVPixelBufferPiP AVSampleBufferDisplayLayer
    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard let cg = self.cgImage else { return nil }

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                        kCVPixelFormatType_32BGRA,
                                        attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let pb = buffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(data: base,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bitmapInfo) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }

 /// BGRAPiP
    func pixelBuffer() -> CVPixelBuffer? {
        guard let cg = self.cgImage else { return nil }
        return toPixelBuffer(width: cg.width, height: cg.height)
    }
}

// MARK: - CVPixelBuffer -> CMSampleBuffer

extension CMSampleBuffer {
    static func from(_ pb: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        let s1 = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                             imageBuffer: pb,
                                                             formatDescriptionOut: &format)
        guard s1 == noErr, let fmt = format else { return nil }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)

        var sample: CMSampleBuffer?
        let s2 = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                          imageBuffer: pb,
                                                          formatDescription: fmt,
                                                          sampleTiming: &timing,
                                                          sampleBufferOut: &sample)
        guard s2 == noErr else { return nil }
        return sample
    }
}

// MARK: -

/// PiP + audio background mode
/// AVAudioEngine 0
final class SilentAudio {
    private let engine = AVAudioEngine()

    func start() {
        guard !engine.isRunning else { return }

        let mixer = engine.mainMixerNode
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else { return }

        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buf in list {
                if let data = buf.mData {
                    memset(data, 0, Int(buf.mDataByteSize))
                }
            }
            _ = frameCount
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: mixer, format: format)
        mixer.outputVolume = 0

        engine.prepare()          // prepare() is not throwing
        try? engine.start()       // start() throws
    }

    func stop() {
        if engine.isRunning { engine.stop() }
    }
}
