/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Contains the video reader implementation using AVCapture.
*/

import Foundation
import AVFoundation
//import Darwin

internal class VideoReader {
    
    // 1ms
    static private let millisecondsInSecond: Float32 = 1000.0
    
    var frameRateInMilliseconds: Float32 {
        return self.videoTrack.nominalFrameRate
    }

    var frameRateInSeconds: Float32 {
        return self.frameRateInMilliseconds * VideoReader.millisecondsInSecond
    }

    var affineTransform: CGAffineTransform {
        return self.videoTrack.preferredTransform.inverted()
    }
    
    var orientation: CGImagePropertyOrientation {
        let angleInDegrees = atan2(self.affineTransform.b, self.affineTransform.a) * CGFloat(180) / CGFloat.pi
        
        var orientation: UInt32 = 1
        switch angleInDegrees {
        case 0:
            orientation = 1 // Recording button is on the right
        case 180:
            orientation = 3 // abs(180) degree rotation recording button is on the right
        case -180:
            orientation = 3 // abs(180) degree rotation recording button is on the right
        case 90:
            orientation = 8 // 90 degree CW rotation recording button is on the top
        case -90:
            orientation = 6 // 90 degree CCW rotation recording button is on the bottom
        default:
            orientation = 1
        }
        
        return CGImagePropertyOrientation(rawValue: orientation)!
    }
    
    private var videoAsset: AVAsset!
    private var videoTrack: AVAssetTrack!
    //媒体资源获取对象
    private var assetReader: AVAssetReader!
    private var videoAssetReaderOutput: AVAssetReaderTrackOutput!

    // 视频读取VideoReader类初始化方法
    init?(videoAsset: AVAsset) {
        self.videoAsset = videoAsset
        // 获取【视频】资源轨道级别数组情报（这里数组只有一个元素，即视频轨道）
        let array = self.videoAsset.tracks(withMediaType: AVMediaType.video)
        // 视频轨道
        self.videoTrack = array[0]

        guard self.restartReading() else {
            return nil
        }
    }

    
    func restartReading() -> Bool {
        do {
            self.assetReader = try AVAssetReader(asset: videoAsset)
        } catch {
            print("Failed to create AVAssetReader object: \(error)")
            return false
        }
        
        //从资源单轨道读取媒体资源（仅视频不包含音频）
        self.videoAssetReaderOutput = AVAssetReaderTrackOutput(track: self.videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange])
        
        // 指解码后图片的格式（对当前硬件解码是最优最高效）
        //self.videoAssetReaderOutput = AVAssetReaderTrackOutput(track: self.videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        
        guard self.videoAssetReaderOutput != nil else {
            return false
        }
        
        self.videoAssetReaderOutput.alwaysCopiesSampleData = true

        guard self.assetReader.canAdd(videoAssetReaderOutput) else {
            return false
        }
        
        // Adds an output to the receiver
        self.assetReader.add(videoAssetReaderOutput)
        // Prepares the receiver for obtaining sample buffers from the asset
        return self.assetReader.startReading()
    }

    // return output sample buffer(CVImageBuffer of media data)
    func nextFrame() -> CVPixelBuffer? {
        guard let sampleBuffer = self.videoAssetReaderOutput.copyNextSampleBuffer() else {
            return nil
        }
        
        return CMSampleBufferGetImageBuffer(sampleBuffer)
    }
}
