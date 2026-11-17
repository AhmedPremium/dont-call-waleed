import CoreFoundation
import SceneKit
import UIKit

enum HouseMaterials {
    enum Surface { case tile, cloth, oak, window }

    private static let tile = texture { g in
        for row in 0..<4 {
            for col in 0..<4 {
                let gray = 0.57 + CGFloat((row * 7 + col * 3) % 5) * 0.029
                let x = col * 64, y = row * 64
                g.setFillColor(UIColor(white:0.26, alpha:1).cgColor)
                g.fill(CGRect(x:x, y:y, width:64, height:64))
                g.setFillColor(UIColor(red:gray, green:gray+0.018, blue:gray+0.022, alpha:1).cgColor)
                g.fill(CGRect(x:x+2, y:y+2, width:61, height:61))
                g.setStrokeColor(UIColor(white:0.82, alpha:0.45).cgColor)
                g.stroke(CGRect(x:x+3, y:y+3, width:59, height:59))
            }
        }
        for n in 0..<460 {
            g.setFillColor(UIColor(white:0.15, alpha:0.08).cgColor)
            g.fill(CGRect(x:(n*53+n/9)%256, y:(n*97+n/14)%256, width:2, height:1))
        }
    }

    private static let cloth = texture { g in
        g.setFillColor(UIColor(red:0.85,green:0.83,blue:0.80,alpha:1).cgColor)
        g.fill(CGRect(x:0,y:0,width:256,height:256))
        for n in stride(from:0,to:256,by:4) {
            g.setFillColor(UIColor(white:0.29,alpha:0.42).cgColor)
            g.fill(CGRect(x:n,y:0,width:1,height:256))
            g.fill(CGRect(x:0,y:n,width:256,height:1))
            g.setFillColor(UIColor(white:0.98,alpha:0.35).cgColor)
            g.fill(CGRect(x:n+2,y:0,width:1,height:256))
        }
    }

    private static let oak = texture { g in
        g.setFillColor(UIColor(red:0.72,green:0.55,blue:0.40,alpha:1).cgColor)
        g.fill(CGRect(x:0,y:0,width:256,height:256))
        for n in 0..<112 {
            let x = CGFloat((n*61)%256)
            let width = 0.45 + CGFloat(n%5)*0.23
            let bend = CGFloat((n*17)%13-6)
            g.setLineWidth(width)
            g.setStrokeColor(UIColor(red:0.18,green:0.11,blue:0.07,alpha:0.10+CGFloat(n%6)*0.04).cgColor)
            g.move(to:CGPoint(x:x,y:0))
            g.addCurve(to:CGPoint(x:x,y:256),control1:CGPoint(x:x+bend,y:68),control2:CGPoint(x:x-bend,y:184))
            g.strokePath()
        }
    }

    private static let window = texture { g in
        let stops: [CGColor] = [
            UIColor(red:0.035,green:0.063,blue:0.12,alpha:1).cgColor,
            UIColor(red:0.19,green:0.30,blue:0.43,alpha:1).cgColor
        ]
        if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:stops as CFArray,locations:[0,1]) {
            g.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:240,y:256),options:[])
        }
        g.setFillColor(UIColor(red:0.033,green:0.062,blue:0.075,alpha:1).cgColor)
        g.move(to:CGPoint(x:0,y:256))
        for n in 0...24 {
            let x = n*11
            let y = 215-(n*17+n*n*3)%36
            g.addLine(to:CGPoint(x:x,y:y+13))
            g.addLine(to:CGPoint(x:x+5,y:y))
        }
        g.addLine(to:CGPoint(x:264,y:256))
        g.closePath()
        g.fillPath()
        for n in 0..<95 {
            g.setFillColor(UIColor(white:0.82,alpha:0.06+CGFloat(n%5)*0.035).cgColor)
            g.fill(CGRect(x:(n*67+n/4)%256,y:(n*83+n*n)%256,width:1,height:3+n%14))
        }
    }

    static func make(_ surface:Surface, tint:UIColor = .white) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.wrapS = .repeat
        result.diffuse.wrapT = .repeat
        result.diffuse.mipFilter = .linear
        result.multiply.contents = tint
        switch surface {
        case .tile:
            result.diffuse.contents = tile
            result.specular.contents = UIColor(white:0.20,alpha:1)
            result.shininess = 36
        case .cloth:
            result.diffuse.contents = cloth
        case .oak:
            result.diffuse.contents = oak
            result.specular.contents = UIColor(white:0.13,alpha:1)
        case .window:
            result.lightingModel = .constant
            result.diffuse.contents = window
        }
        return result
    }

    private static func texture(_ draw:(CGContext) -> Void) -> UIImage {
        // SceneKit expects color textures the simulator can sample as sRGB.
        // A UIKit-rendered grayscale image can become an unsupported R8 sRGB texture.
        let size = 256
        guard let colorSpace = CGColorSpace(name:CGColorSpace.sRGB),
              let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,
                                      bytesPerRow:size*4,space:colorSpace,
                                      bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return UIImage()
        }
        draw(context)
        guard let image = context.makeImage() else { return UIImage() }
        return UIImage(cgImage:image)
    }
}
