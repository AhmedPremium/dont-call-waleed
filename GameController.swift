import UIKit
import SceneKit
import AVFoundation
import CoreText

final class Stick: UIView {
    var vector = CGPoint.zero
    private let knob = UIView()
    override init(frame: CGRect) {
        super.init(frame:frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.06)
        layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor; layer.borderWidth = 1
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.25); knob.isUserInteractionEnabled = false; addSubview(knob)
        accessibilityLabel = "Movement joystick"
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); layer.cornerRadius = bounds.width/2; reset() }
    func reset() { vector = .zero; knob.frame = CGRect(x:bounds.midX-24,y:bounds.midY-24,width:48,height:48); knob.layer.cornerRadius = 24 }
    private func track(_ touches:Set<UITouch>) {
        guard let p = touches.first?.location(in:self) else { return }
        let dx = p.x-bounds.midX, dy = p.y-bounds.midY, d = max(1,hypot(p.x-bounds.midX,p.y-bounds.midY)), r = bounds.width*0.36
        vector = CGPoint(x:dx/d*min(d,r)/r,y:dy/d*min(d,r)/r)
        knob.center = CGPoint(x:bounds.midX+vector.x*r,y:bounds.midY+vector.y*r)
    }
    override func touchesBegan(_ t:Set<UITouch>,with e:UIEvent?) { track(t) }
    override func touchesMoved(_ t:Set<UITouch>,with e:UIEvent?) { track(t) }
    override func touchesEnded(_ t:Set<UITouch>,with e:UIEvent?) { reset() }
    override func touchesCancelled(_ t:Set<UITouch>,with e:UIEvent?) { reset() }
}

final class GameController: UIViewController {
    enum Phase { case title, intro, playing, paused, caught, escaped }
    private enum PhoneState {
        case idle, incoming(until: Float), outgoing(started: Float)
    }

    private let flashlightIntensity: CGFloat = 2400
    private let rooms: [(name: String, landmark: Cell, phone: Cell)] = [
        ("BEDROOM", Cell(x: 4, z: 1), Cell(x: 4, z: 2)),
        ("KITCHEN", Cell(x: 12, z: 1), Cell(x: 12, z: 2)),
        ("LOUNGE", Cell(x: 4, z: 6), Cell(x: 4, z: 7)),
        ("STUDY", Cell(x: 12, z: 6), Cell(x: 12, z: 7)),
        ("LAUNDRY", Cell(x: 4, z: 11), Cell(x: 4, z: 12)),
        ("WORKSHOP", Cell(x: 12, z: 11), Cell(x: 12, z: 12))
    ]
    private var phase = Phase.title
    private let sceneView = SCNView()
    private var world = SCNScene(), camera = SCNNode(), torch = SCNNode(), enemy = SCNNode()
    private var enemyEyes = [SCNNode]()
    private var enemyHead = SCNNode()
    private var enemyLimbs = [SCNNode]()
    private var gait: Float = 0
    private var enemyAwake = false
    private var lastKnownPlayer: Cell?
    private var searchRoute = [Cell]()
    private var houseAmbient: SCNLight?
    private let introOverlay = UIView()
    private let introCaption = UILabel(), introPhone = UILabel()
    private var introBeat = -1
    private var introElapsed: Float = 0
    private var phoneState = PhoneState.idle
    private var nextOutgoing: Float = 0
    private var lure: (target: Cell, until: Float)?
    private var ringtone: SCNAudioSource?
    private var remoteRing: SCNNode?
    private var fridge: SCNNode?
    private var fridgeHum: SCNAudioSource?
    private var fuseNodes = [SCNNode](), lamps = [SCNNode]()
    private let stick = Stick(frame:.zero), lookSurface = UIView(), controls = UIView(), shade = UIView(), danger = UIView()
    private let status = UILabel(), objective = UILabel(), message = UILabel(), hint = UILabel(), titleLabel = UILabel(), detailLabel = UILabel()
    private let use = UIButton(type:.system), lightButton = UIButton(type:.system), sprintButton = UIButton(type:.system), phoneButton = UIButton(type:.system), pauseButton = UIButton(type:.system), startButton = UIButton(type:.system), soundButton = UIButton(type:.system)
    private let menu = UIStackView()
    private let clockLabel = UILabel(), eyebrow = UILabel(), footer = UILabel()
    private let helpButton = UIButton(type:.system)
    private let menuArtwork = UIImageView()
    private var nextBurp: Float = 9
    private var burpSources = [SCNAudioSource]()
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var elapsed: Float = 0, yaw: Float = 0, pitch: Float = 0, battery: Float = 100, stamina: Float = 100
    private var running = false, hidden = false, flashlight = true, power = false, soundEnabled = true
    private var collected = Set<Int>(), route = [Cell]()
    private var nextCall: Float = 24, huntUntil: Float = 0, routeTime: Float = 0, messageUntil: Float = 0, footTime: Float = 0
    private var enemyTarget = House.enemy
    private var routedTarget: Cell?
    private var patrolIndex = 0
    private var players: [String:AVAudioPlayer] = [:]

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        if let url = Bundle.main.url(forResource:"VCR_OSD_MONO_1.001",withExtension:"ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        }
        setupUI(); setupIntro(); buildWorld(); loadAudio()
        showMenu("DON'T CALL\nWALEED", "Yamen’s about to make a call.\nIt’s 3:00 AM.","ENTER THE HOUSE   >")
        NotificationCenter.default.addObserver(self,selector:#selector(background),name:UIApplication.willResignActiveNotification,object:nil)
    }
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated)
        if displayLink == nil {
            let link = CADisplayLink(target:self,selector:#selector(tick(_:))); link.preferredFramesPerSecond = 60
            link.add(to:.main,forMode:.common); displayLink = link
        }
    }
    override func viewDidDisappear(_ animated:Bool) { super.viewDidDisappear(animated); displayLink?.invalidate(); displayLink = nil; players.values.forEach { $0.stop() }; stopSceneAudio(); UIApplication.shared.isIdleTimerDisabled = false }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let compact = view.bounds.height < 600
        titleLabel.font = vhs(compact ? 26 : 64)
        detailLabel.font = vhs(compact ? 12 : 17)
        menu.spacing = compact ? 4 : 22
    }
    private func vhs(_ size:CGFloat) -> UIFont { UIFont(name:"VCROSDMono",size:size) ?? .monospacedSystemFont(ofSize:size,weight:.regular) }
    private func label(_ l:UILabel,_ size:CGFloat,_ color:UIColor = .white) { l.font = vhs(size); l.textColor = color; l.numberOfLines = 0 }
    private func button(_ b:UIButton,_ text:String,_ action:Selector) {
        b.setTitle(text,for:.normal); b.tintColor = .white; b.titleLabel?.font = vhs(16)
        b.backgroundColor = UIColor(white:0.06,alpha:0.8); b.layer.borderWidth = 1; b.layer.borderColor = UIColor(white:0.7,alpha:0.35).cgColor; b.layer.cornerRadius = 3
        b.addTarget(self,action:action,for:.touchUpInside); b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(greaterThanOrEqualToConstant:50).isActive = true
    }
    private func setupUI() {
        for v in [sceneView,danger,controls,shade] { v.frame = view.bounds; v.autoresizingMask = [.flexibleWidth,.flexibleHeight]; view.addSubview(v) }
        sceneView.antialiasingMode = .multisampling2X; sceneView.preferredFramesPerSecond = 60; sceneView.rendersContinuously = false; sceneView.isUserInteractionEnabled = false
        danger.backgroundColor = .red; danger.alpha = 0; danger.isUserInteractionEnabled = false
        for v in [lookSurface,stick,status,objective,message,hint,use,lightButton,sprintButton,phoneButton,pauseButton] { v.translatesAutoresizingMaskIntoConstraints = false; controls.addSubview(v) }
        lookSurface.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(look(_:))))
        label(status,14); label(objective,14,UIColor(red:0.84,green:0.74,blue:0.5,alpha:1)); label(message,17); message.textAlignment = .center; label(hint,13); hint.textAlignment = .center
        button(use,"USE",#selector(interact)); button(lightButton,"LIGHT ON",#selector(toggleLight)); button(sprintButton,"RUN",#selector(toggleRun)); button(phoneButton,"CALL WALEED",#selector(phoneAction)); button(pauseButton,"II",#selector(pauseGame))
        sprintButton.accessibilityLabel = "Sprint"
        phoneButton.titleLabel?.adjustsFontSizeToFitWidth = true
        phoneButton.titleLabel?.minimumScaleFactor = 0.7
        let safe = controls.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            lookSurface.leadingAnchor.constraint(equalTo:controls.centerXAnchor),lookSurface.trailingAnchor.constraint(equalTo:controls.trailingAnchor),lookSurface.topAnchor.constraint(equalTo:controls.topAnchor),lookSurface.bottomAnchor.constraint(equalTo:controls.bottomAnchor),
            stick.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:30),stick.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-26),stick.widthAnchor.constraint(equalToConstant:138),stick.heightAnchor.constraint(equalTo:stick.widthAnchor),
            status.topAnchor.constraint(equalTo:safe.topAnchor,constant:16),status.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:22),
            objective.topAnchor.constraint(equalTo:status.bottomAnchor,constant:9),objective.leadingAnchor.constraint(equalTo:status.leadingAnchor),objective.widthAnchor.constraint(lessThanOrEqualTo:controls.widthAnchor,multiplier:0.7),
            pauseButton.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-20),pauseButton.topAnchor.constraint(equalTo:safe.topAnchor,constant:14),pauseButton.widthAnchor.constraint(equalToConstant:52),
            message.centerXAnchor.constraint(equalTo:controls.centerXAnchor),message.topAnchor.constraint(equalTo:objective.bottomAnchor,constant:20),message.widthAnchor.constraint(equalTo:controls.widthAnchor,multiplier:0.8),
            use.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-24),use.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-28),use.widthAnchor.constraint(equalToConstant:116),
            sprintButton.centerXAnchor.constraint(equalTo:stick.centerXAnchor),sprintButton.bottomAnchor.constraint(equalTo:stick.topAnchor,constant:-10),sprintButton.widthAnchor.constraint(equalToConstant:104),
            lightButton.trailingAnchor.constraint(equalTo:use.trailingAnchor),lightButton.bottomAnchor.constraint(equalTo:use.topAnchor,constant:-12),lightButton.widthAnchor.constraint(equalToConstant:116),
            phoneButton.trailingAnchor.constraint(equalTo:lightButton.trailingAnchor),phoneButton.bottomAnchor.constraint(equalTo:lightButton.topAnchor,constant:-12),phoneButton.widthAnchor.constraint(equalToConstant:132),
            hint.centerXAnchor.constraint(equalTo:controls.centerXAnchor),hint.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-14),hint.widthAnchor.constraint(equalTo:controls.widthAnchor,multiplier:0.35)])
        let crosshair = UILabel(); crosshair.text = "·"; crosshair.textColor = .white; crosshair.font = .systemFont(ofSize:28); crosshair.translatesAutoresizingMaskIntoConstraints = false; crosshair.isUserInteractionEnabled = false; controls.addSubview(crosshair)
        NSLayoutConstraint.activate([crosshair.centerXAnchor.constraint(equalTo:controls.centerXAnchor),crosshair.centerYAnchor.constraint(equalTo:controls.centerYAnchor)])
        shade.backgroundColor = .black
        menuArtwork.image = UIImage(named:"TitleArtwork-Empty.png")
        menuArtwork.contentMode = .scaleAspectFill; menuArtwork.clipsToBounds = true
        menuArtwork.frame = shade.bounds; menuArtwork.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        shade.addSubview(menuArtwork)
        let dim = UIView(frame:shade.bounds); dim.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.18); dim.isUserInteractionEnabled = false; shade.addSubview(dim)
        label(eyebrow,12,UIColor(white:0.65,alpha:1)); eyebrow.text = "NIGHT 01  /  THE WRONG NUMBER"
        label(clockLabel,23,UIColor(red:0.8,green:0.16,blue:0.14,alpha:1)); clockLabel.text = "AT 3 AM"
        label(footer,11,UIColor(white:0.55,alpha:1)); footer.text = "HEADPHONES RECOMMENDED  /  FIRST PLAYABLE ALPHA"
        footer.translatesAutoresizingMaskIntoConstraints = false; shade.addSubview(footer)
        NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo:shade.safeAreaLayoutGuide.leadingAnchor,constant:48),footer.bottomAnchor.constraint(equalTo:shade.safeAreaLayoutGuide.bottomAnchor,constant:-24)])
        menu.axis = .vertical; menu.spacing = 18; menu.alignment = .fill; menu.translatesAutoresizingMaskIntoConstraints = false; shade.addSubview(menu)
        titleLabel.font = vhs(64); titleLabel.textColor = UIColor(red:0.87,green:0.81,blue:0.7,alpha:1); titleLabel.numberOfLines = 0
        titleLabel.layer.shadowColor = UIColor(red:0.6,green:0.02,blue:0.02,alpha:1).cgColor
        titleLabel.layer.shadowOffset = CGSize(width:3,height:2); titleLabel.layer.shadowOpacity = 0.85; titleLabel.layer.shadowRadius = 0
        detailLabel.font = vhs(17); detailLabel.numberOfLines = 0; detailLabel.textColor = UIColor(white:0.76,alpha:1)
        button(startButton,"ENTER",#selector(menuAction)); button(soundButton,"SOUND: ON",#selector(toggleSound))
        button(helpButton,"HOW TO SURVIVE",#selector(showHelp))
        startButton.backgroundColor = UIColor(red:0.42,green:0.055,blue:0.045,alpha:0.92)
        startButton.layer.borderColor = UIColor(red:0.7,green:0.14,blue:0.1,alpha:1).cgColor
        for b in [soundButton,helpButton] { b.backgroundColor = .clear; b.layer.borderWidth = 0; b.contentHorizontalAlignment = .left }
        for v in [eyebrow,titleLabel,clockLabel,detailLabel,startButton,helpButton,soundButton] { menu.addArrangedSubview(v) }
        NSLayoutConstraint.activate([menu.leadingAnchor.constraint(equalTo:shade.safeAreaLayoutGuide.leadingAnchor,constant:48),menu.centerYAnchor.constraint(equalTo:shade.centerYAnchor),menu.widthAnchor.constraint(equalTo:shade.safeAreaLayoutGuide.widthAnchor,multiplier:0.45),menu.widthAnchor.constraint(lessThanOrEqualToConstant:560)])
    }
    private func setupIntro() {
        introOverlay.frame = view.bounds
        introOverlay.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        introOverlay.isHidden = true
        view.addSubview(introOverlay)

        label(introCaption,18)
        introCaption.textAlignment = .center
        introCaption.layer.shadowColor = UIColor.black.cgColor
        introCaption.layer.shadowOpacity = 1
        introCaption.layer.shadowRadius = 5
        introCaption.layer.shadowOffset = .zero

        label(introPhone,16,UIColor(red:0.60,green:0.83,blue:0.69,alpha:1))
        introPhone.textAlignment = .center
        introPhone.backgroundColor = UIColor(white:0.035,alpha:0.95)
        introPhone.layer.borderColor = UIColor(white:0.45,alpha:1).cgColor
        introPhone.layer.borderWidth = 1
        introPhone.layer.cornerRadius = 12
        introPhone.clipsToBounds = true

        let skip = UIButton(type:.system)
        button(skip,"SKIP",#selector(skipIntro))
        for item in [introCaption,introPhone,skip] {
            item.translatesAutoresizingMaskIntoConstraints = false
            introOverlay.addSubview(item)
        }
        let safe = introOverlay.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            introPhone.centerXAnchor.constraint(equalTo:safe.centerXAnchor),
            introPhone.centerYAnchor.constraint(equalTo:safe.centerYAnchor,constant:18),
            introPhone.widthAnchor.constraint(equalToConstant:220),
            introPhone.heightAnchor.constraint(equalToConstant:118),
            introCaption.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:18),
            introCaption.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-18),
            introCaption.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-24),
            skip.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-20),
            skip.topAnchor.constraint(equalTo:safe.topAnchor,constant:14),
            skip.widthAnchor.constraint(equalToConstant:88)
        ])
    }

    private func material(_ c:UIColor,glow:Bool = false) -> SCNMaterial { let m = SCNMaterial(); m.diffuse.contents = c; m.roughness.contents = 0.95; if glow { m.emission.contents = c }; return m }
    @discardableResult private func box(_ s:SCNVector3,_ p:SCNVector3,_ color:UIColor,parent:SCNNode? = nil,glow:Bool = false) -> SCNNode {
        let g = SCNBox(width:CGFloat(s.x),height:CGFloat(s.y),length:CGFloat(s.z),chamferRadius:0.01); g.materials = [material(color,glow:glow)]
        let n = SCNNode(geometry:g); n.position = p; (parent ?? world.rootNode).addChildNode(n); return n
    }
    private func point(_ c:Cell,y:Float = 0) -> SCNVector3 { SCNVector3((Float(c.x)+0.5)*House.tile,y,(Float(c.z)+0.5)*House.tile) }
    @discardableResult private func sphere(_ r:CGFloat,_ p:SCNVector3,_ c:UIColor,_ parent:SCNNode,glow:Bool = false) -> SCNNode {
        let g = SCNSphere(radius:r); g.segmentCount = 16; g.materials = [material(c,glow:glow)]; let n = SCNNode(geometry:g); n.position = p; parent.addChildNode(n); return n
    }
    private func buildWorld() {
        world = SCNScene(); lamps = []; fuseNodes = []; fridge = nil; world.background.contents = UIColor.black
        world.fogColor = UIColor(red:0.025,green:0.03,blue:0.035,alpha:1); world.fogStartDistance = 6; world.fogEndDistance = 22
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.color = UIColor(red:0.22,green:0.27,blue:0.36,alpha:1); ambient.light?.intensity = 240; world.rootNode.addChildNode(ambient)
        houseAmbient = ambient.light
        let colors = [UIColor(red:0.35,green:0.32,blue:0.27,alpha:1),UIColor(red:0.24,green:0.3,blue:0.28,alpha:1),UIColor(red:0.3,green:0.27,blue:0.27,alpha:1)]
        for z in House.rows.indices { for x in House.rows[z].indices {
            let p = point(Cell(x:x,z:z)), t = House.tile
            if !House.open(Cell(x:x,z:z)) {
                box(SCNVector3(t,3.3,t),SCNVector3(p.x,1.65,p.z),colors[min(2,z/6)])
                box(SCNVector3(t+0.02,0.14,t+0.02),SCNVector3(p.x,0.1,p.z),UIColor(white:0.13,alpha:1))
            } else {
                let c = (x+z)%2 == 0 ? UIColor(red:0.19,green:0.13,blue:0.09,alpha:1) : UIColor(red:0.16,green:0.11,blue:0.08,alpha:1)
                box(SCNVector3(t,0.08,t),SCNVector3(p.x,-0.04,p.z),c)
                box(SCNVector3(t,0.08,t),SCNVector3(p.x,3.34,p.z),UIColor(white:0.18,alpha:1))
                for s in [Float(-0.8),0,0.8] { box(SCNVector3(0.015,0.005,t),SCNVector3(p.x+s,0.005,p.z),UIColor(white:0.045,alpha:1)) }
            }
        } }
        let rugColors: [UIColor] = [
            UIColor(red:0.23,green:0.08,blue:0.10,alpha:1),
            UIColor(red:0.14,green:0.24,blue:0.21,alpha:1),
            UIColor(red:0.12,green:0.17,blue:0.26,alpha:1),
            UIColor(red:0.23,green:0.17,blue:0.08,alpha:1),
            UIColor(red:0.14,green:0.23,blue:0.27,alpha:1),
            UIColor(red:0.27,green:0.14,blue:0.07,alpha:1)
        ]
        for (index, room) in rooms.enumerated() {
            let p = point(room.phone)
            box(SCNVector3(2.8,0.015,3.8),SCNVector3(p.x,0.02,p.z),rugColors[index])
            furnishRoom(index, at: point(room.landmark))
            let lamp = SCNNode(); lamp.position = SCNVector3(p.x,2.95,p.z); lamp.light = SCNLight(); lamp.light?.type = .omni
            lamp.light?.color = UIColor(red:1,green:0.62,blue:0.28,alpha:1); lamp.light?.intensity = 85; lamp.light?.attenuationStartDistance = 1; lamp.light?.attenuationEndDistance = 8
            world.rootNode.addChildNode(lamp); lamps.append(lamp)
            box(SCNVector3(0.6,0.06,0.6),SCNVector3(p.x,3.16,p.z),UIColor(white:0.65,alpha:1))
        }
        for c in [Cell(x:6,z:1),Cell(x:10,z:1),Cell(x:6,z:6),Cell(x:10,z:11)] {
            let p = point(c)
            box(SCNVector3(2,0.55,1.5),SCNVector3(p.x,0.3,p.z),UIColor(red:0.15,green:0.09,blue:0.06,alpha:1))
            box(SCNVector3(1.9,0.16,1.45),SCNVector3(p.x,0.66,p.z),UIColor(red:0.33,green:0.33,blue:0.3,alpha:1))
            box(SCNVector3(0.5,0.13,1),SCNVector3(p.x-0.55,0.8,p.z),UIColor(white:0.55,alpha:1))
        }
        for c in House.closets { let p = point(c)
            box(SCNVector3(0.85,2.6,1.7),SCNVector3(p.x-0.65,1.3,p.z),UIColor(red:0.13,green:0.08,blue:0.045,alpha:1))
            box(SCNVector3(0.04,0.1,0.18),SCNVector3(p.x-0.19,1.2,p.z),.systemYellow,glow:true)
        }
        for c in House.fuses { let p = point(c)
            box(SCNVector3(1.2,0.8,0.7),SCNVector3(p.x,0.4,p.z-0.75),UIColor(white:0.15,alpha:1))
            let n = box(SCNVector3(0.18,0.32,0.18),SCNVector3(p.x,1,p.z-0.75),.systemCyan,glow:true)
            n.runAction(.repeatForever(.sequence([.moveBy(x:0,y:0.12,z:0,duration:0.8),.moveBy(x:0,y:-0.12,z:0,duration:0.8)]))); fuseNodes.append(n)
        }
        let panel = point(House.panel)
        box(SCNVector3(0.8,1.3,0.25),SCNVector3(panel.x,1.45,panel.z+0.6),UIColor(white:0.22,alpha:1))
        box(SCNVector3(0.12,0.12,0.06),SCNVector3(panel.x,1.65,panel.z+0.44),.systemRed,glow:true)
        let door = point(House.exit)
        box(SCNVector3(1.65,2.85,0.15),SCNVector3(door.x,1.43,door.z+1.08),UIColor(red:0.11,green:0.18,blue:0.17,alpha:1))
        box(SCNVector3(0.8,0.2,0.04),SCNVector3(door.x,2.7,door.z+0.97),.systemGreen,glow:true)
        enemy = SCNNode()
        enemy.position = point(House.enemy)
        world.rootNode.addChildNode(enemy)
        box(SCNVector3(0.65,1.25,0.35),SCNVector3(0,1.35,0),UIColor(white:0.04,alpha:1),parent:enemy)
        enemyLimbs.removeAll()
        for x in [Float(-0.43), 0.43] {
            let shoulder = SCNNode()
            shoulder.position = SCNVector3(x,1.9,0)
            enemy.addChildNode(shoulder)
            box(SCNVector3(0.16,1.45,0.20),SCNVector3(0,-0.61,0),UIColor(white:0.045,alpha:1),parent:shoulder)
            enemyLimbs.append(shoulder)
        }
        for x in [Float(-0.20), 0.20] {
            let hip = SCNNode()
            hip.position = SCNVector3(x,0.88,0)
            enemy.addChildNode(hip)
            box(SCNVector3(0.16,0.9,0.19),SCNVector3(0,-0.42,0),UIColor(white:0.025,alpha:1),parent:hip)
            enemyLimbs.append(hip)
        }
        let face = makeFace()
        enemyHead = face.head
        enemyEyes = face.eyes
        enemyHead.position = SCNVector3(0,2.2,0)
        enemyEyes.forEach { $0.isHidden = true }
        enemy.addChildNode(enemyHead)
        camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.fieldOfView = 76; camera.camera?.zNear = 0.06; camera.camera?.zFar = 45
        camera.camera?.vignettingIntensity = 0.8; camera.camera?.vignettingPower = 1.8
        camera.position = point(House.spawn,y:1.6); world.rootNode.addChildNode(camera)
        torch = SCNNode(); torch.light = SCNLight(); torch.light?.type = .spot; torch.light?.color = UIColor(red:0.95,green:0.91,blue:0.78,alpha:1); torch.light?.intensity = flashlightIntensity
        torch.light?.spotInnerAngle = 8
        torch.light?.spotOuterAngle = 19
        torch.light?.attenuationStartDistance = 1.4
        torch.light?.attenuationEndDistance = 11
        torch.light?.castsShadow = true
        torch.light?.shadowMapSize = CGSize(width:512,height:512)
        torch.light?.shadowRadius = 2
        camera.addChildNode(torch)
        sceneView.scene = world; sceneView.pointOfView = camera; sceneView.audioListener = camera
    }
    private func furnishRoom(_ index: Int, at p: SCNVector3) {
        let wall = p.z - 1.02
        let darkMetal = UIColor(white:0.15,alpha:1)
        let enamel = UIColor(red:0.64,green:0.69,blue:0.62,alpha:1)
        switch index {
        case 0: // Bedroom: crooked headboard, mattress and pillow.
            box(SCNVector3(1.7,1.12,0.18),SCNVector3(p.x,0.58,wall),UIColor(red:0.27,green:0.12,blue:0.08,alpha:1))
            box(SCNVector3(1.45,0.28,0.65),SCNVector3(p.x,0.36,wall+0.31),UIColor(red:0.28,green:0.09,blue:0.11,alpha:1))
            box(SCNVector3(0.58,0.14,0.29),SCNVector3(p.x+0.26,0.57,wall+0.20),UIColor(white:0.60,alpha:1))
        case 1: // Kitchen: two-door fridge with an audible compressor.
            fridge = box(SCNVector3(1.04,2.26,0.39),SCNVector3(p.x,1.13,wall+0.09),enamel)
            box(SCNVector3(1.02,0.045,0.03),SCNVector3(p.x,1.54,wall+0.29),darkMetal)
            for y in [Float(1.24), 1.77] {
                box(SCNVector3(0.07,0.24,0.08),SCNVector3(p.x-0.37,y,wall+0.32),darkMetal)
            }
            box(SCNVector3(0.05,0.04,0.02),SCNVector3(p.x+0.35,0.25,wall+0.3),.systemGreen,glow:true)
        case 2: // Lounge: an old television comes and goes in the dark.
            box(SCNVector3(1.48,0.94,0.42),SCNVector3(p.x,1.41,wall+0.07),darkMetal)
            let screen = box(SCNVector3(1.18,0.70,0.018),SCNVector3(p.x-0.04,1.43,wall+0.29),UIColor(red:0.14,green:0.43,blue:0.48,alpha:1),glow:true)
            screen.runAction(.repeatForever(.sequence([
                .fadeOpacity(to:0.18,duration:0.06), .wait(duration:0.14),
                .fadeOpacity(to:0.86,duration:0.32), .wait(duration:2.1),
                .fadeOpacity(to:0.40,duration:0.18), .wait(duration:0.47)
            ])))
        case 3: // Study: crowded shelves.
            for y in [Float(0.75), 1.37, 1.99] {
                box(SCNVector3(1.78,0.10,0.43),SCNVector3(p.x,y,wall+0.10),UIColor(red:0.26,green:0.14,blue:0.075,alpha:1))
                for i in 0..<6 {
                    let height: Float = i.isMultiple(of:2) ? 0.34 : 0.42
                    let color: UIColor = i.isMultiple(of:3) ? .systemBrown : .darkGray
                    box(SCNVector3(0.18,height,0.26),SCNVector3(p.x-0.63+Float(i)*0.25,y+0.05+height/2,wall+0.12),color)
                }
            }
        case 4: // Laundry: circular washer door.
            box(SCNVector3(1.2,1.25,0.43),SCNVector3(p.x,0.63,wall+0.11),enamel)
            let door = sphere(0.40,SCNVector3(p.x,0.58,wall+0.34),darkMetal,world.rootNode)
            door.scale.z = 0.10
            box(SCNVector3(0.25,0.055,0.02),SCNVector3(p.x+0.27,1.10,wall+0.34),.systemOrange,glow:true)
        default: // Workshop: amber tool rack and hanging spanners.
            box(SCNVector3(1.82,1.08,0.11),SCNVector3(p.x,1.58,wall),UIColor(red:0.35,green:0.16,blue:0.06,alpha:1))
            for i in 0..<5 {
                let tool = box(SCNVector3(0.08,0.40,0.07),SCNVector3(p.x-0.64+Float(i)*0.32,1.6,wall+0.10),enamel)
                tool.eulerAngles.z = i.isMultiple(of:2) ? -0.22 : 0.22
            }
        }
    }

    private func makeFace() -> (head: SCNNode, eyes: [SCNNode], jaw: SCNNode) {
        let head = SCNNode()
        let skin = UIColor(red:0.42,green:0.38,blue:0.30,alpha:1)
        let skull = sphere(0.31,SCNVector3(0,0.045,0),skin,head)
        skull.scale = SCNVector3(0.88,1.16,0.81)
        var eyes = [SCNNode]()
        for x in [Float(-0.112), 0.112] {
            let socket = sphere(0.071,SCNVector3(x,0.075,-0.23),.black,head)
            socket.scale = SCNVector3(1.18,0.81,0.38)
            let eye = sphere(0.035,SCNVector3(x,0.074,-0.258),UIColor(red:1,green:0.035,blue:0.02,alpha:1),head,glow:true)
            eye.scale = SCNVector3(1.16,0.74,0.52)
            eyes.append(eye)
            let brow = box(SCNVector3(0.16,0.033,0.047),SCNVector3(x,0.13,-0.24),.black,parent:head)
            brow.eulerAngles.z = x < 0 ? -0.22 : 0.22
        }
        let mouth = sphere(0.13,SCNVector3(0,-0.154,-0.205),.black,head)
        mouth.scale = SCNVector3(1.30,0.72,0.48)
        let jaw = SCNNode()
        jaw.position = SCNVector3(0,-0.215,-0.025)
        head.addChildNode(jaw)
        let chin = sphere(0.18,SCNVector3(0,-0.025,-0.035),skin,jaw)
        chin.scale = SCNVector3(1.06,0.52,0.85)
        for i in 0..<7 {
            let x = Float(i-3)*0.039
            let tooth = UIColor(red:0.68,green:0.64,blue:0.47,alpha:1)
            box(SCNVector3(0.030,0.048,0.025),SCNVector3(x,-0.105,-0.268),tooth,parent:head)
            box(SCNVector3(0.030,0.040,0.025),SCNVector3(x,0.036,-0.184),tooth,parent:jaw)
        }
        return (head,eyes,jaw)
    }

    @objc private func showHelp() {
        let panel = UIAlertController(title:"HOW TO SURVIVE",message:"Left thumb: move. RUN toggles sprint. Drag the right side to look.\n\nFind three cyan fuses. USE the red fuse box, then the green exit.\n\nCALL WALEED rings his phone in another room. HANG UP before he traces you. SILENCE incoming calls and break line of sight before hiding.\n\nThe flashlight recharges when off. Listen for Waleed’s burps.\n\nContains sudden sounds and jumpscares.",preferredStyle:.alert)
        panel.addAction(UIAlertAction(title:"GOT IT",style:.default))
        present(panel,animated:true)
    }
    private func stopSceneAudio() {
        world.rootNode.childNodes.filter { $0.name == "ambientBurp" }.forEach {
            $0.removeAllAudioPlayers()
            $0.removeFromParentNode()
        }
        remoteRing?.removeAllAudioPlayers()
        fridge?.removeAllAudioPlayers()
    }

    private func resumeSceneAudio() {
        guard soundEnabled else { return }
        if let fridgeHum { fridge?.addAudioPlayer(SCNAudioPlayer(source:fridgeHum)) }
        if let ringtone { remoteRing?.addAudioPlayer(SCNAudioPlayer(source:ringtone)) }
    }

    private func ambientBurp() {
        guard soundEnabled, let source = burpSources.randomElement() else { return }
        let node = SCNNode()
        node.name = "ambientBurp"
        if enemyAwake, Bool.random() {
            node.position = SCNVector3(enemy.position.x,1.4,enemy.position.z)
        } else if let room = rooms.filter({ distance(point($0.phone),camera.position) > 4 }).randomElement() {
            node.position = point(room.phone,y:1.2)
        } else {
            return
        }
        world.rootNode.addChildNode(node)
        node.addAudioPlayer(SCNAudioPlayer(source:source))
        node.runAction(.sequence([.wait(duration:3),.removeFromParentNode()]))
    }

    private func loopingSource(_ filename: String, volume: Float) -> SCNAudioSource? {
        guard let source = SCNAudioSource(fileNamed:filename) else { return nil }
        source.isPositional = true
        source.shouldStream = false
        source.loops = true
        source.volume = volume
        source.load()
        return source
    }

    private func loadAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default)
        for i in 1...3 {
            if let source = SCNAudioSource(fileNamed:"burp\(i).wav") {
                source.isPositional = true; source.shouldStream = false; source.volume = 1
                source.load(); burpSources.append(source)
            }
        }
        ringtone = loopingSource("ring.wav",volume:0.95)
        fridgeHum = loopingSource("fridge.wav",volume:0.6)
        for name in ["drone","ring","step","sting","pickup","heartbeat","blackout"] {
            if let url = Bundle.main.url(forResource:name,withExtension:"wav"),let p = try? AVAudioPlayer(contentsOf:url) { p.prepareToPlay(); players[name] = p }
        }
        for name in ["drone","ring","heartbeat"] { players[name]?.numberOfLoops = -1; players[name]?.volume = 0.35 }
    }
    private func play(_ name:String) { guard soundEnabled else { return }; players[name]?.currentTime = 0; players[name]?.play() }
    @objc private func toggleSound() { soundEnabled.toggle(); soundButton.setTitle(soundEnabled ? "SOUND: ON" : "SOUND: OFF",for:.normal); if !soundEnabled { players.values.forEach { $0.stop() }; stopSceneAudio() } }
    private func showMenu(_ title:String,_ detail:String,_ action:String) {
        titleLabel.text = title; detailLabel.text = detail; startButton.setTitle(action,for:.normal); shade.isHidden = false; controls.isHidden = true; stick.reset(); setRunning(false)
        players.values.forEach { $0.stop() }; stopSceneAudio(); sceneView.isPlaying = false
        clockLabel.isHidden = phase != .title; eyebrow.isHidden = phase != .title
        UIApplication.shared.isIdleTimerDisabled = false
    }
    @objc private func menuAction() {
        if phase == .title {
            beginIntro()
            return
        }
        if phase != .paused { resetGame() }
        beginPlaying()
    }

    private func beginPlaying() {
        phase = .playing
        introOverlay.isHidden = true
        shade.isHidden = true
        controls.isHidden = false
        sceneView.isPlaying = true
        lastTime = 0
        UIApplication.shared.isIdleTimerDisabled = true
        if soundEnabled {
            players["drone"]?.play()
            if case .incoming = phoneState { players["ring"]?.play() }
        }
        resumeSceneAudio()
    }
    private func beginIntro() {
        resetGame()
        phase = .intro
        introElapsed = 0
        introBeat = -1
        lastTime = 0
        enemy.isHidden = true
        torch.light?.intensity = 0
        houseAmbient?.intensity = 920
        lamps.forEach { $0.light?.intensity = 620 }
        shade.isHidden = true
        introOverlay.isHidden = false
        introPhone.isHidden = false
        sceneView.isPlaying = true
        UIApplication.shared.isIdleTimerDisabled = true
        play("drone")
        updateIntro(dt:0)
    }

    private func updateIntro(dt: Float) {
        introElapsed += dt
        camera.eulerAngles = SCNVector3(-0.045,0.12+min(introElapsed,4)*0.095,0)
        let cue: Int
        switch introElapsed {
        case ..<1.4: cue = 0
        case ..<3.5: cue = 1
        case ..<4.55: cue = 2
        case ..<6.9: cue = 3
        default:
            skipIntro()
            return
        }
        guard cue != introBeat else { return }
        introBeat = cue
        switch cue {
        case 0:
            introPhone.text = "3:00 AM\n\nYAMEN’S PHONE"
            introCaption.text = "Yamen opens Waleed’s contact."
        case 1:
            introPhone.text = "3:00 AM\n\nCALLING WALEED…"
            introCaption.text = "Yamen: “Pick up, Waleed.”"
            play("ring")
        case 2:
            players["ring"]?.stop()
            introPhone.text = "3:00 AM\n\nWALEED · CONNECTED"
            introCaption.text = "Yamen: “Hello?”"
        default:
            players["drone"]?.stop()
            houseAmbient?.intensity = 0
            lamps.forEach { $0.light?.intensity = 0 }
            introOverlay.backgroundColor = .black
            introPhone.isHidden = true
            introCaption.text = "The whole house goes dark."
            play("blackout")
            UIImpactFeedbackGenerator(style:.medium).impactOccurred()
        }
    }

    @objc private func skipIntro() {
        guard phase == .intro else { return }
        players["ring"]?.stop()
        players["blackout"]?.stop()
        introOverlay.backgroundColor = .clear
        enemy.isHidden = false
        camera.eulerAngles = SCNVector3Zero
        houseAmbient?.intensity = 240
        lamps.forEach { $0.light?.intensity = 0 }
        beginPlaying()
        tell("Restore the power. Find three cyan fuses.",duration:7)
    }

    private func resetGame() {
        elapsed = 0; nextBurp = 9; yaw = 0; pitch = 0; hidden = false; flashlight = true
        battery = 100; stamina = 100; collected = []; power = false; nextCall = 24
        phoneState = .idle; nextOutgoing = 0; lure = nil; remoteRing = nil
        huntUntil = 0; route = []; routeTime = 0; patrolIndex = 0; footTime = 0; gait = 0
        enemyTarget = House.enemy; routedTarget = nil; enemyAwake = false
        lastKnownPlayer = nil; searchRoute = []
        buildWorld()
        lamps.forEach { $0.light?.intensity = 0 }
        setRunning(false)
        updatePhoneButton()
        danger.alpha = 0
        lightButton.setTitle("LIGHT ON",for:.normal)
        tell("Find the cyan fuses. CALL WALEED to distract him.",duration:7)
    }

    @objc private func pauseGame() { guard phase == .playing else { return }; phase = .paused; showMenu("STAY QUIET","The house is paused.\nFind three cyan fuses, then the red fuse box.\nThe green door is your way out.\nGold handles mark hiding cupboards.","RESUME") }
    @objc private func background() {
        if phase == .intro {
            skipIntro()
        }
        pauseGame()
    }

    @objc private func toggleRun() {
        guard phase == .playing, !hidden, stamina > 2 else { return }
        setRunning(!running)
    }

    private func setRunning(_ enabled: Bool) {
        running = enabled
        sprintButton.setTitle(enabled ? "RUN ON" : "RUN",for:.normal)
        sprintButton.backgroundColor = enabled ? UIColor(red:0.34,green:0.11,blue:0.08,alpha:0.9) : UIColor(white:0.06,alpha:0.8)
        sprintButton.accessibilityValue = enabled ? "On" : "Off"
    }

    @objc private func toggleLight() { guard phase == .playing,!hidden else { return }; flashlight.toggle(); if battery < 1 { flashlight = false }; lightButton.setTitle(flashlight ? "LIGHT ON" : "LIGHT OFF",for:.normal) }

    @objc private func phoneAction() {
        guard phase == .playing else { return }
        switch phoneState {
        case .idle:
            guard elapsed >= nextOutgoing else { return }
            guard let room = rooms.min(by:{
                distance(point($0.phone),enemy.position) < distance(point($1.phone),enemy.position)
            }) else { return }
            phoneState = .outgoing(started:elapsed)
            nextCall = max(nextCall,elapsed+17)
            lure = (target:room.phone,until:elapsed+10)
            let node = SCNNode()
            node.position = point(room.phone,y:1.10)
            world.rootNode.addChildNode(node)
            remoteRing = node
            if soundEnabled, let ringtone { node.addAudioPlayer(SCNAudioPlayer(source:ringtone)) }
            tell("Ringing in the \(room.name). Hang up before he traces you.",duration:4)
        case .incoming:
            endCall()
            tell("Incoming call silenced.")
        case .outgoing:
            endCall()
            tell("You hung up.")
        }
        updatePhoneButton()
    }

    private func endCall() {
        if case .outgoing = phoneState { nextOutgoing = elapsed+12 }
        phoneState = .idle
        players["ring"]?.stop()
        remoteRing?.removeAllAudioPlayers()
        remoteRing?.removeFromParentNode()
        remoteRing = nil
    }

    private func updatePhoneButton() {
        switch phoneState {
        case .idle:
            let ready = elapsed >= nextOutgoing
            phoneButton.isEnabled = ready
            phoneButton.setTitle(ready ? "CALL WALEED" : "NO SIGNAL",for:.normal)
        case .incoming:
            phoneButton.isEnabled = true
            phoneButton.setTitle("SILENCE",for:.normal)
        case .outgoing:
            phoneButton.isEnabled = true
            phoneButton.setTitle("HANG UP",for:.normal)
        }
        phoneButton.alpha = phoneButton.isEnabled ? 1 : 0.62
    }

    private func updatePhone() -> Bool {
        defer { updatePhoneButton() }
        switch phoneState {
        case .idle:
            if elapsed >= nextCall {
                phoneState = .incoming(until:elapsed+9)
                nextCall = elapsed+Float.random(in:35...52)
                tell("WALEED IS CALLING. Silence your phone!",duration:7)
                play("ring")
            }
        case .incoming(let until):
            if elapsed >= until { endCall() }
        case .outgoing(let started):
            if elapsed-started >= 4 {
                endCall()
                lure = nil
                tell("He traced the call. Move.",duration:5)
                return true
            }
        }
        return false
    }

    @objc private func look(_ g:UIPanGestureRecognizer) {
        let d = g.translation(in:lookSurface); g.setTranslation(.zero,in:lookSurface); guard phase == .playing,!hidden else { return }
        yaw -= Float(d.x)*0.005; pitch = min(0.9,max(-0.9,pitch-Float(d.y)*0.004))
    }
    private func distance(_ a:SCNVector3,_ b:SCNVector3) -> Float { hypot(a.x-b.x,a.z-b.z) }
    private func near(_ c:Cell,range:Float = 2.6) -> Bool { let p = point(c); return distance(camera.position,p) < range && House.visible(camera.position.x,camera.position.z,p.x,p.z) }
    private func tell(_ text:String,duration:Float = 4) { message.text = text; messageUntil = elapsed+duration }
    @objc private func interact() {
        guard phase == .playing else { return }
        if hidden { hidden = false; tell("You step out. Listen before moving."); return }
        for i in House.fuses.indices where !collected.contains(i) && near(House.fuses[i]) { collected.insert(i); fuseNodes[i].isHidden = true; play("pickup"); tell("Fuse \(collected.count) / 3 collected."); return }
        if near(House.panel) {
            if collected.count == 3 && !power { power = true; lamps.forEach { $0.light?.intensity = 380 }; play("pickup"); tell("Power restored. Get to the green exit door!",duration:6) }
            else { tell(power ? "The power is already on." : "Fuse box: \(3-collected.count) more fuses needed.") }; return
        }
        if near(House.exit) { if power { finish(escaped:true) } else { tell("The electric lock has no power.") }; return }
        if House.closets.contains(where:{ near($0,range:2) }) {
            if huntUntil > elapsed && seesPlayer(distance(camera.position,enemy.position)) { tell("He saw you. Lose him before hiding!"); return }
            hidden = true; setRunning(false); flashlight = false; lightButton.setTitle("LIGHT OFF",for:.normal); stick.reset(); tell("Hidden. Keep quiet. USE to leave.",duration:8); return
        }
        tell("Nothing within reach. Try a cyan fuse or a gold handle.")
    }
    private func finish(escaped: Bool) {
        phase = escaped ? .escaped : .caught
        if escaped {
            showMenu("YOU GOT OUT.","The line is dead.\nThis time, leave it that way.\n\nFirst night complete.","PLAY AGAIN")
            return
        }

        endCall()
        stopSceneAudio()
        players.values.forEach { $0.stop() }
        controls.isHidden = true
        danger.alpha = 0

        let scareScene = SCNScene()
        scareScene.background.contents = UIColor.black
        let scareCamera = SCNNode()
        scareCamera.camera = SCNCamera()
        scareCamera.camera?.fieldOfView = 55
        scareCamera.camera?.zNear = 0.035
        scareScene.rootNode.addChildNode(scareCamera)

        let (head, _, jaw) = makeFace()
        head.position = SCNVector3(0,-0.06,-3.0)
        head.eulerAngles = SCNVector3(-0.14,.pi,-0.11)
        scareScene.rootNode.addChildNode(head)

        let upLight = SCNNode()
        upLight.position = SCNVector3(0.23,-0.44,-0.32)
        upLight.light = SCNLight()
        upLight.light?.type = .omni
        upLight.light?.color = UIColor(red:1,green:0.28,blue:0.19,alpha:1)
        upLight.light?.intensity = 120
        scareScene.rootNode.addChildNode(upLight)

        sceneView.scene = scareScene
        sceneView.pointOfView = scareCamera
        sceneView.audioListener = scareCamera
        let lunge = SCNAction.move(to:SCNVector3(0,-0.065,-0.78),duration:0.16)
        lunge.timingMode = .easeIn
        let twist = SCNAction.rotateTo(x:0.11,y:.pi,z:0.16,duration:0.16,usesShortestUnitArc:true)
        head.runAction(.sequence([
            .wait(duration:0.08),
            .group([lunge,twist]),
            .moveBy(x:-0.037,y:0.025,z:0.028,duration:0.055),
            .moveBy(x:0.060,y:-0.035,z:-0.03,duration:0.085)
        ]))
        if !UIAccessibility.isReduceMotionEnabled {
            scareCamera.runAction(.sequence([
                .wait(duration:0.19),
                .moveBy(x:0.06,y:0.043,z:0,duration:0.043),
                .moveBy(x:-0.103,y:-0.063,z:0,duration:0.052),
                .moveBy(x:0.043,y:0.020,z:0,duration:0.068)
            ]))
        }
        jaw.runAction(.sequence([
            .wait(duration:0.08),
            .group([.rotateBy(x:-0.88,y:0,z:0,duration:0.15),.moveBy(x:0,y:-0.17,z:0,duration:0.15)])
        ]))
        play("sting")
        UIImpactFeedbackGenerator(style:.heavy).impactOccurred(intensity:1)

        DispatchQueue.main.asyncAfter(deadline:.now()+1.04) { [weak self] in
            guard let self, self.phase == .caught else { return }
            self.showMenu("HE FOUND YOU.","Don’t call Waleed at 3 AM.\n\nWalk to stay quiet. Silence incoming calls.\nHide by a gold handle.\nBreak his line of sight before hiding.","TRY AGAIN")
        }
    }

    private func seesPlayer(_ distance: Float) -> Bool {
        guard !hidden, distance < (flashlight ? 18 : 11) else { return false }
        let p = camera.position, e = enemy.position
        return House.visible(e.x,e.z,p.x,p.z)
    }

    private func moveEnemy(toward destination: SCNVector3, speed: Float, dt: Float) -> Float {
        let position = enemy.position
        let remaining = distance(position,destination)
        guard remaining > 0.001 else { return 0 }
        let step = min(remaining,speed*dt)
        let vx = (destination.x-position.x)/remaining
        let vz = (destination.z-position.z)/remaining
        let nx = position.x+vx*step
        let nz = position.z+vz*step
        guard House.walkable(nx,nz,radius:0.18) else { return 0 }
        enemy.position = SCNVector3(nx,position.y,nz)
        enemy.eulerAngles.y = atan2(-vx,-vz)
        return step
    }

    private func updateEnemy(dt: Float, sprint: Bool, moving: Bool, traced: Bool) -> Bool {
        let p = camera.position
        let cell = House.cell(p.x,p.z)
        let separation = distance(p,enemy.position)
        let sight = seesPlayer(separation)
        let incoming: Bool
        if case .incoming = phoneState { incoming = true } else { incoming = false }
        let heardFootsteps = !hidden && moving && separation < (sprint ? 16 : 4.6)
        let detected = sight || heardFootsteps || (incoming && separation < 22) || traced

        if elapsed > 13 || lure != nil || traced { enemyAwake = true }
        if enemyAwake, detected {
            huntUntil = elapsed+12
            lastKnownPlayer = cell
            searchRoute.removeAll()
            enemyTarget = cell
            lure = nil
        }
        let hunting = elapsed < huntUntil
        if enemyAwake {
            if hunting {
                updateSearch(detected:detected)
            } else {
                lastKnownPlayer = nil
                searchRoute.removeAll()
                if let lure, elapsed < lure.until {
                    enemyTarget = lure.target
                } else {
                    lure = nil
                    if reached(enemyTarget), enemyTarget == House.patrol[patrolIndex] {
                        patrolIndex = (patrolIndex+1)%House.patrol.count
                    }
                    enemyTarget = House.patrol[patrolIndex]
                }
            }

            let speed: Float = hunting ? (power ? 4.65 : 4.35) : 2.35
            let moved = advanceEnemy(visiblePlayer:sight ? p : nil,speed:speed,dt:dt)
            gait += moved*7
            let stride = moved > 0.001 ? sin(gait)*(hunting ? 0.62 : 0.40) : 0
            enemyLimbs[0].eulerAngles.x = stride
            enemyLimbs[1].eulerAngles.x = -stride
            enemyLimbs[2].eulerAngles.x = -stride
            enemyLimbs[3].eulerAngles.x = stride
            enemy.position.y = moved > 0.001 ? abs(sin(gait))*0.044 : 0
        }

        let e = enemy.position
        let dist = distance(e,p)
        let close = !hidden && dist < 5.8 && House.visible(e.x,e.z,p.x,p.z)
        enemyEyes.forEach { $0.isHidden = !close }
        if close {
            let facing = atan2(e.x-p.x,e.z-p.z)-enemy.eulerAngles.y
            enemyHead.eulerAngles.y = atan2(sin(facing),cos(facing))
        } else {
            enemyHead.eulerAngles.y = 0
        }
        if enemyAwake && !hidden && House.canCatch(enemyX:e.x,enemyZ:e.z,playerX:p.x,playerZ:p.z) {
            finish(escaped:false)
            return false
        }

        danger.alpha = hunting ? CGFloat(0.06+max(0,1-dist/12)*0.14*(0.6+sin(elapsed*8)*0.4)) : 0
        if hunting && soundEnabled {
            if players["heartbeat"]?.isPlaying == false { players["heartbeat"]?.play() }
        } else {
            players["heartbeat"]?.stop()
        }
        return true
    }

    private func reached(_ cell: Cell) -> Bool {
        House.reachedWaypoint(distance(enemy.position,point(cell)))
    }

    private func updateSearch(detected: Bool) {
        guard !detected, reached(enemyTarget) else { return }
        if let lastKnownPlayer {
            searchRoute = House.searchCells(near:lastKnownPlayer)
            self.lastKnownPlayer = nil
        }
        if !searchRoute.isEmpty {
            enemyTarget = searchRoute.removeFirst()
        } else {
            huntUntil = elapsed
        }
    }

    private func advanceEnemy(visiblePlayer: SCNVector3?, speed: Float, dt: Float) -> Float {
        let e = enemy.position
        if let player = visiblePlayer, House.walkableBetween(e.x,e.z,player.x,player.z,radius:0.18) {
            route.removeAll()
            routedTarget = nil
            routeTime = elapsed
            return moveEnemy(toward:player,speed:speed,dt:dt)
        }
        if routedTarget != enemyTarget, elapsed >= routeTime {
            // Finish the committed segment before turning, so corners stay clear.
            let origin = route.first ?? House.cell(e.x,e.z)
            let anchor = route.first != nil || !reached(origin) ? [origin] : []
            route = anchor + House.path(from:origin,to:enemyTarget)
            routedTarget = enemyTarget
            routeTime = elapsed+0.21
        }
        guard let waypoint = route.first else { return 0 }
        let moved = moveEnemy(toward:point(waypoint),speed:speed,dt:dt)
        if reached(waypoint) { route.removeFirst() }
        return moved
    }

    @objc private func tick(_ link:CADisplayLink) {
        guard phase == .playing || phase == .intro else { lastTime = 0; return }
        guard lastTime != 0 else { lastTime = link.timestamp; return }
        let dt = min(Float(link.timestamp-lastTime),0.05)
        lastTime = link.timestamp
        if phase == .intro {
            updateIntro(dt:dt)
            return
        }
        elapsed += dt
        if elapsed > nextBurp { ambientBurp(); nextBurp = elapsed+Float.random(in:10...24) }
        if elapsed > messageUntil { message.text = "" }
        let moving = !hidden && hypot(stick.vector.x,stick.vector.y) > 0.12
        let sprint = running && moving && stamina > 2
        stamina = min(100,max(0,stamina+(sprint ? -22 : 12)*dt))
        if running && stamina <= 2 { setRunning(false) }
        if !hidden {
            let speed:Float = sprint ? 4 : 2.2, forward = -Float(stick.vector.y), strafe = Float(stick.vector.x)
            let dx = (-sin(yaw)*forward+cos(yaw)*strafe)*speed*dt, dz = (-cos(yaw)*forward-sin(yaw)*strafe)*speed*dt
            var p = camera.position
            if House.walkable(p.x+dx,p.z) { p.x += dx }; if House.walkable(p.x,p.z+dz) { p.z += dz }
            p.y = 1.6+(moving ? sin(elapsed*(sprint ? 14 : 9))*0.035 : 0); camera.position = p; camera.eulerAngles = SCNVector3(pitch,yaw,0)
            if moving && elapsed > footTime { play("step"); footTime = elapsed+(sprint ? 0.3 : 0.55) }
        }
        battery = min(100,max(0,battery+(flashlight && !hidden ? -0.65 : 1.25)*dt))
        if battery <= 0 { flashlight = false; lightButton.setTitle("LIGHT OFF",for:.normal) }
        torch.light?.intensity = flashlight && !hidden ? flashlightIntensity : 0
        camera.camera?.exposureOffset = hidden ? -2 : 0
        let traced = updatePhone()
        guard updateEnemy(dt:dt,sprint:sprint,moving:moving,traced:traced) else { return }
        status.text = "3:\(String(format:"%02d",min(59,Int(elapsed/12)))) AM   LIGHT \(Int(battery))%   BREATH \(Int(stamina))%"
        objective.text = power ? "POWER ON · REACH THE GREEN EXIT" : "FUSES \(collected.count)/3 · \(collected.count == 3 ? "FIND THE RED FUSE BOX" : "SEARCH THE HOUSE")"
        if hidden { hint.text = "HIDDEN · USE TO LEAVE" }
        else if House.fuses.indices.contains(where:{ !collected.contains($0) && near(House.fuses[$0]) }) { hint.text = "USE · TAKE FUSE" }
        else if near(House.panel) { hint.text = "USE · FUSE BOX" } else if near(House.exit) { hint.text = "USE · EXIT" }
        else if House.closets.contains(where:{ near($0,range:2) }) { hint.text = "USE · HIDE" } else { hint.text = elapsed < huntUntil ? "HE’S LOOKING FOR YOU" : "DRAG RIGHT SIDE TO LOOK" }
    }
}
