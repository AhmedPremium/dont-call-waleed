import SceneKit
import UIKit

final class OpeningScene {
    let root = SCNNode()
    private var lights = [SCNLight]()
    private var reachHand: SCNNode?
    private let door = SCNNode()
    private let oak = HouseMaterials.make(.oak,tint:UIColor(red:0.79,green:0.72,blue:0.64,alpha:1))
    private let quilt = HouseMaterials.make(.cloth,tint:UIColor(red:0.52,green:0.39,blue:0.32,alpha:1))
    private let pale = UIColor(red:0.61,green:0.55,blue:0.46,alpha:1)
    private let timber = UIColor(red:0.32,green:0.22,blue:0.16,alpha:1)

    init() {
        root.position = SCNVector3(OpeningLayout.worldX,0,OpeningLayout.worldZ)
        root.name = "Connected bedroom and foyer"
        bedroom()
        stairs()
        foyer()
    }

    func setLit(_ lit:Bool) {
        for light in lights { light.intensity = lit ? (light.name == "Landing" ? 575 : 720) : 0 }
    }

    private func makeHand() -> SCNNode {
        let hand = SCNNode()
        let skin = UIColor(red:0.67,green:0.47,blue:0.35,alpha:1)
        let sleeve = UIColor(red:0.28,green:0.35,blue:0.41,alpha:1)
        block(0.15,0.14,0.51,0,-0.015,0.275,sleeve,parent:hand)
        block(0.135,0.078,0.143,0,0,0.011,skin,parent:hand)
        for i in 0..<4 {
            let x = (Float(i)-1.5)*0.032
            let finger = block(0.027,0.029,0.084,x,0.004,-0.087,skin,parent:hand)
            finger.eulerAngles.x = 0.34
        }
        let thumb = block(0.043,0.036,0.077,-0.077,-0.005,-0.016,skin,parent:hand)
        thumb.eulerAngles.y = 0.46
        return hand
    }

    func reachForKnob() {
        let hand = makeHand()
        hand.name = "Yamen reaching hand"
        hand.position = SCNVector3(1.34,0.53,OpeningLayout.frontDoorZ+0.85)
        hand.eulerAngles = SCNVector3(-0.16,-0.47,0.18)
        root.addChildNode(hand)
        reachHand = hand
        let grab = SCNAction.move(to:SCNVector3(0.605,1.04,OpeningLayout.frontDoorZ+0.223),duration:0.66)
        grab.timingMode = .easeInEaseOut
        hand.runAction(.group([grab,.rotateTo(x:0.05,y:0,z:-0.09,duration:0.66,usesShortestUnitArc:true)]))
    }

    func openFrontDoor() {
        if let hand = reachHand {
            let position = door.convertPosition(hand.position,from:root)
            hand.removeFromParentNode()
            hand.position = position
            door.addChildNode(hand)
            hand.runAction(.sequence([.rotateBy(x:0,y:0,z:-0.22,duration:0.13),.wait(duration:0.36),.fadeOut(duration:0.23)]))
        }
        let swing = SCNAction.rotateTo(x:0,y:1.14,z:0,duration:0.65,usesShortestUnitArc:true)
        swing.timingMode = .easeInEaseOut
        door.runAction(.sequence([.wait(duration:0.09),swing]))
    }

    func slamFrontDoor() {
        door.removeAllActions()
        door.runAction(.rotateTo(x:0,y:0,z:0,duration:0.22,usesShortestUnitArc:true))
        reachHand?.removeFromParentNode()
        reachHand = nil
    }

    func pushUp(camera:SCNNode) {
        for sign in [Float(-1),1] {
            let hand = makeHand()
            hand.position = SCNVector3(sign*0.29,-0.36,-0.57)
            hand.eulerAngles = SCNVector3(0.34,sign*0.24,sign*0.20)
            camera.addChildNode(hand)
            hand.runAction(.sequence([.wait(duration:0.57),.moveBy(x:0,y:-0.48,z:0.17,duration:0.73),.removeFromParentNode()]))
        }
    }

    private func bedroom() {
        let y = OpeningLayout.upperFloor
        block(6.6,0.15,5.7,0,y-0.075,2.85,timber,finish:oak)
        block(6.6,0.12,5.7,0,y+2.63,2.85,pale)
        block(6.6,2.65,0.16,0,y+1.32,5.68,pale)
        for sign in [Float(-1),1] {
            block(0.15,2.65,5.7,sign*3.3,y+1.32,2.85,pale)
            block(2.26,2.65,0.16,sign*2.18,y+1.32,0,pale)
            block(0.075,0.14,5.6,sign*3.21,y+0.07,2.85,timber,finish:oak)
        }
        block(2.18,0.30,0.15,0,y+2.47,0,timber,finish:oak)
        block(1.78,1.03,0.13,-2.00,y+0.52,5.33,timber,finish:oak)
        block(1.65,0.29,2.14,-2.00,y+0.23,4.24,timber,finish:oak)
        block(1.58,0.21,2.11,-2.00,y+0.47,4.24,UIColor(white:0.67,alpha:1))
        block(1.55,0.10,1.40,-2.00,y+0.61,3.92,pale,finish:quilt)
        for x in [Float(-2.39),-1.62] {
            block(0.56,0.15,0.43,x,y+0.66,4.97,UIColor(white:0.86,alpha:1))
        }
        block(0.70,0.68,0.53,-0.70,y+0.34,5.04,timber,finish:oak)
        block(0.44,0.028,0.34,-0.70,y+0.711,5.02,.black)
        block(0.42,0.018,0.28,-0.70,y+0.731,5.02,UIColor(red:0.105,green:0.19,blue:0.25,alpha:1))
        lamp(x:1.6,y:y+2.25,z:3.6,intensity:760)
        lamp(x:-2.25,y:y+1.1,z:4.70,intensity:270)
    }

    private func stairs() {
        let length = -OpeningLayout.stairEnd
        let steps = 15
        let run = length/Float(steps)
        let drop = OpeningLayout.upperFloor/Float(steps)
        for index in 0..<steps {
            let z = -(Float(index)+0.5)*run
            let y = OpeningLayout.upperFloor-Float(index)*drop
            block(2.12,0.048,run-0.008,0,y-0.024,z,timber,finish:oak)
            block(2.10,drop-0.041,0.055,0,y-(drop+0.039)/2,z-run/2+0.024,pale)
        }
        for side in [Float(-1),1] {
            block(0.13,5.34,length,side*1.12,2.67,-length/2,pale)
            for i in 0..<8 {
                let z = -0.26-Float(i)*0.70
                let y = OpeningLayout.floorHeight(at:z)
                block(0.057,0.75,0.061,side*0.97,y+0.37,z,timber,finish:oak)
            }
            let rail = block(0.088,0.11,6.22,side*0.97,2.28,-2.80,timber,finish:oak)
            rail.eulerAngles.x = -0.47
        }
        lamp(x:0,y:3.65,z:-2.8,intensity:480)
    }

    private func foyer() {
        let front = OpeningLayout.frontDoorZ
        block(6.4,0.13,5.15,0,-0.065,-8.02,.gray,finish:HouseMaterials.make(.tile))
        block(6.4,0.13,5.22,0,2.68,-8.02,pale)
        for side in [Float(-1),1] {
            if side < 0 {
                block(0.16,2.69,5.2,side*3.20,1.34,-8.02,pale)
            } else {
                let openingZ = OpeningLayout.portalLocalZ
                for z in [openingZ-1.89, openingZ+1.80] {
                    block(0.16,2.69,1.36,side*3.20,1.34,z,pale)
                }
                block(0.19,0.37,2.4,side*3.20,2.51,openingZ,timber,finish:oak)
                for z in [openingZ-1.13, openingZ+1.13] {
                    block(0.22,2.38,0.16,side*3.20,1.19,z,timber,finish:oak)
                }
            }
            block(2.29,2.69,0.18,side*2.06,1.34,front,pale)
            block(2.23,2.69,0.18,side*2.1,1.34,-5.60,pale)
            block(0.11,2.42,0.25,side*0.903,1.20,front,timber,finish:oak)
        }
        block(1.92,0.21,0.25,0,2.42,front,timber,finish:oak)
        door.position = SCNVector3(-0.82,0,front)
        root.addChildNode(door)
        block(1.65,2.30,0.12,0.82,1.15,0,timber,finish:oak,parent:door)
        for height in [Float(0.53),1.60] {
            block(1.28,0.78,0.029,0.82,height,0.071,pale,finish:oak,parent:door)
        }
        let brass = UIColor(red:0.61,green:0.44,blue:0.22,alpha:1)
        let knob = SCNSphere(radius:0.070)
        knob.firstMaterial?.diffuse.contents = brass
        let handle = SCNNode(geometry:knob)
        handle.position = SCNVector3(1.41,1.04,0.14)
        door.addChildNode(handle)
        block(0.062,0.069,0.026,0.82,1.55,0.10,brass,parent:door)
        block(1.54,0.026,0.84,0,0.014,-9.71,timber,finish:quilt)
        block(1.35,0.73,0.56,-2.08,0.36,-9.88,timber,finish:oak)
        lamp(x:0,y:2.30,z:-8.47,intensity:720)
    }

    @discardableResult
    private func block(_ w:Float,_ h:Float,_ d:Float,_ x:Float,_ y:Float,_ z:Float,_ color:UIColor,
                       finish:SCNMaterial? = nil,parent:SCNNode? = nil) -> SCNNode {
        let mesh = SCNBox(width:CGFloat(w),height:CGFloat(h),length:CGFloat(d),chamferRadius:0.008)
        let surface = finish ?? SCNMaterial()
        if finish == nil { surface.diffuse.contents = color }
        mesh.materials = [surface]
        let node = SCNNode(geometry:mesh)
        node.position = SCNVector3(x,y,z)
        (parent ?? root).addChildNode(node)
        return node
    }

    private func lamp(x:Float,y:Float,z:Float,intensity:CGFloat) {
        let lamp = SCNLight()
        lamp.type = .omni
        lamp.color = UIColor(red:1,green:0.83,blue:0.65,alpha:1)
        lamp.intensity = intensity
        lamp.attenuationEndDistance = 8
        let node = SCNNode()
        node.position = SCNVector3(x,y,z)
        node.light = lamp
        lights.append(lamp)
        root.addChildNode(node)
    }
}
