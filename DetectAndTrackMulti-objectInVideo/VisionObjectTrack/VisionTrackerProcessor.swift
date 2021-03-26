/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 Contains the tracker processing logic using Vision.
 */

import AVFoundation
import UIKit
import Vision
import Upsurge
import Hume

/// 自定义Errors枚举
enum VisionTrackerProcessorError: Error {
    case readerInitializationFailed
    case firstFrameReadFailed
    case objectTrackingFailed
    case rectangleDetectionFailed
}

/// - protocol:
///   - func displayFrame()  // UI 更新（重绘）
///   - didFinifshTracking()  //追踪结束（显示首帧；更改追踪按键状态）
protocol VisionTrackerProcessorDelegate: class {
    func displayFrame(_ frame: CVPixelBuffer?, withAffineTransform transform: CGAffineTransform, rects: [TrackedPolyRect]?, detectTrackUUID:[UUID:UUID]?)
    func didFinifshTracking()
}


/// 通过Vision处理追踪
class VisionTrackerProcessor {
    
    var FPS_track:String = "Tracking Speed"
    var FPS_detect:String = "Detection Speed"
    /// 匿名函数来初始化属性（目标检测模型）
    let visionModel: VNCoreMLModel = {
        do {
            /// 目标检测模型初始化
            //let coreMLModel = YOLOv3FP16()
            //let coreMLModel = MobileNetV2_SSDLite()
            //let coreMLModel = MobileNetV3_SSDLite_small()
            
            let coreMLModel = MobileNetV3_SSDLite_Large()
            //let coreMLModel = YOLOv3()
            
            /// try 用在最后的有效操作代码前（出错时进入catch代码）
            return try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Failed to create VNCoreMLModel: \(error)")
        }
    }()
    
    /// 处理追踪请求不是单个图片信息，而是系列图像信息的requestHangler
    private var requestHandler_track = VNSequenceRequestHandler()
    
    /// 可检测交通相关类：人，自行车，汽车，摩托车，公交，货车
    let labelsToTrack:[String] = ["person", "bicycle", "car", "motorcycle", "bus", "truck"]
    
    /// 跟踪目标的ID（画图显示用）
    var trackCountNum:Int = 0
    
    /// 跟踪目标的UUID数组
    var trackUUID = [UUID]()
    
    // oldTrackUUID:newDetectUUID(跟新画图中的轨迹点集：UUID-CenterPoint)
    var track_DetectUUID = [UUID:UUID]()
    
    /// 开始时间（检测/跟踪）
    var startTime_detect:Double = 0.0
    
    /// 抽象视频资源
    var videoAsset: AVAsset!
    
    /// 追踪精度：.accurate / .fast（此处选择精度优先）
    var trackingLevel = VNRequestTrackingLevel.accurate
    //var trackingLevel = VNRequestTrackingLevel.fast
    
    /// 最大跟踪数（ 原则上是16个 ）
    var maxTrackNum:Int = 8
    
    /// 画图用的信息（BBox，label，trackCount，color...）
    var rects = [TrackedPolyRect]()
    
    /// 代理声明
    weak var delegate: VisionTrackerProcessorDelegate?
    
    /// 追踪结束标识
    private var cancelRequested = false
    
    /// 目标检测PolyRect结果集（BBox等strut / Label / trackCount / color）
    var detectedRects = [TrackedPolyRect]()
    
    /// UUID : Label 字典
    var label_uuid = [UUID:String]()
    
    /// UUID : trackCount 字典
    var count_uuid = [UUID:Int]()
    
    /// 检测到的目标observation数组
    var detectedObjects = [VNRecognizedObjectObservation]()
    
    /// 追踪目标框的位置及大小，颜色等信息，字典型
    var trackedObjects = [UUID: TrackedPolyRect]()
    
    
    ///  VisionTrackerProcessor类初始化方法(要传递视频资源)
    ///  TrackingViewController中调用（参数来自AssetViewController中传递过来的的视频资源）
    /// - Parameter videoAsset: 视频资源
    // MARK: - 初始化VisionTrackerProcessor类(参数传递：视频资源)
    init(videoAsset: AVAsset) {
        self.videoAsset = videoAsset
    }
    
    
    /// 计算IOU：跟踪目标集BBox & 新检测目标集BBox
    /// - Parameters:
    ///   - detectedBBox: 检测目标集框
    ///   - trackedBBox: 跟踪目标集框
    ///   - threshold: 检测框与跟踪框为同一目标的阈值（小于此阈值置零）
    func calculate_IOU(detectedBBox:CGRect, trackedBBox:CGRect, threshold:CGFloat)->Double{
        
        // 检测框面积
        let s1 = (detectedBBox.maxX - detectedBBox.minX)*(detectedBBox.maxY - detectedBBox.minY)
        
        // 跟踪框面积
        let s2 = (trackedBBox.maxX - trackedBBox.minX)*(trackedBBox.maxY - trackedBBox.minY)
        
        // 相交矩形坐标
        let xmin = max(detectedBBox.minX, trackedBBox.minX)
        let ymin = max(detectedBBox.minY, trackedBBox.minY)
        let xmax = min(detectedBBox.maxX, trackedBBox.maxX)
        let ymax = min(detectedBBox.maxY, trackedBBox.maxY)
        
        let w = max(0, xmax - xmin)
        let h = max(0, ymax - ymin)
        
        let area = w * h
        var IOU = area/(s1 + s2 - area)
        
        // 小于此阈值的均视为新目标
        if IOU < threshold {
            IOU = 0
        }
        
        return Double(IOU)
    }
    
    
    /**
     
     - 首帧页面显示：
     
        1. 获取视频资源（首帧：sample buffer）
        2. CoreML模型执行目标检测任务（初始化待追踪目标集）
        3. 显示更新UI(首帧图像重绘)
     
        // 注*：此方法存在耗时操作（目标检测），故TrackingViewController中进入页面调用时，明确是在子线程中执行
     
     */
    // MARK: - 首帧显示及目标检测任务处理（耗时）
    func readAndDisplayFirstFrame() throws {
        /// Prepares the receiver(VideoReader) for obtaining sample buffers from the asset
        guard let videoReader = VideoReader(videoAsset: videoAsset) else {
            throw VisionTrackerProcessorError.readerInitializationFailed
        }
        /// get sample buffer(CVImageBuffer) of media data
        guard let firstFrame = videoReader.nextFrame() else {
            throw VisionTrackerProcessorError.firstFrameReadFailed
        }
        
        /// 清空检测到的对象作图信息集，重新检测
        self.detectedRects.removeAll()
        /// 清空目标跟踪集，重新进行初始化
        self.trackedObjects.removeAll()
        /// 清空检测到的目标集
        self.detectedObjects.removeAll()
        
        /// 目标跟踪递增ID置零
        self.trackCountNum = 0

        /// 匿名函数初始化属性(目标检测请求)
        let request_detect:VNCoreMLRequest = {
            let request = VNCoreMLRequest(model: self.visionModel, completionHandler: {
                [weak self] request, error in
                self?.processObservations(for: request, error: error, toTrack: true)
            })
           
            /// Currently they assume the full input image is used.
            request.imageCropAndScaleOption = .scaleFill
            return request
        }()
        
        /// Get additional info from the camera.
        var options: [VNImageOption : Any] = [:]
        if let cameraIntrinsicMatrix = CMGetAttachment(firstFrame, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            options[.cameraIntrinsics] = cameraIntrinsicMatrix
        }
        
        /// VNImageRequestHandler（VNImageRequestHandler来处理目标检测请求）
        let requestHandler_detect = VNImageRequestHandler(cvPixelBuffer: firstFrame, orientation: .up, options: options)
        do{
            /// 检测用时
            startTime_detect = CFAbsoluteTimeGetCurrent()
            try requestHandler_detect.perform([request_detect])
        } catch {
            print("Failed to perform Vision request: \(error)")
        }
        
        /// UI更新显示首帧图像（及检测到的目标信息）
        delegate?.displayFrame(firstFrame, withAffineTransform: videoReader.affineTransform, rects: self.detectedRects, detectTrackUUID: self.track_DetectUUID)
    }
    
    
    /**
     
     - 处理追踪事务方法：
     
        1. 获取视频资源（帧：sample buffer）
        2. true 循环（追踪目标：初始追踪目标为检测到的多个目标）
        3. 显示更新UI(视频帧图像重绘)
     
     */
    // MARK: - 追踪任务处理（耗时操作）
    func performTracking() throws {
        
        /// 本地视频读取（通过VideoReader类）
        guard let videoReader = VideoReader(videoAsset: videoAsset) else {
            throw VisionTrackerProcessorError.readerInitializationFailed
        }
        
        /// 是否成功读取首帧
        guard videoReader.nextFrame() != nil else {
            throw VisionTrackerProcessorError.firstFrameReadFailed
        }
        
        //MARK:- 目标检测初始化部分（VNCoreMLRequest：用自己的coremlModel）
        let request_detect:VNCoreMLRequest = {
            let request = VNCoreMLRequest(model: self.visionModel, completionHandler: {
                [weak self] request, error in
                self?.processObservations(for: request, error: error, toTrack: false)
            })
           
            /// Currently they assume the full input image is used.
            request.imageCropAndScaleOption = .scaleFill
            return request
        }()
        
        /// Get additional info from the camera.
        var options: [VNImageOption : Any] = [:]
        
        /// 是否结束追踪标识
        cancelRequested = false
        
        /// 可追踪目标是否完全消失
        var trackingFailedForAtLeastOneObject = false
        
        /// 帧计数（逐帧跟踪，隔帧检测）
        var frameCount:Int = 0
        
        
        // MARK: - 循环检测跟踪（追踪结束按钮🔘/到达最后帧-跳出循环♻️）
        while true {
            
            /// 每次目标检测时，清空之前检测到的对象，新一帧检测
            self.detectedRects.removeAll() // 检测到的交通系目标（包含绘画信息 - 只作用在首帧）
            self.detectedObjects.removeAll() // 检测到的交通系目标（observation数组）
            self.trackUUID.removeAll() // 跟踪到目标的uuid集（每次都要重置）
            self.track_DetectUUID.removeAll()// 匹配的trackUUID：detectUUID
            self.rects.removeAll() // 每次追踪检测，初始化一次检测到的目标信息(包含绘画信息)
            
            /// 循环结束标志✅ -- 1.追踪是否结束； 2.是否有读取到下一帧图像（逐帧读取）
            guard cancelRequested == false, let frame = videoReader.nextFrame() else {
                // 跳出循环（跳出当前True的循环）
                break
            }
            
            
            /**
             
                    -【目标跟踪操作】：
             
                        1. 多目标跟踪（初始化目标跟踪VNRequest集）
                        2. NSequenceRequestHandler().perform()
                        3. 处理跟踪结果
             
             */
            
            print("=============================== 一次循环开始 ===================================")
            /// 多目标跟踪（每个目标对应一个跟踪Request）：跟踪请求集( 小于16， 否则会出错， 无法处理跟踪请求) ⭐️
            var trackingRequests = [VNRequest]()
            
            // MARK: - 1. 针对多个追踪目标，每一个目标初始化一个追踪请求
            for trackOne in self.trackedObjects {
                
                if trackingRequests.count > self.maxTrackNum{
                    // 跟踪目标数不能大于规定最大跟踪数（跳出当前内循环for循环，不跳出True的外循环）
                    break
                }
                
                /// 追踪目标的标签（trackOne.key-UUID）
                label_uuid[trackOne.key] = trackOne.value.label
                /// 跟踪目标ID计数信息
                count_uuid[trackOne.key] = trackOne.value.count
               
                /// Vision的追踪请求（ trackOne：字典key为uuid， value为提取的目标特征对象Rect信息 ）
                let request_track:VNTrackObjectRequest =
                {
                    /// 跟踪请求结束标志-completionHandler: 调用processTrackingObservation()函数
                    let request = VNTrackObjectRequest(detectedObjectObservation: trackOne.value.observation, completionHandler: {
                        [weak self] request, error in
                        self?.processTrackingObservation(for: request, error: error)
                    })
                    return request
                }()
                
                /// 追踪请求算法选择（Revision1感觉更优秀）
                request_track.revision = VNTrackObjectRequestRevision1
                //request_track.revision = VNTrackObjectRequestRevision2
                
                /// 目标追踪精度要求
                request_track.trackingLevel = trackingLevel
                
                /// 多个目标的追踪请求组成的请求数组
                trackingRequests.append(request_track)
            }// 得目标跟踪请求集
            
            print("< --------- 初始化的「追踪request」数组大小 ----------- >")
            print("跟踪请求数：", trackingRequests.count)
            
            /// 获取当前时间
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // MARK: - 2. VNSequenceRequestHandler().perform():处理追踪请求（ do和catch只能执行一个 ）
            do {
                
                print(" o（^_^）o ・・>>>>>>>>>>>>>>>>>>> 进入跟踪进程： ")
                
                /// VNSequenceRequestHandler().perform() - 可能出现错误，需重新初始化跟踪Handler（　即追踪请求为空时　）
                try self.requestHandler_track.perform(trackingRequests, on: frame, orientation: videoReader.orientation)
                
                print("　<----------- 目标跟踪进程结束 ----------->")
                /// 竖屏拍摄的视频
                //try requestHandler.perform(trackingRequests, on: frame, orientation: .up)
            } catch {
                
                print("-- Track Error☠️ -- Track Error☠️ -- -- Track Error☠️ -- -- Track Error☠️ --")
                /// 可追踪目标均消失
                // trackingFailedForAtLeastOneObject = true
            }
            
            /// 获取当前时间，以计算多目标追踪耗时
            let endTime_1 = CFAbsoluteTimeGetCurrent()
            
            let cost_time_track = (endTime_1 - startTime)*1000
            print(" o（^_^）o 跟踪结果计算时长为(ms): ", cost_time_track)
            if Int(cost_time_track) != 0 {
                self.FPS_track = "Tracking Speed: " + String(1000/Int(cost_time_track)) + " FPS"
            }
            
            /// 帧数
            frameCount = frameCount + 1
            
            /*
            /// Draw results( displayFrame 方法中UI更新是在主线程异步执行，防止阻塞 )
            self.delegate?.displayFrame(frame, withAffineTransform: videoReader.affineTransform, rects: self.rects)
            ///进程挂起，单位微秒（1ms）:useconds_t( 微秒：frameRateInSeconds = 1000 )
            usleep(useconds_t(videoReader.frameRateInSeconds - 900))
            */
        
            /**
                       
                      -【目标检测操作】：
             
                          1. VNCoreMLRequest初始化（追踪时已初始化完成）
                          2. VNImageRequestHandler.perform()
                          3. self?.processObservations(for: request, error: error, toTrack: false)：处理目标检测结果
                       
            */
            
            // && self.trackedObjects.count < self.maxTrackNum
            if frameCount%3 == 0 {
                
                if let cameraIntrinsicMatrix = CMGetAttachment(frame, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
                    options[.cameraIntrinsics] = cameraIntrinsicMatrix
                }
                
                /// VNImageRequestHandler（VNImageRequestHandler来处理目标检测请求）
                let requestHandler_detect = VNImageRequestHandler(cvPixelBuffer: frame, orientation: .up, options: options)
                
                do{
                    /// 检测用时
                    startTime_detect = CFAbsoluteTimeGetCurrent()
                    print(" o（^_^）o ・・>>>>>>>>>>>>>>>>>>>>> 进入检测进程：")
                    try requestHandler_detect.perform([request_detect])
                } catch {
                    print("Failed to perform Vision request: \(error)")
                }
                
                print("　<----------- 目标检测进程结束 ----------->")
            }
            print("　========================== 一次循环结束 ========================")
            print("\n")
            
            /// speed test
            let endTime_2 = CFAbsoluteTimeGetCurrent()
            
            // 经检测结果更新过的rects
            self.rects = [TrackedPolyRect](self.trackedObjects.values)
            
            /// Draw results( displayFrame 方法中UI更新是在主线程异步执行，防止阻塞 )
            self.delegate?.displayFrame(frame, withAffineTransform: videoReader.affineTransform, rects: self.rects, detectTrackUUID: self.track_DetectUUID)
            
            ///　进程挂起，单位微秒（1ms）:useconds_t( 微秒：frameRateInSeconds = 1000 )
            usleep(useconds_t(videoReader.frameRateInSeconds))
            
        }// True循环追踪检测over
        
        print("######################- 跳出ture循环 -###############################")
        /// 追踪结束（首帧显示，等待追踪按键动作）
        delegate?.didFinifshTracking()
        
        /// 追踪目标均消失
        if trackingFailedForAtLeastOneObject {
            print("~~~~~~~~~~~~~~~~~~~~~~~~ 追踪目标全消失 ~~~~~~~~~~~~~~~~~~~~~")
            throw VisionTrackerProcessorError.objectTrackingFailed
        }
    }// func performTracking() over
    
    
    /// 目标追踪结束：返回追踪结果结果，更新跟踪对象（BoundingBox）
    /// - Parameters:
    ///   - request: 目标跟踪请求
    ///   - error: 可能抛出的错误
    // MARK: - 目标跟踪结果处理（observation）
    func processTrackingObservation(for request:VNRequest, error:Error?){
        
        print("-<->-处理目标跟踪的结果：")
        if (error != nil){
            print(error ?? ">没有错误<")
            /// 当有错误时重新初始化requestHandler
            self.requestHandler_track = VNSequenceRequestHandler()
            return
        }
        
        // MARK: - 3. 处理跟踪结果
            
            /// get追踪结果( VNObservation )
            guard let results = request.results as? [VNObservation] else {
                // 本次循环到此结束，进入下一次循环
                return
            }
            
            /// get追踪目标特征对象( VNDetectedObjectObservation )
            guard let observation = results.first as? VNDetectedObjectObservation else {
                // 本次循环到此结束，进入下一次循环
                return
            }
            
            print("$(^_^)$: 目标跟踪结果（confidece）: " + String(observation.confidence))
            print(observation.uuid)
            
            /// Assume threshold = 0.2f （实线/虚线）
            let rectStyle: TrackedPolyRectStyle = observation.confidence > 0.7 ? .solid : .dashed
            
            /// get同一目标的原框选颜色（根据唯一UUID）
            let knownRect = self.trackedObjects[observation.uuid]!
            
            /// 追踪目标的信心较低时，从追踪对象集合中移除 threshold=0.5
            if observation.confidence > 0.5 {
                
                /// 更新保存新的追踪Rect对象（bbox已更新的同一目标）
                let rect = TrackedPolyRect(observation: observation, color: knownRect.color, label:label_uuid[observation.uuid]!, count:count_uuid[observation.uuid]!, style: rectStyle)
                
                /// 信心大于0.5的对象，可画入显示页面(这是画图用的：displayFrame)
                //self.rects.append(rect)
                
                /// 更新作为下一次追踪目标的集合
                self.trackedObjects[observation.uuid] = rect
                
            }else{
                // 注*：信心太低表示跟丢了，有： 1 算法本身不足跟丢的原因；2 消失（出屏幕范围了）；3 被遮挡了
                /// 信心太低， 移除待追踪目标集合
                self.trackedObjects.removeValue(forKey: observation.uuid)
                // TODO: need to do：-rects.remove(at: 信心太低已不需要追踪的rect)
            }
       
    }
    
    
    /// 目标检测结束：返回检测结果作为初始化跟踪对象
    /// - Parameters:
    ///   - request: 目标检测请求
    ///   - error: 可能抛出的错误
    // MARK: - 目标检测结果处理（observation）
    func processObservations(for request: VNRequest, error: Error?, toTrack: Bool){
        
        /// 获取当前时间，以计算多目标追踪耗时
        let endTime_detect = CFAbsoluteTimeGetCurrent()
        
        let cost_time_detect = (endTime_detect - startTime_detect)*1000
        print("目标检测结果计算时长为(ms): ", cost_time_detect)
        if cost_time_detect != 0 {
            self.FPS_detect = "Detection Speed: " + String(1000/Int(cost_time_detect)) + " FPS"
        }
        
        /// 从results属性中得图像分析结果对象：Observation
        if let results = request.results as? [VNRecognizedObjectObservation] {
            
            /// 各检测结果
            for observation in results{
                
                // 保证跟踪目标集中目标数，小于规定的最大跟踪数
                if self.trackedObjects.count > self.maxTrackNum {
                    break
                }
                
                /// 检测到的目标信息
                let bestClass = observation.labels[0].identifier
                let checkLable:Bool = self.labelsToTrack.contains(bestClass)
                
                // 只跟踪交通相关目标
                if checkLable {
                    // 只首帧
                    if(toTrack){
                        // MobileNetV3
                        let confidence_detect = 1 - observation.labels[0].confidence
                        // MobileNetV2
                        //let confidence_detect = observation.labels[0].confidence
                        
                        let label = String(format: "%@ %.1f", bestClass, confidence_detect * 100)
                        print("*****************\(label)*******************")
                        
                        /// CommonTypes(16种颜色中选择一种, 初始化检测到的目标对象)
                        let rectColor = TrackedObjectsPalette.color(atIndex: self.trackCountNum)
                        let detectedRect = TrackedPolyRect(observation: observation, color: rectColor, label:label, count:self.trackCountNum)
                        
                        /// 初始化追踪目标的信息集合
                        self.detectedRects.append(detectedRect)
                        
                        //print(self.trackedObjects.isEmpty)
                        //print(self.trackedObjects.description)
                        
                        self.trackCountNum = self.trackCountNum + 1;
                        
                        
                        /// 赋予追踪目标唯一UUID  [UUID:TrackedPolyRect]
                        self.trackedObjects[observation.uuid] = detectedRect
                        
                    }else{
                        // 首帧之后的检测
                        self.detectedObjects.append(observation)
                        print("  ---- 加入到了检测到的交通相关的目标数组")
                    }
                }
            }// 各检测结果处理完成
            
            // 追踪序列开始后(检测到的目标集合不能为空)
            if (!toTrack && !self.detectedObjects.isEmpty) {
                
                print("  ---- 进入持续跟踪监测阶段：")
                
                // 追踪目标集合不能为空（若为空，直接将检测到的目标集 赋值 给追踪集合）
                if self.trackedObjects.isEmpty {
                    print("追踪数组为空？？？？？？？？？？？？？")
                    //self.trackCountNum = 0
                    for observation in self.detectedObjects {
                        
                        // 保证跟踪目标集中目标数，小于规定的最大跟踪数
                        if self.trackedObjects.count > self.maxTrackNum {
                            break
                        }
                        
                        // MobileNetV3
                        let confidence_detect = 1 - observation.labels[0].confidence
                        // MobileNetV2
                        //let confidence_detect = observation.labels[0].confidence
                        let bestClass = observation.labels[0].identifier
                        let label = String(format: "%@ %.1f", bestClass, confidence_detect * 100)
                        print("*****************\(label)*******************")
                        
                        /// CommonTypes(16种颜色中选择一种, 初始化检测到的目标对象)
                        let rectColor = TrackedObjectsPalette.color(atIndex: self.trackCountNum)
                        let trackedRect = TrackedPolyRect(observation: observation, color: rectColor, label:label, count:self.trackCountNum)
                        self.trackedObjects[observation.uuid] = trackedRect
                        self.trackCountNum = self.trackCountNum + 1
                    }
                    print("就这样结束了吗！！！！！！！！！！！！！！！！！！！！！！！")
                    return //
                }
                
                // 检测到目标BBOx数组
                var detected_bboxes:[CGRect] = []
                // 追踪到目标Bbox数组
                var tracked_bboxes:[CGRect] = []
                
                print("【混合检测】----检测到数量和追踪数量：")
                print(detectedObjects.count)
                print(self.trackedObjects.count)
                print("\n")
                
                // 得检测目标BBOX
                for i in 0...self.detectedObjects.count-1 {
                    detected_bboxes.append(detectedObjects[i].boundingBox)
                }
                
                // 得跟踪目标BBOX
                for value in self.trackedObjects.values{
                    self.trackUUID.append(value.observation.uuid)
                    tracked_bboxes.append(value.observation.boundingBox)
                }
            
                // 检测到目标：行数； 追踪到目标：列数
                let rowCount = detected_bboxes.count
                let columnCount = tracked_bboxes.count
                
                // iou_cost矩阵：检测行，跟踪列
                var iou_multiArray = [[Double]](repeating: [Double](repeating: 0.0, count: columnCount), count: rowCount)
                
                var i = 0
                var j = 0
                for detectedRect in detected_bboxes {
                    for trackedRect in tracked_bboxes {
                        let IOU = calculate_IOU(detectedBBox: detectedRect, trackedBBox: trackedRect, threshold: 0.1)
                        iou_multiArray[i][j] = IOU
                        j = j + 1
                    }
                    j = 0
                    i = i + 1
                }
                
                print(" - IOU成本矩阵：")
                print(iou_multiArray)
                
                let KM = HunSolver(matrix: iou_multiArray, maxim: true)!
                let KM_result:(Double,[(Int, Int)]) = KM.solve()
                print(" - 匈牙利（KM）匹配结果：")
                print(KM_result)
                
                let matched_tupleArray = KM_result.1
                
                for matched_tuple in matched_tupleArray {
                    
                    // 以列数为基准（（,0）(,1) (,2) (,3) (,4)...）:检测为行，跟踪为列（ 行列均未越界时 ）
                    if matched_tuple.0<=rowCount-1 && matched_tuple.1<=columnCount-1 {
                        
                        // MARK:- 初始化updateTrackedRect用(绘制追踪所需信息的结构体)
                        let observation = self.detectedObjects[matched_tuple.0]
                        
                        // MobileNetV3
                        let confidence_detect = 1 - observation.labels[0].confidence
                        // MobileNetV2
                        //let confidence_detect = observation.labels[0].confidence
                        
                        // Label信息
                        let bestClass = observation.labels[0].identifier
                        let label = String(format: "%@ %.1f", bestClass, confidence_detect * 100)
                        print("*****************\(label)*******************")
                        
                        // 行列均未越界时(说明是方阵，即跟踪目标数与当前检测数一样，但没法保证完全匹配)
                        if iou_multiArray[matched_tuple.0][matched_tuple.1]==0.0 {
                            
                            print("这里是有检测和跟踪集非完全匹配的！！！！！！")
                            // 保证跟踪目标集中目标数，小于规定的最大跟踪数
                            if self.trackedObjects.count > self.maxTrackNum {
                                continue
                            }
                            
                            // 说明这俩其实并未匹配成功（只是凑方阵的原因）
                            /// CommonTypes(16种颜色中选择一种, 初始化检测到的目标对象)
                            let rectColor = TrackedObjectsPalette.color(atIndex: self.trackCountNum)
                            
                            /// 绘图所需信息
                            let updateTrackedRect = TrackedPolyRect(observation: observation, color: rectColor, label:label, count:self.trackCountNum)
                            
                            /// 未匹配到的检测目标，直接作为新目标加入到跟踪目标集
                            self.trackedObjects[observation.uuid] = updateTrackedRect
                            
                            /// 跟踪目标ID加一
                            self.trackCountNum = self.trackCountNum + 1
                            
                        }else{
                            
                            // 匹配成功的目标，用检测框更新跟踪框（检测框更准）
                            let oldTrackUUID = self.trackUUID[matched_tuple.1]
                            
                            // 匹配的newDetectUUID：oldTrackUUID字典
                            self.track_DetectUUID[observation.uuid] = oldTrackUUID
                            
                            /// 继承原跟踪框颜色，目标ID
                            let rectColor = self.trackedObjects[oldTrackUUID]?.color
                            let curretCount = self.trackedObjects[oldTrackUUID]?.count
                            let updateTrackedRect = TrackedPolyRect(observation: observation, color: rectColor!, label:label, count:curretCount!)
                            
                            // 目标检测目标更新跟踪集（检测到目标的uuid）
                            self.trackedObjects[observation.uuid] = updateTrackedRect
                            
                            // 删除原跟踪目标集的目标
                            self.trackedObjects.removeValue(forKey: oldTrackUUID)
                            
                        }
                    }else if matched_tuple.1 > columnCount-1{
                        
                        // 保证跟踪目标集中目标数，小于规定的最大跟踪数
                        if self.trackedObjects.count > self.maxTrackNum {
                            break
                        }
                        
                        // 列越界，说明检测目标数大于追踪目标数（此处追踪目标框不存在，是补零产生的）
                        let observation = self.detectedObjects[matched_tuple.0]
                        // MobileNetV3
                        let confidence_detect = 1 - observation.labels[0].confidence
                        // MobileNetV2
                        //let confidence_detect = observation.labels[0].confidence
                        let bestClass = observation.labels[0].identifier
                        let label = String(format: "%@ %.1f", bestClass, confidence_detect * 100)
                        print("*****************\(label)*******************")
                        
                        /// CommonTypes(16种颜色中选择一种, 初始化检测到的目标对象)
                        let rectColor = TrackedObjectsPalette.color(atIndex: self.trackCountNum)
                        let trackedRect = TrackedPolyRect(observation: observation, color: rectColor, label:label, count:self.trackCountNum)
                        self.trackedObjects[observation.uuid] = trackedRect
                        
                        self.trackCountNum = self.trackCountNum + 1
                        
                    }else{
                        // 行越界，说明检测目标数小于跟踪目标数（此处的检测目标框不存在，是补零产生的）
                        //let oldTrackUUID = self.trackUUID[matched_tuple.1]
                        print("可能未检测到此跟踪目标")
                        // 删除原跟踪目标集的目标(因为此处并未检测到目标)
                        //self.trackedObjects.removeValue(forKey: oldTrackUUID)
                        continue // 进入下一次循环
                    }
                }// 匹配元组中，未匹配到的检测框判断for循环完成
                
           }// 追踪开始后，开始不断进行目标检测
            
        }// 从results属性中得图像分析结果对象（目标检测结果）：Observation
        
    }/// func over
    
    /// 结束追踪( TrackingViewController中追踪结束按键动作时调用 )
    // MARK: - 结束追踪任务
    func cancelTracking() {
        cancelRequested = true
    }
    
    
}/// class over
