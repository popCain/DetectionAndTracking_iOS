/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implements the view controller showing tracked content.
*/

import AVFoundation
import UIKit

class TrackingViewController: UIViewController {
    
    var visionProcessor: VisionTrackerProcessor!
    
    
    
    /// 清空目标框bbox按钮
    @IBOutlet weak var clearRectsButton: UIButton!
    
    /// 追踪开始/结束按钮
    @IBOutlet weak var startStopButton: UIBarButtonItem!
    
    /// 追踪帧画面显示UI
    @IBOutlet weak var trackingView: TrackingImageView!
    
    /// 子线程（子线程负责耗时操作，主线程负责UI更新，防止阻塞）
    private var workQueue = DispatchQueue(label: "com.apple.VisionTracker", qos: .userInitiated)
    
    // MARK: - 此AVAsset视频资源属性在AssetsViewController中实现初始化
    /// prepare(): 通过performSegue()传值实现
    var videoAsset: AVAsset! {
        
        /// 属性监视器（didSet：当属性值变化后，必须进行以下操作）
        didSet {
            
            /// 初始化VisionTrackerProcessor类（传值给此类）
            visionProcessor = VisionTrackerProcessor(videoAsset: videoAsset)
            visionProcessor.delegate = self
        }
    }
    
    /// startStopButton的追踪开始/结束状态指示
    enum State {
        case tracking
        case stopped
    }
    
    // MARK: - 属性强制处理（追踪按钮状态及UI）
    private var state: State = .stopped {
        
        /// 追踪按钮状态初始化（任何时候属性变化时，强制进行以下操作）
        didSet {
            
            /// 追踪按钮状态及UI更新
            self.handleStateChange()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    // MARK: - 页面消失时，结束追踪任务，释放内存
    override func viewWillDisappear(_ animated: Bool) {
        visionProcessor.cancelTracking()
        super.viewWillDisappear(animated)
    }
    
    // MARK: - 首帧显示（存在目标检测的耗时操作）
    override func viewDidLoad() {
        super.viewDidLoad()
        
        ///耗时操作，不能在主线程main中，main主线程只能用来UI刷新操作
        ///DispatchQueue.global().async与此实例化workQueue一样
        workQueue.async {
            
            /// 显示视频第一帧的缩略图
            self.displayFirstVideoFrame()
        }
        
        /// 跟踪属性为准确度优先
        visionProcessor.trackingLevel = .accurate
    }
    
    // MARK: - 首帧画面重绘显示方法
    /// 第一帧缩略图(调用visionProcessor类的方法处理对象，显示遵从其协议实现)
    private func displayFirstVideoFrame() {
        do {
            try visionProcessor.readAndDisplayFirstFrame()
        } catch {
            self.handleError(error)
        }
    }
    
    // MARK: -追踪开始方法
    /// 开始按键开始追踪
    private func startTracking() {
        do {
            /// true循环（执行追踪）
            try visionProcessor.performTracking()
        } catch {
            self.handleError(error)
        }
    }
    
    // MARK: -异常处理（自定义Errors枚举）
    /// 异常处理方法
    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            var title: String
            var message: String
            if let processorError = error as? VisionTrackerProcessorError {
                title = "Vision Processor Error"
                switch processorError {
                case .firstFrameReadFailed:
                    message = "Cannot read the first frame from selected video."
                case .objectTrackingFailed:
                    message = "Tracking of one or more objects failed."
                case .readerInitializationFailed:
                    message = "Cannot create a Video Reader for selected video."
                case .rectangleDetectionFailed:
                    message = "Rectagle Detector failed to detect rectangles on the first frame of selected video."
                }
            } else {
                title = "Error"
                message = error.localizedDescription
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    // MARK: -更改追踪按钮的UI（.play/.stop）
    /**
    
    - 跟踪按钮方法：
    
       1. 帧图像重绘显示
       2. 结束追踪后操作（显示首帧；更改追踪按键状态）
    
    */
    private func handleStateChange() {
        let newBarButton: UIBarButtonItem!
        var navBarHidden: Bool!
        
        switch state {
        
        /// 等待中（未追踪状态）
        case .stopped:
            
            /// 显示导航栏
            navBarHidden = false
            
            /// 系统自带UI（.play）：按钮的动作处理函数一样handleStartStopButton(_:)
            newBarButton = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(handleStartStopButton(_:)))
            
        /// 追踪进行中
        case .tracking:
            
            /// 隐藏导航栏
            navBarHidden = true
            
            /// 系统自带UI（.stop）：按钮的动作处理函数一样handleStartStopButton(_:)
            newBarButton = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(handleStartStopButton(_:)))
        }
        
        /// 导航栏显示/隐藏
        self.navigationController?.setNavigationBarHidden(navBarHidden, animated: true)
        
        UIView.animate(withDuration: 0.5, animations: {
            self.view.layoutIfNeeded()
            
            /// 添加至导航按钮右按钮
            self.navigationItem.rightBarButtonItem = newBarButton
        })
    }

    // MARK: -清空跟踪对象集合，显示首帧
    @IBAction func handleClearRectsButton(_ sender: UIButton) {
        //objectsToTrack.removeAll()
        workQueue.async {
            self.displayFirstVideoFrame()
        }
    }
    
    // MARK: -按键动作（开始/结束追踪）
    @IBAction func handleStartStopButton(_ sender: UIBarButtonItem) {
        switch state {
        case .tracking:
            /// stop tracking
            self.visionProcessor.cancelTracking()
            self.state = .stopped
            workQueue.async {
                self.displayFirstVideoFrame()
            }
        case .stopped:
            /// start tracking
            state = .tracking
            workQueue.async {
                self.startTracking()
            }
        }
    }// button动作方法over
    
    // MARK: -屏幕点击操作时显示/隐藏导航栏
    /// 是否隐藏导航栏（追踪状态下，页面显示效果）
    @IBAction func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        
        /// 追踪进行时，点击屏幕才有效果
        guard state == .tracking, gestureRecognizer.state == .ended else {
            return
        }
        guard let navController = self.navigationController else {
            return
        }
        
        /// 获取当前导航栏的状态：显示/隐藏
        let navBarHidden = navController.isNavigationBarHidden
        
        /// 点击后隐藏状态更新为显示，显示状态f更新为隐藏
        navController.setNavigationBarHidden(!navBarHidden, animated: true)
    }// 屏幕点击事件处理结束
    
}// class over


// MARK: -VisionTrackerProcessorDelegate协议实现（帧画面显示；结束追踪后操作）
/**
 
 - 协议实现方法：
 
    1. 帧图像重绘显示
    2. 结束追踪后操作（显示首帧；更改追踪按键状态）
 
 */
extension TrackingViewController: VisionTrackerProcessorDelegate {
    
    /// VisionTrackerProcessorDelegated协议实现（帧图像重绘显示）
    /// - Parameters:
    ///   - frame: CVPixelBuffer
    ///   - transform: 2D图形绘制进行的矩阵仿射变换
    ///   - rects: 自定义目标结构体（丰富信息）
    ///   - detectTrackUUID: 检测：就跟踪UUID
    func displayFrame(_ frame: CVPixelBuffer?, withAffineTransform transform: CGAffineTransform, rects: [TrackedPolyRect]?, detectTrackUUID:[UUID:UUID]?) {
        
        // 异步执行，防止阻塞（通知ui更新）
        DispatchQueue.main.async {
            
            if let frame = frame {
                let ciImage = CIImage(cvPixelBuffer: frame).transformed(by: transform)
                let uiImage = UIImage(ciImage: ciImage)
                self.trackingView.image = uiImage
            }
            
            //self.trackingView.polyRects = rects ?? (self.trackedObjectType == .object ? self.objectsToTrack : [])
            self.trackingView.polyRects = rects!
            self.trackingView.rubberbandingStart = CGPoint.zero
            self.trackingView.rubberbandingVector = CGPoint.zero
            
            self.trackingView.FPS_detect = self.visionProcessor.FPS_detect
            self.trackingView.FPS_track = self.visionProcessor.FPS_track
            
            self.trackingView.trackDetectUUID = detectTrackUUID!
            print("++++++++++++++++++++跨页面传递+++++++++++++++++++++++++")
            print(detectTrackUUID!.count)
            
            
            // need to redraw（TrackingImageView）
            self.trackingView.setNeedsDisplay()
         }// 主线程更新界面范围
    }// 页面显示方法结束
    
    /// 是否结束追踪
    func didFinifshTracking() {
        
        /// 首帧显示
        workQueue.async {
            self.displayFirstVideoFrame()
        }
        
        /// 更改追踪按键状态（按键时可重新追踪）
        DispatchQueue.main.async {
            self.state = .stopped
        }
    }// method over
    
}// protocol reality over
