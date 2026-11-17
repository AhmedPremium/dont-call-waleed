import SceneKit

enum WaleedMesh {
    struct Ring {
        let y:Float
        let width:Float
        let depth:Float
        var shift:Float = 0
    }

    static func sculpt(_ rings:[Ring], material:SCNMaterial) -> SCNNode {
        let segments = 28
        var vertices = [SCNVector3]()
        var normals = [SCNVector3]()
        var indices = [UInt16]()
        for (row,ring) in rings.enumerated() {
            let above = rings[min(row+1,rings.count-1)]
            let below = rings[max(row-1,0)]
            for j in 0..<segments {
                let angle = Float(j)*2*Float.pi/Float(segments)
                let x = sin(angle), z = cos(angle)
                let width = ring.width*(1+0.025*sin(angle*3+ring.y*5))
                vertices.append(SCNVector3(width*x,ring.y,ring.depth*z+ring.shift))
                let slope = (above.width-below.width)/max(0.015,above.y-below.y)
                let direction = sqrt(1+slope*slope)
                normals.append(SCNVector3(x/direction,-slope/direction,z/direction))
                if row == 0 { continue }
                let a = UInt16((row-1)*segments+j)
                let b = UInt16((row-1)*segments+(j+1)%segments)
                let c = UInt16(row*segments+j)
                let d = UInt16(row*segments+(j+1)%segments)
                indices += [a,b,c,b,d,c]
            }
        }
        let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],
                                   elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        geometry.materials = [material]
        return SCNNode(geometry:geometry)
    }
}
