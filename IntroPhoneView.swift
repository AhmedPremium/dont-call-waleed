import UIKit

final class IntroPhoneView: UIView {
    enum Screen { case lock, home, recents, contact, dialing, connected, lost, ending }
    var screen = Screen.lock { didSet { setNeedsDisplay() } }

    private let green = UIColor(red:0.15,green:0.74,blue:0.42,alpha:1)
    private let midnight = UIColor(red:0.064,green:0.08,blue:0.12,alpha:1)

    override init(frame: CGRect) {
        super.init(frame:frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Yamen’s phone"
    }

    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.scaleBy(x:bounds.width/180,y:bounds.height/336)
        let skin = UIColor(red:0.46,green:0.30,blue:0.23,alpha:1)
        fill(29,211,45,121,22,skin)
        fill(116,212,61,112,26,skin)
        fill(43,304,125,31,15,skin)
        fill(13,5,148,310,26,UIColor(white:0.24,alpha:1))
        fill(15,7,144,306,24,.black)
        fill(21,13,132,294,20,midnight)
        fill(72,18,30,8,4,.black)
        text("3:00",29,24,40,10,.white,weight:.semibold)
        symbol("battery.75percent",122,23,20,.white)

        switch screen {
        case .lock:
            symbol("lock.fill",80,51,14,.white)
            text("3:00",28,73,119,44,.white,centered:true,weight:.light)
            text("AM",32,128,112,13,.white,centered:true)
            text("Swipe up to unlock",29,259,117,10,.white,centered:true)
            tap(x:87,y:286)
        case .home:
            text("Yamen",31,54,105,20,.white,weight:.semibold)
            tile("phone.fill","Phone",32,100,green)
            tile("message.fill","Messages",84,100,.systemTeal)
            tile("camera.fill","Camera",32,167,.systemIndigo)
            tile("flashlight.on.fill","Light",84,167,.systemOrange)
            tap(x:49,y:117)
        case .recents:
            text("Phone",30,52,110,10,green)
            text("Recents",30,72,110,23,.white,weight:.bold)
            text("Today",31,119,112,11,.lightGray)
            fill(27,141,119,38,8,UIColor(white:0.18,alpha:1))
            text("Waleed",34,147,81,15,.white,weight:.semibold)
            text("Mobile",34,164,84,9,.lightGray)
            symbol("info.circle",123,153,12,green)
            text("Recents        Contacts",30,267,113,9,.lightGray,centered:true)
            tap(x:75,y:157)
        case .contact:
            identity(detail:"Mobile")
            button("phone.fill",x:70,y:221,color:green)
            tap(x:87,y:238)
        case .dialing, .connected, .lost:
            let detail = screen == .dialing ? "Calling mobile…" : (screen == .connected ? "00:01  •  Connected" : "Call failed")
            identity(detail:detail)
            symbol("speaker.wave.2.fill",43,177,16,.white)
            symbol("mic.slash.fill",114,177,16,.white)
            button("phone.down.fill",x:70,y:221,color:UIColor(red:0.88,green:0.22,blue:0.26,alpha:1))
        case .ending:
            text("INCOMING CALL",27,54,120,11,.lightGray,centered:true,weight:.semibold)
            symbol("phone.arrow.down.left",75,88,24,green)
            text("Yamen",28,117,118,27,.white,centered:true,weight:.semibold)
            text("Your own number",27,155,120,12,.lightGray,centered:true)
            button("phone.fill",x:70,y:221,color:green)
        }
        fill(64,296,46,3,1.5,UIColor(white:0.92,alpha:0.8))
        ctx.restoreGState()
    }

    private func identity(detail:String) {
        fill(62,55,50,50,25,UIColor(red:0.22,green:0.29,blue:0.40,alpha:1))
        text("W",62,65,50,22,.white,centered:true,weight:.semibold)
        text("Waleed",28,115,118,24,.white,centered:true,weight:.semibold)
        text(detail,27,148,121,11,.lightGray,centered:true)
    }

    private func tile(_ icon:String,_ name:String,_ x:CGFloat,_ y:CGFloat,_ color:UIColor) {
        fill(x,y,36,36,9,color)
        symbol(icon,x+9,y+9,18,.white)
        text(name,x-7,y+40,50,9,.white,centered:true)
    }

    private func button(_ icon:String,x:CGFloat,y:CGFloat,color:UIColor) {
        fill(x,y,34,34,17,color)
        symbol(icon,x+9,y+9,16,.white)
    }

    private func tap(x:CGFloat,y:CGFloat) {
        UIColor.white.withAlphaComponent(0.8).setStroke()
        let ring = UIBezierPath(ovalIn:CGRect(x:x-10,y:y-10,width:20,height:20))
        ring.lineWidth = 1.5
        ring.stroke()
    }

    private func fill(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ r:CGFloat,_ color:UIColor) {
        color.setFill()
        UIBezierPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerRadius:r).fill()
    }

    private func text(_ value:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ size:CGFloat,_ color:UIColor,
                      centered:Bool = false,weight:UIFont.Weight = .regular) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = centered ? .center : .left
        (value as NSString).draw(in:CGRect(x:x,y:y,width:w,height:size*1.35),withAttributes:[
            .font:UIFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:paragraph
        ])
    }

    private func symbol(_ name:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:UIColor) {
        UIImage(systemName:name)?.withTintColor(color,renderingMode:.alwaysOriginal)
            .draw(in:CGRect(x:x,y:y,width:size,height:size))
    }
}
