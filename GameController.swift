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

    private let flashlightIntensity: CGFloat = 1100
    private var house = House()
    private enum RoomKind: String {
        case bedroom = "BEDROOM", kitchen = "KITCHEN", lounge = "LOUNGE", study = "STUDY"
        case laundry = "LAUNDRY", workshop = "WORKSHOP", dining = "DINING ROOM"
        case guest = "GUEST ROOM", sunroom = "SUNROOM"

        var rugColor: UIColor {
            switch self {
            case .bedroom: UIColor(red:0.23,green:0.08,blue:0.10,alpha:1)
            case .kitchen: UIColor(red:0.14,green:0.24,blue:0.21,alpha:1)
            case .lounge: UIColor(red:0.12,green:0.17,blue:0.26,alpha:1)
            case .study: UIColor(red:0.23,green:0.17,blue:0.08,alpha:1)
            case .laundry: UIColor(red:0.14,green:0.23,blue:0.27,alpha:1)
            case .workshop: UIColor(red:0.27,green:0.14,blue:0.07,alpha:1)
            case .dining: UIColor(red:0.29,green:0.18,blue:0.16,alpha:1)
            case .guest: UIColor(red:0.16,green:0.24,blue:0.20,alpha:1)
            case .sunroom: UIColor(red:0.20,green:0.23,blue:0.30,alpha:1)
            }
        }
    }

    private let rooms: [(kind: RoomKind, landmark: Cell, phone: Cell)] = [
        (.bedroom, Cell(x:4,z:1), Cell(x:4,z:2)),
        (.kitchen, Cell(x:12,z:1), Cell(x:12,z:2)),
        (.lounge, Cell(x:4,z:6), Cell(x:4,z:7)),
        (.study, Cell(x:12,z:6), Cell(x:12,z:7)),
        (.laundry, Cell(x:4,z:11), Cell(x:4,z:12)),
        (.workshop, Cell(x:12,z:11), Cell(x:12,z:12)),
        (.dining, Cell(x:21,z:1), Cell(x:21,z:2)),
        (.guest, Cell(x:21,z:6), Cell(x:21,z:7)),
        (.sunroom, Cell(x:21,z:11), Cell(x:21,z:12))
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
    private let shelter = Cell(x:24,z:6)
    private let notes: [(cell:Cell, text:String)] = [
        (Cell(x:4,z:14),"Waleed’s note: “It knocks three times. If it answers, leave the phone alone.”"),
        (Cell(x:21,z:2),"Yamen’s message: “The boards by the dining room set it off. There’s a steel shelter in the guest room.”"),
        (Cell(x:22,z:12),"Service log: “Phone line passes through the back wing. Restore the breaker, then get out.”")
    ]
    private let traps = [Cell(x:17,z:3),Cell(x:21,z:8),Cell(x:18,z:13)]
    private let pipeCells = [Cell(x:4,z:11),Cell(x:19,z:2),Cell(x:24,z:7),Cell(x:22,z:13)]
    private var pipeSources = [SCNAudioSource]()
    private var nextPipe: Float = 7
    private var nextTrap: Float = 0
    private var lastTrap: Cell?
    private var readNotes = Set<Cell>()
    private var noteNodes = [SCNNode]()
    private var thermalScreens = [SCNNode]()
    private var lightPanels = [SCNNode]()
    private var lookRoll: Float = 0
    private var stepPhase: Float = 0
    private var movement = SIMD2<Float>.zero
    private var enemyBend = [SCNNode]()
    private var houseAmbient: SCNLight?
    private let introOverlay = UIView()
    private let introCaption = UILabel()
    private let introPhone = IntroPhoneView(frame:.zero)
    private var introBeat = -1
    private var introElapsed: Float = 0
    private var phoneState = PhoneState.idle
    private var nextOutgoing: Float = 0
    private var lure: (target: Cell, until: Float)?
    private var ringtone: SCNAudioSource?
    private var remoteRing: SCNNode?
    private var fridge: SCNNode?
    private var fridgeHum: SCNAudioSource?
    private let phoneVoice = AVSpeechSynthesizer()
    private var innerDoors = [(pivot: SCNNode, center: SCNVector3)]()
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

        let skip = UIButton(type:.system)
        button(skip,"SKIP",#selector(skipIntro))
        for item in [introCaption,introPhone,skip] {
            item.translatesAutoresizingMaskIntoConstraints = false
            introOverlay.addSubview(item)
        }
        let safe = introOverlay.safeAreaLayoutGuide
        let phoneWidth = introPhone.widthAnchor.constraint(equalTo:safe.heightAnchor,multiplier:0.39)
        phoneWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            introPhone.centerXAnchor.constraint(equalTo:safe.centerXAnchor,constant:40),
            introPhone.centerYAnchor.constraint(equalTo:safe.centerYAnchor,constant:18),
            phoneWidth,
            introPhone.widthAnchor.constraint(lessThanOrEqualToConstant:218),
            introPhone.heightAnchor.constraint(equalTo:introPhone.widthAnchor,multiplier:336.0/180.0),
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
        world = SCNScene(); lamps = []; lightPanels = []; thermalScreens = []; fuseNodes = []; fridge = nil; world.background.contents = UIColor.black
        world.fogColor = UIColor(red:0.025,green:0.03,blue:0.035,alpha:1); world.fogStartDistance = 12; world.fogEndDistance = 35
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.color = UIColor(red:0.22,green:0.27,blue:0.36,alpha:1); ambient.light?.intensity = 240; world.rootNode.addChildNode(ambient)
        houseAmbient = ambient.light
        buildSurfaces()
        buildDoors()
        addRoomLamp(at:point(Cell(x:3,z:13)))
        box(SCNVector3(1.68,0.45,0.73),point(Cell(x:4,z:13),y:0.30),UIColor(red:0.30,green:0.22,blue:0.16,alpha:1))
        box(SCNVector3(1.62,0.13,0.69),point(Cell(x:4,z:13),y:0.58),UIColor(red:0.37,green:0.45,blue:0.39,alpha:1))
        box(SCNVector3(1.62,0.51,0.16),SCNVector3(point(Cell(x:4,z:13)).x,0.68,point(Cell(x:4,z:13)).z-0.31),UIColor(red:0.37,green:0.45,blue:0.39,alpha:1))
        for room in rooms {
            let p = point(room.phone)
            box(SCNVector3(2.8,0.015,3.8),SCNVector3(p.x,0.02,p.z),room.kind.rugColor)
            furnishRoom(room.kind, at: point(room.landmark))
            addRoomLamp(at:p)
        }
        buildSurvivalProps()
        for c in House.closets { let p = point(c)
            box(SCNVector3(0.85,2.6,1.7),SCNVector3(p.x-0.65,1.3,p.z),UIColor(red:0.13,green:0.08,blue:0.045,alpha:1))
            box(SCNVector3(0.04,0.1,0.18),SCNVector3(p.x-0.19,1.2,p.z),.systemYellow,glow:true)
        }
        for cell in house.fuses {
            let p = point(cell)
            sideTable(at:p)
            fuseNodes.append(makeFuse(at:SCNVector3(p.x,0.806,p.z-0.18)))
        }
        let panel = point(House.panel)
        box(SCNVector3(0.89,1.24,0.28),SCNVector3(panel.x,1.45,panel.z+0.6),UIColor(white:0.21,alpha:1))
        box(SCNVector3(0.78,0.95,0.05),SCNVector3(panel.x,1.40,panel.z+0.445),.darkGray)
        for x in [Float(-0.24),0,0.24] {
            box(SCNVector3(0.16,0.38,0.035),SCNVector3(panel.x+x,1.36,panel.z+0.408),.black)
            for y in [Float(1.22),1.50] {
                box(SCNVector3(0.095,0.047,0.041),SCNVector3(panel.x+x,y,panel.z+0.388),UIColor(red:0.73,green:0.51,blue:0.23,alpha:1))
            }
        }
        box(SCNVector3(0.12,0.12,0.06),SCNVector3(panel.x,1.83,panel.z+0.44),.systemRed,glow:true)
        let door = point(House.exit)
        box(SCNVector3(1.65,2.85,0.15),SCNVector3(door.x,1.43,door.z+1.08),UIColor(red:0.11,green:0.18,blue:0.17,alpha:1))
        box(SCNVector3(0.8,0.2,0.04),SCNVector3(door.x,2.7,door.z+0.97),.systemGreen,glow:true)
        enemy = SCNNode()
        enemy.position = point(House.enemy)
        world.rootNode.addChildNode(enemy)
        let coat = UIColor(red:0.115,green:0.127,blue:0.115,alpha:1)
        let cloth = UIColor(red:0.095,green:0.088,blue:0.082,alpha:1)
        let skin = UIColor(red:0.37,green:0.29,blue:0.24,alpha:1)
        let torso = sphere(0.44,SCNVector3(0,1.44,0),coat,enemy)
        torso.scale = SCNVector3(0.81,1.34,0.54)
        let collar = sphere(0.23,SCNVector3(0,1.95,0.015),cloth,enemy)
        collar.scale = SCNVector3(1.46,0.69,1.15)
        box(SCNVector3(0.027,0.72,0.02),SCNVector3(0.04,1.42,-0.235),.darkGray,parent:enemy)
        enemyLimbs.removeAll()
        enemyBend.removeAll()
        for x in [Float(-0.37),0.37] {
            let shoulder = joint(root:enemy,at:SCNVector3(x,1.83,0))
            roundedLimb(at:SCNVector3(0,-0.21,0),length:0.46,radius:0.105,color:coat,parent:shoulder)
            let elbow = joint(root:shoulder,at:SCNVector3(0,-0.43,0))
            roundedLimb(at:SCNVector3(0,-0.19,0),length:0.43,radius:0.076,color:coat,parent:elbow)
            sphere(0.075,SCNVector3(0,-0.43,-0.018),skin,elbow).scale = SCNVector3(0.75,1.31,0.66)
        }
        for x in [Float(-0.17),0.17] {
            let hip = joint(root:enemy,at:SCNVector3(x,0.98,0))
            roundedLimb(at:SCNVector3(0,-0.22,0),length:0.49,radius:0.104,color:cloth,parent:hip)
            let knee = joint(root:hip,at:SCNVector3(0,-0.45,0))
            roundedLimb(at:SCNVector3(0,-0.20,0),length:0.44,radius:0.083,color:cloth,parent:knee)
            box(SCNVector3(0.18,0.13,0.30),SCNVector3(0,-0.47,-0.051),.black,parent:knee)
        }
        let face = makeFace()
        enemyHead = face.head
        enemyEyes = face.eyes
        enemyHead.position = SCNVector3(0,2.2,0)
        enemyEyes.forEach { $0.isHidden = true }
        enemy.addChildNode(enemyHead)
        camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.fieldOfView = 76; camera.camera?.zNear = 0.06; camera.camera?.zFar = 58
        camera.camera?.vignettingIntensity = 0.8; camera.camera?.vignettingPower = 1.8
        camera.position = point(House.spawn,y:1.6); world.rootNode.addChildNode(camera)
        torch = SCNNode(); torch.light = SCNLight(); torch.light?.type = .spot; torch.light?.color = UIColor(red:0.95,green:0.91,blue:0.78,alpha:1); torch.light?.intensity = flashlightIntensity
        torch.light?.spotInnerAngle = 24
        torch.light?.spotOuterAngle = 65
        torch.light?.attenuationStartDistance = 1.4
        torch.light?.attenuationEndDistance = 18
        torch.light?.castsShadow = true
        torch.light?.shadowMapSize = CGSize(width:512,height:512)
        torch.light?.shadowRadius = 2
        camera.addChildNode(torch)
        sceneView.scene = world; sceneView.pointOfView = camera; sceneView.audioListener = camera
    }
    private func joint(root:SCNNode,at position:SCNVector3) -> SCNNode {
        let node = SCNNode()
        node.position = position
        root.addChildNode(node)
        if root === enemy { enemyLimbs.append(node) } else { enemyBend.append(node) }
        return node
    }

    private func roundedLimb(at position:SCNVector3,length:CGFloat,radius:CGFloat,color:UIColor,parent:SCNNode) {
        let geometry = SCNCapsule(capRadius:radius,height:length)
        geometry.radialSegmentCount = 12
        geometry.materials = [material(color)]
        let node = SCNNode(geometry:geometry)
        node.position = position
        parent.addChildNode(node)
    }

    private func addRoomLamp(at p:SCNVector3) {
        let lamp = SCNNode()
        lamp.position = SCNVector3(p.x,2.99,p.z)
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red:1,green:0.86,blue:0.69,alpha:1)
        light.intensity = 0
        light.attenuationStartDistance = 2
        light.attenuationEndDistance = 10
        lamp.light = light
        world.rootNode.addChildNode(lamp)
        lamps.append(lamp)
        box(SCNVector3(0.78,0.12,0.53),SCNVector3(p.x,3.23,p.z),.darkGray)
        let panel = box(SCNVector3(0.66,0.045,0.44),SCNVector3(p.x,3.15,p.z),.white,glow:true)
        lightPanels.append(panel)
    }

    private func setRoomPower(_ intensity:CGFloat) {
        lamps.forEach { $0.light?.intensity = intensity }
        lightPanels.forEach { $0.isHidden = intensity <= 0 }
        thermalScreens.forEach { $0.isHidden = intensity <= 0 }
    }

    private func buildSurfaces() {
        let wall = material(UIColor(white:0.73,alpha:1))
        let hardwood = material(UIColor(red:0.39,green:0.25,blue:0.17,alpha:1))
        let ceiling = material(UIColor(white:0.37,alpha:1))
        let trim = material(UIColor(red:0.22,green:0.14,blue:0.10,alpha:1))
        let plaster = UIGraphicsImageRenderer(size:CGSize(width:128,height:128)).image { drawing in
            let g = drawing.cgContext
            g.setFillColor(UIColor(red:0.55,green:0.56,blue:0.50,alpha:1).cgColor)
            g.fill(CGRect(x:0,y:0,width:128,height:128))
            for i in 0..<280 {
                let x = (i*73+i/4)%128, y = (i*29+i/7)%128
                g.setFillColor(UIColor(white:i.isMultiple(of:3) ? 0.2 : 0.8,alpha:0.11).cgColor)
                g.fill(CGRect(x:x,y:y,width:3+(i%5),height:1+(i%3)))
            }
        }
        let wood = UIGraphicsImageRenderer(size:CGSize(width:128,height:128)).image { drawing in
            let g = drawing.cgContext
            let tones = [0.32,0.39,0.34,0.42,0.37,0.31,0.36,0.40]
            for (index,tone) in tones.enumerated() {
                let t = CGFloat(tone)
                g.setFillColor(UIColor(red:t+0.13,green:t,blue:t-0.08,alpha:1).cgColor)
                g.fill(CGRect(x:0,y:index*16,width:128,height:16))
                g.setFillColor(UIColor(white:0.12,alpha:0.72).cgColor)
                g.fill(CGRect(x:0,y:index*16,width:128,height:1))
                g.fill(CGRect(x:(index*39)%128,y:index*16,width:1,height:16))
            }
            for i in 0..<95 {
                g.setFillColor(UIColor(white:i.isMultiple(of:3) ? 0.08 : 0.73,alpha:0.13).cgColor)
                g.fill(CGRect(x:(i*51)%128,y:(i*17)%128,width:7+(i%20),height:1))
            }
        }
        wall.diffuse.contents = plaster
        hardwood.diffuse.contents = wood
        for material in [wall,hardwood] {
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.mipFilter = .linear
        }
        func strip(_ material:SCNMaterial,_ width:Float,_ height:Float,_ depth:Float,_ x:Float,_ y:Float,_ z:Float,_ tiles:Int) {
            let mesh = SCNBox(width:CGFloat(width),height:CGFloat(height),length:CGFloat(depth),chamferRadius:0)
            let surfaces = material.copy() as! SCNMaterial
            surfaces.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(tiles),1,1)
            mesh.materials = [surfaces]
            let node = SCNNode(geometry:mesh)
            node.position = SCNVector3(x,y,z)
            world.rootNode.addChildNode(node)
        }
        for (z,row) in house.rows.enumerated() {
            var start = 0
            while start < row.count {
                let solid = row[start] == "#"
                var end = start+1
                while end < row.count && (row[end] == "#") == solid { end += 1 }
                let t = House.tile, width = Float(end-start)*t
                let x = Float(start)*t+width/2, y = (Float(z)+0.5)*t
                if solid {
                    strip(wall,width,3.3,t,x,1.65,y,end-start)
                    strip(trim,width+0.02,0.14,t+0.025,x,0.10,y,1)
                } else {
                    strip(hardwood,width,0.08,t,x,-0.04,y,end-start)
                    strip(ceiling,width,0.08,t,x,3.34,y,1)
                }
                start = end
            }
        }
    }

    private func buildDoors() {
        innerDoors.removeAll()
        let painted = UIColor(red:0.61,green:0.54,blue:0.43,alpha:1)
        let wood = UIColor(red:0.34,green:0.19,blue:0.11,alpha:1)
        let raised = UIColor(red:0.42,green:0.25,blue:0.15,alpha:1)
        let brass = UIColor(red:0.71,green:0.53,blue:0.26,alpha:1)
        for doorway in house.doorways {
            let frame = SCNNode()
            frame.position = point(doorway.cell)
            frame.eulerAngles.y = doorway.rotated ? .pi/2 : 0
            world.rootNode.addChildNode(frame)
            for x in [Float(-0.89),0.89] {
                box(SCNVector3(0.26,2.60,0.32),SCNVector3(x,1.30,0),painted,parent:frame)
            }
            box(SCNVector3(2.04,0.21,0.32),SCNVector3(0,2.52,0),painted,parent:frame)
            box(SCNVector3(2.04,0.72,0.25),SCNVector3(0,2.97,0),painted,parent:frame)
            box(SCNVector3(1.58,0.024,0.32),SCNVector3(0,0.012,0),wood,parent:frame)
            let hinge = SCNNode()
            hinge.position = SCNVector3(-0.77,0,0)
            frame.addChildNode(hinge)
            box(SCNVector3(1.50,2.37,0.09),SCNVector3(0.75,1.20,0),wood,parent:hinge)
            for side in [Float(-1),1] {
                for y in [Float(0.56),1.73] {
                    box(SCNVector3(1.14,0.87,0.031),SCNVector3(0.75,y,0.057*side),raised,parent:hinge)
                    box(SCNVector3(0.98,0.73,0.017),SCNVector3(0.75,y,0.078*side),wood,parent:hinge)
                }
                box(SCNVector3(0.068,0.18,0.016),SCNVector3(1.34,1.05,0.058*side),brass,parent:hinge)
                let knob = sphere(0.045,SCNVector3(1.34,1.07,0.097*side),brass,hinge)
                knob.scale.z = 0.72
            }
            innerDoors.append((hinge,frame.position))
        }
    }

    private func moveDoors(dt:Float) {
        for door in innerDoors {
            let approaching = distance(camera.position,door.center) < 3.8 || distance(enemy.position,door.center) < 3.8
            let angle: Float = approaching ? -1.61 : 0
            door.pivot.eulerAngles.y += (angle-door.pivot.eulerAngles.y)*min(1,dt*9)
        }
    }

    private func sideTable(at p:SCNVector3) {
        let wood = UIColor(red:0.33,green:0.20,blue:0.13,alpha:1)
        box(SCNVector3(0.92,0.074,0.64),SCNVector3(p.x,0.708,p.z-0.18),wood)
        box(SCNVector3(0.81,0.165,0.53),SCNVector3(p.x,0.60,p.z-0.18),wood)
        box(SCNVector3(0.17,0.037,0.065),SCNVector3(p.x,0.60,p.z+0.105),.lightGray)
        for x in [Float(-0.34),0.34] {
            for z in [Float(-0.40),0.03] {
                box(SCNVector3(0.067,0.54,0.068),SCNVector3(p.x+x,0.26,p.z+z),wood)
            }
        }
    }

    private func makeFuse(at p:SCNVector3) -> SCNNode {
        let cartridge = SCNNode()
        cartridge.position = p
        world.rootNode.addChildNode(cartridge)
        let casing = UIColor(red:0.82,green:0.81,blue:0.72,alpha:1)
        let metal = UIColor(red:0.64,green:0.66,blue:0.64,alpha:1)
        let shell = UIColor(red:0.10,green:0.30,blue:0.31,alpha:1)
        box(SCNVector3(0.37,0.097,0.16),SCNVector3Zero,shell,parent:cartridge)
        let tube = SCNCylinder(radius:0.053,height:0.32)
        tube.radialSegmentCount = 14
        tube.materials = [material(casing)]
        let body = SCNNode(geometry:tube)
        body.eulerAngles.z = .pi/2
        cartridge.addChildNode(body)
        for x in [Float(-0.166),0.166] {
            let cap = SCNCylinder(radius:0.058,height:0.079)
            cap.radialSegmentCount = 14
            let finish = material(metal)
            finish.roughness.contents = 0.28
            cap.materials = [finish]
            let contact = SCNNode(geometry:cap)
            contact.position.x = x
            contact.eulerAngles.z = .pi/2
            cartridge.addChildNode(contact)
            box(SCNVector3(0.048,0.035,0.069),SCNVector3(x*1.36,0,0),metal,parent:cartridge)
        }
        box(SCNVector3(0.107,0.007,0.014),SCNVector3(0,0.059,0.021),.systemCyan,parent:cartridge,glow:true)
        return cartridge
    }

    private func bed(at p:SCNVector3,blanket:UIColor) {
        let wood = UIColor(red:0.31,green:0.20,blue:0.14,alpha:1)
        let linen = UIColor(red:0.72,green:0.69,blue:0.60,alpha:1)
        box(SCNVector3(1.70,1.05,0.12),SCNVector3(p.x,0.57,p.z-1.00),wood)
        box(SCNVector3(1.58,0.27,2.04),SCNVector3(p.x,0.25,p.z+0.04),wood)
        box(SCNVector3(1.53,0.22,1.98),SCNVector3(p.x,0.47,p.z+0.04),linen)
        for x in [Float(-0.40),0.40] {
            let cushion = sphere(0.31,SCNVector3(p.x+x,0.64,p.z-0.61),linen,world.rootNode)
            cushion.scale = SCNVector3(1.04,0.23,0.70)
        }
        box(SCNVector3(1.55,0.075,1.37),SCNVector3(p.x,0.62,p.z+0.35),blanket)
        box(SCNVector3(0.067,0.22,1.36),SCNVector3(p.x-0.75,0.51,p.z+0.35),blanket)
        box(SCNVector3(0.067,0.22,1.36),SCNVector3(p.x+0.75,0.51,p.z+0.35),blanket)
        sideTable(at:SCNVector3(p.x-1.50,0,p.z-0.64))
    }

    private func sofa(at p:SCNVector3) {
        let fabric = UIColor(red:0.34,green:0.42,blue:0.36,alpha:1)
        let cushions = UIColor(red:0.42,green:0.50,blue:0.43,alpha:1)
        box(SCNVector3(2.58,0.31,0.91),SCNVector3(p.x,0.30,p.z),fabric)
        box(SCNVector3(2.56,0.66,0.17),SCNVector3(p.x,0.68,p.z-0.38),fabric)
        for x in [Float(-1.14),1.14] {
            box(SCNVector3(0.26,0.43,0.91),SCNVector3(p.x+x,0.55,p.z),fabric)
        }
        for x in [Float(-0.68),0,0.68] {
            box(SCNVector3(0.65,0.12,0.63),SCNVector3(p.x+x,0.50,p.z+0.065),cushions)
            box(SCNVector3(0.65,0.40,0.15),SCNVector3(p.x+x,0.76,p.z-0.235),cushions)
        }
    }

    private func furnishRoom(_ kind: RoomKind, at p: SCNVector3) {
        let wall = p.z - 1.02
        let darkMetal = UIColor(white:0.15,alpha:1)
        let enamel = UIColor(red:0.64,green:0.69,blue:0.62,alpha:1)
        switch kind {
        case .bedroom:
            bed(at:p,blanket:UIColor(red:0.29,green:0.14,blue:0.19,alpha:1))
        case .kitchen: // Kitchen: two-door fridge with an audible compressor.
            buildKitchen(at:p)
            fridge = box(SCNVector3(1.04,2.26,0.39),SCNVector3(p.x,1.13,wall+0.09),enamel)
            box(SCNVector3(1.02,0.045,0.03),SCNVector3(p.x,1.54,wall+0.29),darkMetal)
            for y in [Float(1.24), 1.77] {
                box(SCNVector3(0.07,0.24,0.08),SCNVector3(p.x-0.37,y,wall+0.32),darkMetal)
            }
            box(SCNVector3(0.05,0.04,0.02),SCNVector3(p.x+0.35,0.25,wall+0.3),.systemGreen,glow:true)
        case .lounge:
            box(SCNVector3(2.14,0.63,0.61),SCNVector3(p.x,0.33,wall+0.23),UIColor(red:0.37,green:0.22,blue:0.14,alpha:1))
            for x in [Float(-0.53),0.53] {
                box(SCNVector3(0.69,0.43,0.02),SCNVector3(p.x+x,0.37,wall+0.548),.darkGray)
            }
            sofa(at:SCNVector3(p.x+2.45,0,wall+0.55))
            box(SCNVector3(1.48,0.94,0.42),SCNVector3(p.x,1.41,wall+0.07),darkMetal)
            let screen = box(SCNVector3(1.18,0.70,0.018),SCNVector3(p.x-0.04,1.43,wall+0.29),UIColor(red:0.14,green:0.43,blue:0.48,alpha:1),glow:true)
            thermalScreens.append(screen)
            screen.runAction(.repeatForever(.sequence([
                .fadeOpacity(to:0.18,duration:0.06), .wait(duration:0.14),
                .fadeOpacity(to:0.86,duration:0.32), .wait(duration:2.1),
                .fadeOpacity(to:0.40,duration:0.18), .wait(duration:0.47)
            ])))
        case .study: // Study: crowded shelves.
            for y in [Float(0.75), 1.37, 1.99] {
                box(SCNVector3(1.78,0.10,0.43),SCNVector3(p.x,y,wall+0.10),UIColor(red:0.26,green:0.14,blue:0.075,alpha:1))
                for i in 0..<6 {
                    let height: Float = i.isMultiple(of:2) ? 0.34 : 0.42
                    let color: UIColor = i.isMultiple(of:3) ? .systemBrown : .darkGray
                    box(SCNVector3(0.18,height,0.26),SCNVector3(p.x-0.63+Float(i)*0.25,y+0.05+height/2,wall+0.12),color)
                }
            }
        case .laundry: // Laundry: circular washer door.
            box(SCNVector3(1.2,1.25,0.43),SCNVector3(p.x,0.63,wall+0.11),enamel)
            let door = sphere(0.40,SCNVector3(p.x,0.58,wall+0.34),darkMetal,world.rootNode)
            door.scale.z = 0.10
            box(SCNVector3(0.25,0.055,0.02),SCNVector3(p.x+0.27,1.10,wall+0.34),.systemOrange,glow:true)
        case .workshop: // Workshop: amber tool rack and hanging spanners.
            box(SCNVector3(1.82,1.08,0.11),SCNVector3(p.x,1.58,wall),UIColor(red:0.35,green:0.16,blue:0.06,alpha:1))
            for i in 0..<5 {
                let tool = box(SCNVector3(0.08,0.40,0.07),SCNVector3(p.x-0.64+Float(i)*0.32,1.6,wall+0.10),enamel)
                tool.eulerAngles.z = i.isMultiple(of:2) ? -0.22 : 0.22
            }
        case .dining:
            box(SCNVector3(2.4,0.12,1.18),SCNVector3(p.x,0.89,wall+0.65),UIColor(red:0.25,green:0.15,blue:0.092,alpha:1))
            for x in [Float(-0.89),0.89] {
                box(SCNVector3(0.12,0.84,0.80),SCNVector3(p.x+x,0.42,wall+0.65),darkMetal)
            }
            let plate = sphere(0.24,SCNVector3(p.x+0.51,0.97,wall+0.69),enamel,world.rootNode)
            plate.scale.y = 0.11
            for x in [Float(-0.73),0.62] {
                box(SCNVector3(0.40,0.09,0.41),SCNVector3(p.x+x,0.48,wall+1.52),darkMetal)
                box(SCNVector3(0.40,0.43,0.07),SCNVector3(p.x+x,0.73,wall+1.72),darkMetal)
                for dx in [Float(-0.15),0.15] {
                    box(SCNVector3(0.048,0.44,0.36),SCNVector3(p.x+x+dx,0.22,wall+1.52),darkMetal)
                }
            }
        case .guest:
            bed(at:p,blanket:UIColor(red:0.16,green:0.32,blue:0.30,alpha:1))
        case .sunroom:
            box(SCNVector3(3.15,1.38,0.13),SCNVector3(p.x,1.97,wall),darkMetal)
            for x in [Float(-1.04),0,1.04] {
                box(SCNVector3(0.94,1.22,0.04),SCNVector3(p.x+x,1.97,wall+0.09),UIColor(red:0.12,green:0.24,blue:0.30,alpha:1))
            }
        }
    }

    private func buildKitchen(at p:SCNVector3) {
        let walnut = UIColor(red:0.44,green:0.25,blue:0.13,alpha:1)
        let granite = UIColor(red:0.29,green:0.30,blue:0.28,alpha:1)
        let steel = UIColor(red:0.56,green:0.60,blue:0.59,alpha:1)
        let wall = p.z-1.10
        for slot in [-2,-1,1,2] {
            let x = p.x+Float(slot)*1.18
            box(SCNVector3(1.15,0.88,0.56),SCNVector3(x,0.45,wall+0.23),walnut)
            box(SCNVector3(1.18,0.078,0.65),SCNVector3(x,0.92,wall+0.23),granite)
            box(SCNVector3(0.34,0.044,0.068),SCNVector3(x,0.70,wall+0.53),steel)
            box(SCNVector3(1.10,0.68,0.31),SCNVector3(x,2.01,wall+0.11),walnut)
            box(SCNVector3(0.065,0.13,0.038),SCNVector3(x+0.34,1.81,wall+0.29),steel)
            for n in 0..<4 {
                box(SCNVector3(0.265,0.36,0.035),SCNVector3(x-0.42+Float(n)*0.28,1.16,wall),n.isMultiple(of:2) ? steel : granite)
            }
        }
        let sink = p.x-2.36
        box(SCNVector3(0.71,0.025,0.42),SCNVector3(sink,0.972,wall+0.24),steel)
        box(SCNVector3(0.55,0.028,0.31),SCNVector3(sink,0.984,wall+0.24),.darkGray)
        box(SCNVector3(0.055,0.23,0.052),SCNVector3(sink,1.09,wall+0.10),steel)
        box(SCNVector3(0.055,0.052,0.19),SCNVector3(sink,1.19,wall+0.16),steel)
        let oven = p.x+2.36
        box(SCNVector3(0.99,0.57,0.032),SCNVector3(oven,0.43,wall+0.53),UIColor(white:0.085,alpha:1))
        box(SCNVector3(0.72,0.032,0.056),SCNVector3(oven,0.68,wall+0.567),steel)
        for x in [Float(-0.30),0.30] {
            let burner = sphere(0.19,SCNVector3(oven+x,0.978,wall+0.27),.black,world.rootNode)
            burner.scale.y = 0.085
        }
    }

    private func buildSurvivalProps() {
        let steel = UIColor(red:0.24,green:0.30,blue:0.29,alpha:1)
        let alcove = point(shelter)
        box(SCNVector3(1.60,2.40,0.25),SCNVector3(alcove.x,1.20,alcove.z-0.98),steel)
        for y in [Float(0.38),0.86,1.34,1.84] {
            box(SCNVector3(1.46,0.055,0.06),SCNVector3(alcove.x,y,alcove.z-0.82),.darkGray)
        }
        box(SCNVector3(0.37,0.13,0.10),SCNVector3(alcove.x+0.37,1.10,alcove.z-0.79),.systemGreen,glow:true)
        noteNodes = notes.map { note in
            let p = point(note.cell)
            box(SCNVector3(0.75,0.40,0.47),SCNVector3(p.x,0.20,p.z),.darkGray)
            let sheet = box(SCNVector3(0.32,0.018,0.24),SCNVector3(p.x,0.414,p.z),UIColor(red:0.72,green:0.63,blue:0.36,alpha:1),glow:true)
            sheet.eulerAngles.y = 0.14
            return sheet
        }
        for cell in traps {
            let p = point(cell,y:0.018)
            box(SCNVector3(1.42,0.035,0.43),p,UIColor(red:0.39,green:0.24,blue:0.13,alpha:1))
            for x in [Float(-0.57),0.58] {
                box(SCNVector3(0.045,0.045,0.25),SCNVector3(p.x+x,p.y,p.z),.darkGray)
            }
        }
        for cell in pipeCells {
            let p = point(cell)
            let copper = UIColor(red:0.43,green:0.27,blue:0.16,alpha:1)
            for offset in [Float(-0.46), 0.46] {
                let pipe = SCNCylinder(radius:0.065,height:4.0)
                pipe.radialSegmentCount = 12
                pipe.materials = [material(copper)]
                let node = SCNNode(geometry:pipe)
                node.position = SCNVector3(p.x,3.03,p.z+offset)
                node.eulerAngles.z = .pi/2
                world.rootNode.addChildNode(node)
                for x in [Float(-1.34),-0.21,1.16] {
                    box(SCNVector3(0.075,0.23,0.18),SCNVector3(p.x+x,3.11,p.z+offset),.darkGray)
                }
            }
        }
    }

    private func updatePipes() {
        guard elapsed >= nextPipe else { return }
        nextPipe = elapsed + Float.random(in:5...15)
        guard soundEnabled, let source = pipeSources.randomElement() else { return }
        let candidates = pipeCells.filter { (2.5...13).contains(distance(point($0),camera.position)) }
        guard let pipe = candidates.randomElement() else { return }
        playRoomSound(source,at:point(pipe,y:2.95))
    }

    private func playRoomSound(_ source:SCNAudioSource,at position:SCNVector3) {
        let node = SCNNode()
        node.name = "roomEffect"
        node.position = position
        world.rootNode.addChildNode(node)
        node.addAudioPlayer(SCNAudioPlayer(source:source))
        node.runAction(.sequence([.wait(duration:3),.removeFromParentNode()]))
    }

    private func tripFloorboard() -> Bool {
        let p = camera.position
        let current = House.cell(p.x,p.z)
        let trap = traps.contains(current) && distance(p,point(current)) < 0.84 ? current : nil
        defer { lastTrap = trap }
        guard let trap, trap != lastTrap, !hidden, elapsed >= nextTrap else { return false }
        nextTrap = elapsed+3.5
        if soundEnabled, let knock = pipeSources.first { playRoomSound(knock,at:point(trap,y:0.12)) }
        UIImpactFeedbackGenerator(style:.light).impactOccurred()
        return distance(p,enemy.position) < 27
    }

    private func makeFace() -> (head: SCNNode, eyes: [SCNNode], jaw: SCNNode) {
        let head = SCNNode()
        let skin = UIColor(red:0.42,green:0.38,blue:0.30,alpha:1)
        let hood = sphere(0.35,SCNVector3(0,0.085,0.105),UIColor(white:0.074,alpha:1),head)
        hood.scale = SCNVector3(1.0,1.11,0.83)
        let skull = sphere(0.31,SCNVector3(0,0.045,0),skin,head)
        skull.scale = SCNVector3(0.88,1.16,0.81)
        let nose = sphere(0.065,SCNVector3(0,-0.001,-0.24),skin,head)
        nose.scale = SCNVector3(0.67,1.19,1.26)
        for x in [Float(-0.18),0.18] {
            let cheek = sphere(0.093,SCNVector3(x,-0.055,-0.18),UIColor(red:0.34,green:0.27,blue:0.23,alpha:1),head)
            cheek.scale = SCNVector3(0.86,0.66,0.73)
        }
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
            let drop = Float(i % 3)*0.006
            let tooth = UIColor(red:0.68,green:0.64,blue:0.47,alpha:1)
            box(SCNVector3(0.030,0.048,0.025),SCNVector3(x,-0.105-drop,-0.268),tooth,parent:head)
            box(SCNVector3(0.030,0.040,0.025),SCNVector3(x,0.036,-0.184),tooth,parent:jaw)
        }
        return (head,eyes,jaw)
    }

    @objc private func showHelp() {
        let panel = UIAlertController(title:"HOW TO SURVIVE",message:"Left thumb: move. RUN toggles sprint. Drag the right side to look.\n\nFind three cyan fuses. USE the red fuse box, then the green exit.\n\nCALL WALEED rings his phone in another room. HANG UP before he traces you. SILENCE incoming calls and break line of sight before hiding.\n\nUse the steel shelter in the guest room when you can reach it safely. Some boards will give you away. Read notes for clues.\n\nContains sudden sounds and jumpscares.",preferredStyle:.alert)
        panel.addAction(UIAlertAction(title:"GOT IT",style:.default))
        present(panel,animated:true)
    }
    private func stopSceneAudio() {
        world.rootNode.childNodes.filter { $0.name == "roomEffect" }.forEach {
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
        let position: SCNVector3
        if enemyAwake, Bool.random() {
            position = SCNVector3(enemy.position.x,1.4,enemy.position.z)
        } else if let room = rooms.filter({ distance(point($0.phone),camera.position) > 4 }).randomElement() {
            position = point(room.phone,y:1.2)
        } else {
            return
        }
        playRoomSound(source,at:position)
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
        for name in ["pipe-knock","pipe-hiss"] {
            if let clip = SCNAudioSource(fileNamed:name+".wav") {
                clip.isPositional = true
                clip.volume = 1
                clip.load()
                pipeSources.append(clip)
            }
        }
        ringtone = loopingSource("ring.wav",volume:0.95)
        fridgeHum = loopingSource("fridge.wav",volume:0.6)
        for name in ["drone","ring","step","sting","pickup","heartbeat","blackout","scare-burp"] {
            if let url = Bundle.main.url(forResource:name,withExtension:"wav"),let p = try? AVAudioPlayer(contentsOf:url) { p.prepareToPlay(); players[name] = p }
        }
        players["sting"]?.volume = 0.55
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
        houseAmbient?.intensity = 700
        setRoomPower(940)
        shade.isHidden = true
        introOverlay.isHidden = false
        introPhone.isHidden = true
        introPhone.alpha = 0
        introPhone.transform = CGAffineTransform(translationX:14,y:145)
        sceneView.isPlaying = true
        UIApplication.shared.isIdleTimerDisabled = true
        play("drone")
        updateIntro(dt:0)
    }

    private func updateIntro(dt: Float) {
        introElapsed += dt
        let glance = min(introElapsed/2.4,1)
        camera.eulerAngles = SCNVector3(-0.015,-0.82+glance*0.91,0)
        let cue: Int
        switch introElapsed {
        case ..<2.35: cue = 0
        case ..<4.1: cue = 1
        case ..<5.3: cue = 2
        case ..<6.6: cue = 3
        case ..<7.7: cue = 4
        case ..<10.0: cue = 5
        case ..<14.1: cue = 6
        case ..<16.5: cue = 7
        default:
            skipIntro()
            return
        }
        guard cue != introBeat else { return }
        introBeat = cue
        switch cue {
        case 0:
            introCaption.text = "Yamen: “He told me to wait until morning.”"
        case 1:
            introPhone.screen = .lock
            introPhone.isHidden = false
            UIView.animate(withDuration:0.48) {
                self.introPhone.alpha = 1
                self.introPhone.transform = .identity
            }
            introCaption.text = "Yamen: “One call. That’s all.”"
        case 2:
            introPhone.screen = .home
            introCaption.text = nil
            play("pickup")
        case 3:
            introPhone.screen = .recents
        case 4:
            introPhone.screen = .contact
        case 5:
            introPhone.screen = .dialing
            play("ring")
        case 6:
            players["ring"]?.stop()
            introPhone.screen = .connected
            introCaption.text = "Waleed: “Why did you call me at 3 AM?”"
            if soundEnabled {
                let reply = AVSpeechUtterance(string:"Why did you call me at three A M?")
                reply.voice = AVSpeechSynthesisVoice(language:"en-GB")
                reply.rate = 0.45
                reply.pitchMultiplier = 0.86
                phoneVoice.speak(reply)
            }
        default:
            phoneVoice.stopSpeaking(at:.immediate)
            players["drone"]?.stop()
            houseAmbient?.intensity = 0
            setRoomPower(0)
            introPhone.screen = .lost
            play("blackout")
            UIImpactFeedbackGenerator(style:.medium).impactOccurred()
            UIView.animate(withDuration:0.55) {
                self.introPhone.alpha = 0
                self.introPhone.transform = CGAffineTransform(translationX:12,y:125)
            }
            introCaption.text = "Yamen: “Waleed? … Are you still there?”"
        }
    }

    @objc private func skipIntro() {
        guard phase == .intro else { return }
        players["ring"]?.stop()
        players["blackout"]?.stop()
        phoneVoice.stopSpeaking(at:.immediate)
        introOverlay.backgroundColor = .clear
        enemy.isHidden = false
        camera.eulerAngles = SCNVector3Zero
        houseAmbient?.intensity = 240
        setRoomPower(0)
        beginPlaying()
        tell("Restore the power. Find three cyan fuses.",duration:7)
    }

    private func resetGame() {
        house = House()
        nextPipe = 7; nextTrap = 0; lastTrap = nil; readNotes = []
        movement = .zero; stepPhase = 0; lookRoll = 0
        elapsed = 0; nextBurp = 9; yaw = 0; pitch = 0; hidden = false; flashlight = true
        battery = 100; stamina = 100; collected = []; power = false; nextCall = 24
        phoneState = .idle; nextOutgoing = 0; lure = nil; remoteRing = nil
        huntUntil = 0; route = []; routeTime = 0; patrolIndex = 0; footTime = 0; gait = 0
        enemyTarget = House.enemy; routedTarget = nil; enemyAwake = false
        lastKnownPlayer = nil; searchRoute = []
        buildWorld()
        setRoomPower(0)
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
            tell("Ringing in the \(room.kind.rawValue). Hang up before he traces you.",duration:4)
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
    private func near(_ c:Cell,range:Float = 2.6) -> Bool { let p = point(c); return distance(camera.position,p) < range && house.visible(camera.position.x,camera.position.z,p.x,p.z) }
    private func tell(_ text:String,duration:Float = 4) { message.text = text; messageUntil = elapsed+duration }
    @objc private func interact() {
        guard phase == .playing else { return }
        if hidden { hidden = false; tell("You step out. Listen before moving."); return }
        for (index,note) in notes.enumerated() where !readNotes.contains(note.cell) && near(note.cell,range:1.8) {
            readNotes.insert(note.cell)
            noteNodes[index].isHidden = true
            play("pickup")
            tell(note.text,duration:8)
            return
        }
        if near(shelter,range:2) {
            if distance(camera.position,enemy.position) < 2 {
                tell("He’s too close to get the door shut.")
            } else {
                hidden = true
                setRunning(false)
                flashlight = false
                lightButton.setTitle("LIGHT OFF",for:.normal)
                movement = .zero
                stick.reset()
                tell("Steel door latched. USE to step out.",duration:8)
            }
            return
        }
        for i in house.fuses.indices where !collected.contains(i) && near(house.fuses[i]) { collected.insert(i); fuseNodes[i].isHidden = true; play("pickup"); tell("Fuse \(collected.count) / 3 collected."); return }
        if near(House.panel) {
            if collected.count == 3 && !power { power = true; setRoomPower(560); play("pickup"); tell("Power restored. Get to the green exit door!",duration:6) }
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
            let ending = readNotes.count == notes.count ?
                "Outside, Yamen’s phone lights up. The service log was right: the house was using Waleed’s number. He leaves the phone on the doorstep." :
                "Yamen throws the breaker and gets out. From the other side of the locked door, the pipes knock three times."
            showMenu("YOU GOT OUT.",ending,"PLAY AGAIN")
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
        upLight.light?.intensity = 265
        scareScene.rootNode.addChildNode(upLight)

        sceneView.scene = scareScene
        sceneView.pointOfView = scareCamera
        sceneView.audioListener = scareCamera
        let lunge = SCNAction.move(to:SCNVector3(0,-0.055,-0.69),duration:0.16)
        lunge.timingMode = .easeIn
        let twist = SCNAction.rotateTo(x:0.11,y:.pi,z:0.16,duration:0.16,usesShortestUnitArc:true)
        head.runAction(.sequence([
            .wait(duration:0.08),
            .group([lunge,twist]),
            .moveBy(x:-0.037,y:0.025,z:0.028,duration:0.055),
            .moveBy(x:0.060,y:-0.035,z:-0.03,duration:0.085),
            .rotateBy(x:-0.16,y:-0.04,z:-0.09,duration:0.20)
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
            .group([.rotateBy(x:-1.02,y:0,z:0,duration:0.15),.moveBy(x:0,y:-0.14,z:0,duration:0.15)]),
            .wait(duration:0.25), .rotateBy(x:0.19,y:0,z:0,duration:0.21)
        ]))
        play("sting")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.24) { [weak self] in
            guard let self, self.phase == .caught else { return }
            self.play("scare-burp")
            UIImpactFeedbackGenerator(style:.heavy).impactOccurred(intensity:1)
        }

        DispatchQueue.main.asyncAfter(deadline:.now()+1.55) { [weak self] in
            guard let self, self.phase == .caught else { return }
            self.showMenu("HE FOUND YOU.","Don’t call Waleed at 3 AM.\n\nWalk to stay quiet. Silence incoming calls.\nHide by a gold handle.\nBreak his line of sight before hiding.","TRY AGAIN")
        }
    }

    private func seesPlayer(_ distance: Float) -> Bool {
        guard !hidden, distance < (flashlight ? 18 : 11) else { return false }
        let p = camera.position, e = enemy.position
        return house.visible(e.x,e.z,p.x,p.z)
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
        guard house.walkable(nx,nz,radius:0.18) else { return 0 }
        enemy.position = SCNVector3(nx,position.y,nz)
        let bearing = atan2(-vx,-vz)
        let angleDelta = bearing-enemy.eulerAngles.y
        enemy.eulerAngles.y += atan2(sin(angleDelta),cos(angleDelta))*min(1,dt*13)
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
                    if reached(enemyTarget), enemyTarget == house.patrol[patrolIndex] {
                        patrolIndex = (patrolIndex+1)%house.patrol.count
                    }
                    enemyTarget = house.patrol[patrolIndex]
                }
            }

            let speed: Float = hunting ? (power ? 4.45 : 4.15) : 2.26
            let moved = advanceEnemy(visiblePlayer:sight ? p : nil,speed:speed,dt:dt)
            gait += moved*4.9
            let amount: Float = hunting ? 0.74 : 0.45
            let stride = moved > 0.001 ? sin(gait)*amount : 0
            let target: [Float] = [-stride,stride,stride,-stride]
            let bend: [Float] = [0.38+max(0,stride)*0.42,0.38+max(0,-stride)*0.42,
                                 -max(0,-stride)*0.88,-max(0,stride)*0.88]
            for index in enemyLimbs.indices {
                enemyLimbs[index].eulerAngles.x += (target[index]-enemyLimbs[index].eulerAngles.x)*min(1,dt*17)
                enemyBend[index].eulerAngles.x += (bend[index]-enemyBend[index].eulerAngles.x)*min(1,dt*17)
            }
            enemy.eulerAngles.x = hunting && moved > 0.001 ? 0.12 : 0
            enemy.position.y = moved > 0.001 ? abs(sin(gait))*0.05 : 0
        }

        let e = enemy.position
        let dist = distance(e,p)
        let close = !hidden && dist < 5.8 && house.visible(e.x,e.z,p.x,p.z)
        enemyEyes.forEach { $0.isHidden = !close }
        if close {
            let facing = atan2(e.x-p.x,e.z-p.z)-enemy.eulerAngles.y
            enemyHead.eulerAngles.y = atan2(sin(facing),cos(facing))
        } else {
            enemyHead.eulerAngles.y = 0
        }
        if enemyAwake && !hidden && house.canCatch(enemyX:e.x,enemyZ:e.z,playerX:p.x,playerZ:p.z) {
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
            searchRoute = house.searchCells(near:lastKnownPlayer)
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
        if let player = visiblePlayer, house.walkableBetween(e.x,e.z,player.x,player.z,radius:0.18) {
            route.removeAll()
            routedTarget = nil
            routeTime = elapsed
            return moveEnemy(toward:player,speed:speed,dt:dt)
        }
        if routedTarget != enemyTarget, elapsed >= routeTime {
            // Finish the committed segment before turning, so corners stay clear.
            let origin = route.first ?? House.cell(e.x,e.z)
            let anchor = route.first != nil || !reached(origin) ? [origin] : []
            route = anchor + house.path(from:origin,to:enemyTarget)
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
        stamina = min(100,max(0,stamina+(sprint ? -13 : 13)*dt))
        if running && stamina <= 2 { setRunning(false) }
        var stepped = false
        if !hidden {
            let speed: Float = sprint ? 4 : 2.2
            let requested = moving ? SIMD2<Float>(Float(stick.vector.x),-Float(stick.vector.y))*speed : .zero
            movement += (requested-movement)*min(1,dt*(moving ? 12 : 19))
            let dx = (-sin(yaw)*movement.y+cos(yaw)*movement.x)*dt
            let dz = (-cos(yaw)*movement.y-sin(yaw)*movement.x)*dt
            let previous = camera.position
            var p = previous
            if house.walkable(p.x+dx,p.z) { p.x += dx }
            if house.walkable(p.x,p.z+dz) { p.z += dz }
            let traveled = distance(previous,p)
            stepped = traveled > 0.002
            stepPhase += traveled*(sprint ? 4.5 : 5.1)
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            let targetHeight: Float = 1.60 + (stepped && !reduceMotion ? sin(stepPhase)*(sprint ? 0.046 : 0.028) : 0)
            p.y += (targetHeight-p.y)*min(1,dt*18)
            let tilt = reduceMotion ? 0 : -movement.x*0.010
            lookRoll += (tilt-lookRoll)*min(1,dt*9)
            camera.position = p
            camera.eulerAngles = SCNVector3(pitch,yaw,lookRoll)
            if stepped && elapsed > footTime { play("step"); footTime = elapsed+(sprint ? 0.3 : 0.55) }
        }
        battery = min(100,max(0,battery+(flashlight && !hidden ? -0.65 : 1.25)*dt))
        if battery <= 0 { flashlight = false; lightButton.setTitle("LIGHT OFF",for:.normal) }
        torch.light?.intensity = flashlight && !hidden ? flashlightIntensity : 0
        camera.camera?.exposureOffset = hidden ? -2 : 0
        moveDoors(dt:dt)
        updatePipes()
        let traced = updatePhone()
        let trap = tripFloorboard()
        guard updateEnemy(dt:dt,sprint:sprint,moving:stepped,traced:traced || trap) else { return }
        status.text = "3:\(String(format:"%02d",min(59,Int(elapsed/12)))) AM   LIGHT \(Int(battery))%   BREATH \(Int(stamina))%"
        objective.text = power ? "POWER ON · REACH THE GREEN EXIT" : "FUSES \(collected.count)/3 · \(collected.count == 3 ? "FIND THE RED FUSE BOX" : "SEARCH THE HOUSE")"
        if hidden { hint.text = "HIDDEN · USE TO LEAVE" }
        else if near(shelter,range:2) { hint.text = "USE · STEEL SHELTER" }
        else if notes.contains(where:{ !readNotes.contains($0.cell) && near($0.cell,range:1.8) }) { hint.text = "USE · READ NOTE" }
        else if house.fuses.indices.contains(where:{ !collected.contains($0) && near(house.fuses[$0]) }) { hint.text = "USE · TAKE FUSE" }
        else if near(House.panel) { hint.text = "USE · FUSE BOX" } else if near(House.exit) { hint.text = "USE · EXIT" }
        else if House.closets.contains(where:{ near($0,range:2) }) { hint.text = "USE · HIDE" } else { hint.text = elapsed < huntUntil ? "HE’S LOOKING FOR YOU" : "DRAG RIGHT SIDE TO LOOK" }
    }
}
