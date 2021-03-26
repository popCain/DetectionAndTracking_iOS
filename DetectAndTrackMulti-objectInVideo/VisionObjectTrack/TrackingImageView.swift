/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 Implements the main tracking image view.
 */

import Foundation
import UIKit
import Vision

class TrackingImageView: UIView {
    
    /// 子线程（子线程负责耗时操作，主线程负责UI更新，防止阻塞）
    private var featureQueue = DispatchQueue(label: "com.apple.featurePrint", qos: .userInitiated)
    
    private var visionProcessor: VisionTrackerProcessor!
    
    var image: UIImage!
    var polyRects = [TrackedPolyRect]()
    
    var FPS_track:String = ""
    var FPS_detect:String = ""
    var FPS_extractFeature:String = ""
    
    var imageAreaRect = CGRect.zero
    
    let dashedPhase = CGFloat(0.0)
    let dashedLinesLengths: [CGFloat] = [4.0, 2.0]
    var centerObjects = [Center_UUID]()
    var trackDetectUUID = [UUID:UUID]()
    
    // Rubber-banding setup
    var rubberbandingStart = CGPoint.zero
    var rubberbandingVector = CGPoint.zero
    var rubberbandingRect: CGRect {
        let pt1 = self.rubberbandingStart
        let pt2 = CGPoint(x: self.rubberbandingStart.x + self.rubberbandingVector.x, y: self.rubberbandingStart.y + self.rubberbandingVector.y)
        let rect = CGRect(x: min(pt1.x, pt2.x), y: min(pt1.y, pt2.y), width: abs(pt1.x - pt2.x), height: abs(pt1.y - pt2.y))
        
        return rect
    }
    
    var rubberbandingRectNormalized: CGRect {
        guard imageAreaRect.size.width > 0 && imageAreaRect.size.height > 0 else {
            return CGRect.zero
        }
        var rect = rubberbandingRect
        
        // Make it relative to imageAreaRect
        rect.origin.x = (rect.origin.x - self.imageAreaRect.origin.x) / self.imageAreaRect.size.width
        rect.origin.y = (rect.origin.y - self.imageAreaRect.origin.y) / self.imageAreaRect.size.height
        rect.size.width /= self.imageAreaRect.size.width
        rect.size.height /= self.imageAreaRect.size.height
        // Adjust to Vision.framework input requrement - origin at LLC
        rect.origin.y = 1.0 - rect.origin.y - rect.size.height
        
        return rect
    }
    
    /// 点击是否落在视频演示view中
    func isPointWithinDrawingArea(_ locationInView: CGPoint) -> Bool {
        return self.imageAreaRect.contains(locationInView)
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.setNeedsDisplay()
    }
    
    // 重写系统的UIKit：draw方法（2D绘图），获取UIView子类的上下文
    override func draw(_ rect: CGRect) {
        
        // 获取上下文(graphical context)，当作一个新的画布
        let ctx = UIGraphicsGetCurrentContext()!
        // 存储上下文，以便之后的存储动作
        ctx.saveGState()
        
        ctx.clear(rect)
        
        //无填充
        ctx.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        //ctx.setFillColor(UIColor.cyan.cgColor)
        ctx.setLineWidth(1)
        
        // Draw a frame
        guard let newImage = scaleImage(to: rect.size) else {
            return
        }
        newImage.draw(at: self.imageAreaRect.origin)
        //print("######################################")
        //print(self.imageAreaRect.origin)
        // Draw rubberbanding rectangle, if available
        if self.rubberbandingRect != CGRect.zero {
            
            ctx.setStrokeColor(UIColor.blue.cgColor)
            // Switch to dashed lines for rubberbanding selection
            ctx.setLineDash(phase: dashedPhase, lengths: dashedLinesLengths)
            ctx.stroke(self.rubberbandingRect)
        }
        
        /*******************************-- Draw rects（遍历各个目标框）--*********************************/
        for polyRect in self.polyRects {
            
            // 创建绘制目标框路径
            let path_object = CGMutablePath()
            // 创建绘制轨迹路径
            let path_path = CGMutablePath()
            
            // 目标uuid(跟踪结果的uuid)
            let uuid = polyRect.observation.uuid
            
            // 边框实线/虚线
            switch polyRect.style {
            case .solid:
                ctx.setLineDash(phase: dashedPhase, lengths: [])
            case .dashed:
                ctx.setLineDash(phase: dashedPhase, lengths: dashedLinesLengths)
            }
            
            /*******************************--  画中心点轨迹 --**************************************/
            // 中心点坐标(及尺度变换)
            let centerPoint = polyRect.center
            let previous_center = scale(cornerPoint: centerPoint, toImageViewPointInViewRect: rect)
            
            // 左上角起点坐标（及尺度变换）：画类别描述文字的位置
            let leftTop = polyRect.topLeft
            let scale_leftTop = scale(cornerPoint: leftTop, toImageViewPointInViewRect: rect)
            let previous_leftTop = CGPoint(x: scale_leftTop.x, y: (scale_leftTop.y - 13))
            
            // 左下角起点坐标（及尺度变换）：画跟踪物体计数
            /*
            let leftBottom = polyRect.bottomLeft
            let scale_leftBottom = scale(cornerPoint: leftBottom, toImageViewPointInViewRect: rect)
            let previous_leftBottom = CGPoint(x: scale_leftBottom.x, y: (scale_leftBottom.y - 15))
            */
            
            //UUID:Center(CGPoint)结构体
            let center_uuid = Center_UUID(uuid: uuid, center: previous_center)
            self.centerObjects.append(center_uuid)
            
            print("$$$$$$$$$$$$$$$$$$$$- 进入画图 -$$$$$$$$$$$$$$$$$$$$$")
            print(self.centerObjects.count)
            
            print("detect:track新旧UUID字典：")
            // [trackUUID:detectUUID]--[old:new]
            print(self.trackDetectUUID)
            print("$$$$$$$$$$$$$$$$$$$$$$$$- 出画图 -$$$$$$$$$$$$$$$$$$$$$$")
            print("\n")
            
            for i in 0..<self.centerObjects.count {
                // 更换元跟踪的uuid为新的检测uuid(uuid is old)
                if !self.trackDetectUUID.isEmpty && self.trackDetectUUID.keys.contains(uuid){
                    // uuid为新的检测目标的uuid（将原来的旧的跟踪uuid更换）
                    if self.centerObjects[i].uuid == self.trackDetectUUID[uuid] {
                        
                        //print("更改uuid成功！！！！！！！！！！！")
                        self.centerObjects[i].uuid = uuid
                    }
                    
                }
            }
            
            /// dictionary: [UUID : [Center_UUID]]
            let dictionary = Dictionary(grouping: self.centerObjects, by: {$0.uuid})
            
            var centers = [Center_UUID]()
            
            /// [Center_UUID](这个结构体数组中，所有的UUID都是当前最新的uuid)
            centers = dictionary[uuid]!
            
            /*
            if self.trackDetectUUID.keys.contains(uuid) {
                let newUUID = uuid
                centers = dictionary[newUUID]!
            }else{
                centers = dictionary[uuid]!
            }
            */
            
            var centerPoints = [CGPoint]()
            
            /// 从结构体中取出Center（CGPoint）点坐标
            for i in 0..<centers.count {
                centerPoints.append(centers[i].center)
            }
            
            //画运动轨迹
            path_path.addLines(between: centerPoints)
            
            /*******************************--  画bbox目标框  --**************************************/
            // 得四个点的坐标
            let cornerPoints = polyRect.cornerPoints
            // cornerPoints[3](左下点)
            var previous = scale(cornerPoint: cornerPoints[cornerPoints.count - 1], toImageViewPointInViewRect: rect)
            // 画矩形框bbox：[左上，右上， 右下， 左下]
            for cornerPoint in cornerPoints {
                //print("左上点开始，逆时针左下点结束：", cornerPoint)
                // 起点（左下点）
                path_object.move(to: previous)
                let current = scale(cornerPoint: cornerPoint, toImageViewPointInViewRect: rect)
                // 终点（左上点）| - | _
                path_object.addLine(to: current)
                previous = current
            }
            
            var left_top = scale(cornerPoint: cornerPoints[0], toImageViewPointInViewRect: rect)
            var right_bottom = scale(cornerPoint: cornerPoints[2], toImageViewPointInViewRect: rect)
            var bbox = CGRect(origin: left_top, size: CGSize(width: right_bottom.x-left_top.x, height: right_bottom.y-left_top.y))
            
            var fillColor = polyRect.color.cgColor.copy(alpha: 0.5)
             
            ctx.setFillColor(fillColor!)
            
            ctx.fill(bbox)
            // 添加画目标框的路径到上下文（ctx）
            ctx.addPath(path_object)
            // 添加画目标轨迹的路径到上下文（ctx）
            ctx.addPath(path_path)
            //设置边框颜色(对应不同目标)
            ctx.setStrokeColor(polyRect.color.cgColor)
            
            // 绘制路径(要在文字之前将目标框绘制完成)
            ctx.strokePath()
            ctx.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
            
            //ctx.drawPath(using: CGPathDrawingMode.stroke)
            
            // 获取显示目标标签(画文本)
            let str = polyRect.label
            let attrString = NSAttributedString(string: str, attributes: [NSAttributedString.Key.font:UIFont.systemFont(ofSize: 11, weight: .regular), NSAttributedString.Key.backgroundColor:polyRect.color])
            attrString.draw(at: previous_leftTop)
            
            // 显示目标番号
            let object_count = String(polyRect.count)
            let attrString_count = NSAttributedString(string: object_count, attributes: [NSAttributedString.Key.font:UIFont.systemFont(ofSize: 11, weight: .semibold), NSAttributedString.Key.backgroundColor:polyRect.color])
            let center_count = CGPoint(x: previous_center.x - 3, y: previous_center.y - 5)
            attrString_count.draw(at: center_count)
            
            // 打印点集
            //print("?????????????????????--<\(object_count)>")
            //print(centerPoints)
            //print("????????????????????????????????????")
            
            /*
                                这里是属于截图操作
             */
            // 截图并显示
            // 截图区域计算
            let topLeft_point = scale(cornerPoint: polyRect.topLeft, toImageViewPointInViewRect: rect)
            let bottomRight_point = scale(cornerPoint: polyRect.bottomRight, toImageViewPointInViewRect: rect)
            let bottomLeft_point = scale(cornerPoint: polyRect.bottomLeft, toImageViewPointInViewRect: rect)
            let topRight_point = scale(cornerPoint: polyRect.topRight, toImageViewPointInViewRect: rect)
            
            let target_Size = CGSize(width: abs(bottomLeft_point.x - topRight_point.x), height: abs(bottomLeft_point.y - topRight_point.y))
            
            //UIScreen.main.scale（默认主屏幕缩放scale factor是：2.0）
            // target_image.size = (750, 420)--newImage.size = (375, 210)
            let scale_X:CGFloat = 2
            let scale_Y:CGFloat = 2
            
            //let scale_X:CGFloat = 530/375
            //let scale_Y:CGFloat = 375/210
            //let transform = CGAffineTransform(scaleX: 1920/375, y: 1080/210)
            //let target_Rect = CGRect(origin: topRight_point, size: target_Size)
            
            let target_Rect_X:CGFloat = scale_X*topLeft_point.x
            // 纵坐标起始位置会有变化(不是trackingView的原点起始位置开始的，图片是显示在其中间位置的)
            // 但是在进行图片截取（crop操作时），是以图片左上角为原点的而不是画布的原点：
            // 裁剪区域Rect（左上为起始点，向右下方画矩形）
            let target_Rect_Y:CGFloat = scale_Y*(topLeft_point.y - self.imageAreaRect.minY)
            
            
            
            let target_Rect_Width:CGFloat = scale_X * target_Size.width
            let target_Rect_Height:CGFloat = scale_X * target_Size.height
            
            let target_Rect = CGRect(x: target_Rect_X, y: target_Rect_Y, width: target_Rect_Width, height: target_Rect_Height)
            
            
            //let target_Rect_test = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            
           // target_Rect_test.applying(transform)
            
            print("$$$$$$$$$$$$$- target_Rect -$$$$$$$$$$$")
            print(target_Rect)
            print(newImage.size)
            
            
            // 截取并显示(CGRect区域范围：Lower_Left（左下角开始的）)
            guard let target_image:UIImage = cropImage(newImage, withRect: target_Rect)else {
                return
            }
            
            print("%%%%%%%%%%%%%%%- target_image -%%%%%%%%%%%%%%%")
            print(target_image.size)
            
            //target_image.draw(at: CGPoint(x: 0, y: 0))
            //let at_position_x = floor((self.imageAreaRect.width - target_Size.width) / 2.0)
            
            target_image.draw(in: CGRect(x: topLeft_point.x, y: topLeft_point.y - 230.0, width: target_Size.width, height: target_Size.height))
            //self.position_show_x = self.position_show_x + target_Size.width + 5
            //newImage.draw(at: CGPoint(x: 0, y: 0))
            
            let target_cgimage = target_image.cgImage!
            
            /*
                由于计算比较耗时，所以先不计算，当快要显示出遮挡时，从保留的三帧或五帧目标图像中选择一个计算printFeature
             */
            // 耗时操作（提取图片特征）
            /*
            featureQueue.async {
                if #available(iOS 13.0, *) {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    // Make sure we can generate featureprint for original drawing.此为函数
                    guard let originalFPO = self.featureprintObservationForImage(target_cgimage) else {
                        return
                    }
                    
                    let endTime = CFAbsoluteTimeGetCurrent()
                    let costTime = (endTime - startTime)*1000
                    print("Cost Time: " + String(costTime))
                    if Int(costTime) != 0 {
                        let FPS = String(1000/Int(costTime))
                        self.FPS_extractFeature = "FeatureExtarct Speed: " + FPS + " FPS"
                        print("FeayureExtarct Speed: " + String(costTime) + "ms" + "(" + self.FPS_extractFeature + ")")
                    }
                    //print("((((((((((((((((- originalFPO_printFeature -))))))))))))))")
                    //print(originalFPO)
                } else {
                    // Fallback on earlier versions
                }
            }// 耗时操作线程结束
            */
            
        }// 遍历各目标框结束
        
        //如果 between 里面的点的个数是偶数，那就是每两点之间的连线。如果为奇数，在最后一个点将和（0，0）点组成一组的连线
        //ctx.strokeLineSegments(between: object_centerPoints)
        let center_FPS_track = CGPoint(x: self.imageAreaRect.minX + 10, y: self.imageAreaRect.maxY + 20)
        let attrString_FPS_track = NSAttributedString(string: self.FPS_track, attributes: [NSAttributedString.Key.font:UIFont.systemFont(ofSize: 11, weight: .semibold), NSAttributedString.Key.backgroundColor:UIColor.white])
        attrString_FPS_track.draw(at: center_FPS_track)
        
        let center_FPS_detect = CGPoint(x: self.imageAreaRect.minX + 10, y: self.imageAreaRect.maxY + 40)
        let attrString_FPS_detect = NSAttributedString(string: self.FPS_detect, attributes: [NSAttributedString.Key.font:UIFont.systemFont(ofSize: 11, weight: .semibold), NSAttributedString.Key.backgroundColor:UIColor.white])
        attrString_FPS_detect.draw(at: center_FPS_detect)
        
        let center_FPS_extractFeature = CGPoint(x: self.imageAreaRect.minX + 10, y: self.imageAreaRect.maxY + 60)
        let attrString_FPS_extractFeature = NSAttributedString(string: self.FPS_extractFeature, attributes: [NSAttributedString.Key.font:UIFont.systemFont(ofSize: 11, weight: .semibold), NSAttributedString.Key.backgroundColor:UIColor.white])
        attrString_FPS_extractFeature.draw(at: center_FPS_extractFeature)
        
        //重新载入
        ctx.restoreGState()
    }
    
    private func scaleImage(to viewSize: CGSize) -> UIImage? {
        guard self.image != nil && self.image.size != CGSize.zero else {
            return nil
        }
        
        self.imageAreaRect = CGRect.zero
        
        // There are two possible cases to fully fit self.image into the the ImageTrackingView area:
        // Option 1) image.width = view.width ==> image.height <= view.height
        // Option 2) image.height = view.height ==> image.width <= view.width
        let imageAspectRatio = self.image.size.width / self.image.size.height
        
        // Check if we're in Option 1) case and initialize self.imageAreaRect accordingly
        let imageSizeOption1 = CGSize(width: viewSize.width, height: floor(viewSize.width / imageAspectRatio))
        if imageSizeOption1.height <= viewSize.height {
            let imageX: CGFloat = 0
            let imageY = floor((viewSize.height - imageSizeOption1.height) / 2.0)
            self.imageAreaRect = CGRect(x: imageX,
                                        y: imageY,
                                        width: imageSizeOption1.width,
                                        height: imageSizeOption1.height)
        }
        
        if self.imageAreaRect == CGRect.zero {
            // Check if we're in Option 2) case if Option 1) didn't work out and initialize imageAreaRect accordingly
            let imageSizeOption2 = CGSize(width: floor(viewSize.height * imageAspectRatio), height: viewSize.height)
            if imageSizeOption2.width <= viewSize.width {
                let imageX = floor((viewSize.width - imageSizeOption2.width) / 2.0)
                let imageY: CGFloat = 0
                self.imageAreaRect = CGRect(x: imageX,
                                            y: imageY,
                                            width: imageSizeOption2.width,
                                            height: imageSizeOption2.height)
            }
        }
        
        // In next line, pass 0.0 to use the current device's pixel scaling factor (and thus account for Retina resolution).
        // Pass 1.0 to force exact pixel size.
        UIGraphicsBeginImageContextWithOptions(self.imageAreaRect.size, false, 0.0)
        self.image.draw(in: CGRect(x: 0.0, y: 0.0, width: self.imageAreaRect.size.width, height: self.imageAreaRect.size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    private func scale(cornerPoint point: CGPoint, toImageViewPointInViewRect viewRect: CGRect) -> CGPoint {
        // Adjust bBox from Vision.framework coordinate system (origin at LLC) to imageView coordinate system (origin at ULC)
        let pointY = 1.0 - point.y
        let scaleFactor = self.imageAreaRect.size
        //print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
        //print(scaleFactor)
        return CGPoint(x: point.x * scaleFactor.width + self.imageAreaRect.origin.x, y: pointY * scaleFactor.height + self.imageAreaRect.origin.y)
    }
    
    // 目标范围的图片截取
    private func cropImage(_ image: UIImage, withRect cropRect: CGRect) -> UIImage?{
            
        //let imageViewScale = max(image.size.width / 375.0, image.size.height / 530.0)
        let imageViewScale:CGFloat = 1
        print("&&&&&&&&&&&&&&&- imageViewScale -&&&&&&&&&&&&&&")
        print(imageViewScale)
        // Scale cropRect to handle images larger than shown-on-screen size
        let cropZone = CGRect(x:cropRect.origin.x * imageViewScale,
                              y:cropRect.origin.y * imageViewScale,
                              width:cropRect.size.width * imageViewScale,
                              height:cropRect.size.height * imageViewScale)

        // Perform cropping in Core Graphics
        guard let cutImageRef: CGImage = image.cgImage?.cropping(to:cropZone)
        else {
            return nil
        }

        // Return image to UIImage
        let croppedImage: UIImage = UIImage(cgImage: cutImageRef)
        return croppedImage
    }// 截取目标图函数
    
    // 获得图片特征值
    @available(iOS 13.0, *)
    func featureprintObservationForImage(_ image:CGImage) -> VNFeaturePrintObservation? {
        
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        
        // 图片特征输出请求
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try requestHandler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            print("Vision error: \(error)")
            return nil
        }
    }
    
}
