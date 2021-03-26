/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Defines common types used throughout the sample.
*/

import Foundation
import UIKit
import Vision

enum TrackedObjectType: Int {
    case object
    case rectangle
}

enum TrackedPolyRectStyle: Int {
    case solid
    case dashed
}

struct Center_UUID {
    var uuid:UUID
    var center:CGPoint
}

struct TrackedObjectsPalette {
    static var palette = [
        UIColor.white,
        UIColor.cyan,
        UIColor.orange,
        UIColor.brown,
        UIColor.red,
        UIColor.green,
        UIColor.blue,
        UIColor.yellow,
        UIColor.magenta,
        UIColor.purple,
        #colorLiteral(red: 0, green: 1, blue: 0, alpha: 1), // light green
        UIColor.darkGray,
        UIColor.gray,
        #colorLiteral(red: 0, green: 0.9800859094, blue: 0.941437602, alpha: 1),   // light blue
        UIColor.black,
        UIColor.lightGray,
    ]
    
    static func color(atIndex index: Int) -> UIColor {
        if index < palette.count {
            return palette[index]
        }
        return randomColor()
    }
    
    static func randomColor() -> UIColor {
        func randomComponent() -> CGFloat {
            return CGFloat(arc4random_uniform(256)) / 255.0
        }
        return UIColor(red: randomComponent(), green: randomComponent(), blue: randomComponent(), alpha: 1.0)
    }
}

struct TrackedPolyRect {
    
    var observation: VNDetectedObjectObservation
    var label:String
    var count:Int
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
    var center: CGPoint
    
    var color: UIColor
    var style: TrackedPolyRectStyle
    
    
    var cornerPoints: [CGPoint] {
        // 返回四个点的坐标
        return [topLeft, topRight, bottomRight, bottomLeft]
    }
    
    var boundingBox: CGRect {
        let topLeftRect = CGRect(origin: topLeft, size: .zero)
        let topRightRect = CGRect(origin: topRight, size: .zero)
        let bottomLeftRect = CGRect(origin: bottomLeft, size: .zero)
        let bottomRightRect = CGRect(origin: bottomRight, size: .zero)

        return topLeftRect.union(topRightRect).union(bottomLeftRect).union(bottomRightRect)
    }
    
    
    init(observation: VNDetectedObjectObservation, color: UIColor, label:String, count:Int, style: TrackedPolyRectStyle = .solid) {
        //self.init(cgRect: observation.boundingBox, color: color, style: style)
        let cgRect = observation.boundingBox
        topLeft = CGPoint(x: cgRect.minX, y: cgRect.maxY)
        topRight = CGPoint(x: cgRect.maxX, y: cgRect.maxY)
        bottomLeft = CGPoint(x: cgRect.minX, y: cgRect.minY)
        bottomRight = CGPoint(x: cgRect.maxX, y: cgRect.minY)
        center = CGPoint(x:(cgRect.minX + cgRect.maxX)/2, y:(cgRect.minY + cgRect.maxY)/2)
        self.color = color
        self.style = style
        self.observation = observation
        self.label = label
        self.count = count
    }
    
}

