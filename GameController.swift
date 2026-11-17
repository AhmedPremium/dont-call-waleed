import UIKit
import SceneKit
import AVFoundation
import CoreText

final class Stick: UIView {
    var vector = CGPoint.zero
    private let knob = UIView()
    private var dragStart: CGPoint?
    override init(frame: CGRect) {
        super.init(frame:frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.06)
        layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor; layer.borderWidth = 1
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.25); knob.isUserInteractionEnabled = false; addSubview(knob)
        accessibilityLabel = "Movement joystick"
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var travel: CGFloat { bounds.width * 0.325 }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        let diameter = bounds.width * 0.35
        knob.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        knob.layer.cornerRadius = diameter / 2
        positionKnob()
    }

    func reset() {
        vector = .zero
        dragStart = nil
        positionKnob()
    }

    private func positionKnob() {
        knob.center = CGPoint(x: bounds.midX + vector.x * travel,
                             y: bounds.midY + vector.y * travel)
    }

    private func track(_ touches: Set<UITouch>) {
        guard travel > 0, let point = touches.first?.location(in: self) else { return }
        if dragStart == nil { dragStart = point }
        let anchor = dragStart ?? point
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let divisor = max(travel, hypot(dx, dy))
        vector = CGPoint(x: dx / divisor, y: dy / divisor)
        positionKnob()
    }
    override func touchesBegan(_ t:Set<UITouch>,with e:UIEvent?) { track(t) }
    override func touchesMoved(_ t:Set<UITouch>,with e:UIEvent?) { track(t) }
    override func touchesEnded(_ t:Set<UITouch>,with e:UIEvent?) { reset() }
    override func touchesCancelled(_ t:Set<UITouch>,with e:UIEvent?) { reset() }
}

final class GameController: UIViewController {
    enum Phase { case title, intro, downstairs, openingDoor, gardenReveal, playing, reading, paused, caught, ending, escaped }
    private enum PhoneState {
        case idle, incoming(until: Float), outgoing(started: Float)
    }

    private struct Cupboard {
        let cell: Cell
        let front: SCNVector3
        let doors: [SCNNode]
        let forwardX: Float
        let forwardZ: Float
        let fuse: SCNNode?
        var isOpen = false
        var readyAt: Float = 0
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
        (.sunroom, House.sunroomWindow, Cell(x:12,z:12))
    ]
    private var phase = Phase.title
    private var story = StoryProgress()
    private var gardenDoorOpen = false
    private var retreatStarted: Float = 0
    private var televisionScreen: SCNNode?
    private var televisionOn = false
    private var newsStarted: Float?
    private var newsLine = -1
    private let bulletin = [
        "Police warn that Waleed is still at large. Investigators have linked him to several killings.",
        "Officials say he is dangerous. Stay indoors and lock all entrances.",
        "If your emergency system fails, reconnect the two security relays before using the back exit."
    ]
    private var serviceKeyNode: SCNNode?
    private var relayLights = [Cell:SCNNode]()
    private var exitLight: SCNNode?
    private let sceneView = SCNView()
    private var world = SCNScene(), camera = SCNNode(), torch = SCNNode(), enemy = SCNNode()
    private var enemyEyes = [SCNNode]()
    private var enemyHead = SCNNode()
    private var enemyLimbs = [SCNNode]()
    private var gait: Float = 0
    private var enemyAwake = false
    private var lastKnownPlayer: Cell?
    private var searchRoute = [Cell]()
    private let shelter = Cell(x:15,z:6)
    private let notes: [(cell:Cell, title:String, author:String, body:String)] = [
        (Cell(x:4,z:14),"Three knocks","Waleed · handwritten note",
         "Yamen,\n\nIt knocks three times. I heard it from the stairs first. When I opened the door, nobody was there.\n\nIf something answers from inside the house, leave the phone alone. It already knows your number."),
        (Cell(x:13,z:2),"Where to hide","Yamen · torn notebook page",
         "The floorboards in the hall are loose. I stepped on one and heard someone stop walking on the other side of the wall.\n\nThere’s a steel shelter in the study. Look for the green handle. Get the door shut before it reaches you."),
        (Cell(x:13,z:12),"Breaker and phone line","Maintenance · service log",
         "The house line runs behind the downstairs breaker. When I disconnected it, the handset rang anyway. Caller ID showed Waleed’s number.\n\nI left three spare fuses in the cupboards. Once the power is back, use the green exit.")
    ]
    private let reader = DocumentReader(frame:.zero)
    private let traps = [Cell(x:11,z:4),Cell(x:12,z:8),Cell(x:8,z:13)]
    private let pipeCells = [Cell(x:4,z:11),Cell(x:11,z:2),Cell(x:14,z:7),Cell(x:12,z:13)]
    private var nextTrap: Float = 0
    private var lastTrap: Cell?
    private var readNotes = Set<Cell>()
    private var noteNodes = [SCNNode]()
    private var thermalScreens = [SCNNode]()
    private var lightPanels = [SCNNode]()
    private var lookRoll: Float = 0
    private var crouched = false
    private var sightTime: Float = 0
    private enum PatrolActivity { case fridge, listen, television }
    private var patrolActivity: PatrolActivity?
    private var patrolPauseUntil: Float = 0
    private var patrolPose: Float = 0
    private var fridgeHinge: SCNNode?
    private var fridgeLamp: SCNLight?
    private var activityCreak: SCNAudioSource?
    private var televisionBuzz: SCNAudioSource?
    private var patrolTVAudio: SCNNode?
    private var nextHello: Float = 26
    private var wardrobeReturn: (position:SCNVector3,yaw:Float,pitch:Float)?
    private var wardrobeYaw: Float = 0
    private var stepPhase: Float = 0
    private var movement = SIMD2<Float>.zero
    private var enemyBend = [SCNNode]()
    private var houseAmbient: SCNLight?
    private let introOverlay = UIView()
    private let introSkip = UIButton(type:.system)
    private let introCaption = UILabel()
    private let endCard = UILabel()
    private let introPhone = IntroPhoneView(frame:.zero)
    private var opening: OpeningScene?
    private var doorCameraStart = SCNVector3Zero
    private var doorFacingStart: Float = 0
    private var doorPitchStart: Float = 0
    private var doorCue = 0
    private var pausedFrom = Phase.playing
    private var nextKnock: Float = 0
    private var distanceSinceStep: Float = 0
    private var stepVoice = 0
    private var introBeat = -1
    private var introElapsed: Float = 0
    private var exitHinge = SCNNode()
    private var endingStart = SCNVector3Zero
    private var endingYaw: Float = 0
    private var endingPitch: Float = 0
    private var endingTime: Float = 0
    private var endingBeat = -1
    private var breaker = BreakerEncounter()
    private var wardrobeKnock: SCNAudioSource?
    private var phoneState = PhoneState.idle
    private var nextOutgoing: Float = 0
    private var lure: (target: Cell, until: Float)?
    private var ringtone: SCNAudioSource?
    private var remoteRing: SCNNode?
    private let phoneVoice = AVSpeechSynthesizer()
    private var innerDoors = [(pivot: SCNNode, center: SCNVector3)]()
    private var cupboards = [Cupboard](), lamps = [SCNNode]()
    private let stick = Stick(frame:.zero), lookSurface = UIView(), controls = UIView(), shade = UIView(), danger = UIView()
    private let status = UILabel(), objective = UILabel(), message = UILabel(), hint = UILabel(), titleLabel = UILabel(), detailLabel = UILabel()
    private let use = UIButton(type:.system), lightButton = UIButton(type:.system), crouchButton = UIButton(type:.system), sprintButton = UIButton(type:.system), phoneButton = UIButton(type:.system), pauseButton = UIButton(type:.system), startButton = UIButton(type:.system), soundButton = UIButton(type:.system)
    private let menu = UIStackView()
    private let retryActions = UIStackView()
    private let clockLabel = UILabel(), eyebrow = UILabel(), footer = UILabel()
    private let helpButton = UIButton(type:.system)
    private let newLayoutButton = UIButton(type:.system)
    private let menuArtwork = UIImageView()
    private let menuGradient = CAGradientLayer()
    private var nextBurp: Float = 9
    private var burpSources = [SCNAudioSource]()
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var elapsed: Float = 0, yaw: Float = 0, pitch: Float = 0, battery: Float = 100, stamina: Float = 100
    private var running = false, hidden = false, flashlight = true, power = false, soundEnabled = true
    private var collected = Set<Cell>(), route = [Cell]()
    private var nextCall: Float = 24, huntUntil: Float = 0, routeTime: Float = 0, messageUntil: Float = 0
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
        setupUI(); setupIntro()
        reader.frame = view.bounds
        reader.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        reader.onClose = { [weak self] in self?.closeDocument() }
        view.addSubview(reader)
        buildWorld(); loadAudio()
        showMenu("Don’t Call\nWaleed", "One call wakes the house.","Play")
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
        updateMenuFonts()
        menu.spacing = compact ? 7 : 16
        retryActions.axis = compact && phase == .caught ? .horizontal : .vertical
        menuGradient.frame = shade.bounds
    }
    private func updateMenuFonts() {
        let compact = view.bounds.height < 600
        let size: CGFloat = phase == .title ? (compact ? 43 : min(93,view.bounds.width*0.086)) : (compact ? 28 : 61)
        titleLabel.font = cinematicFont(size)
        detailLabel.font = .systemFont(ofSize:compact ? 13 : 19,weight:.regular)
    }

    private func cinematicFont(_ size:CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize:size,weight:.semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor:descriptor,size:size)
    }

    private func vhs(_ size:CGFloat) -> UIFont { UIFont(name:"VCROSDMono",size:size) ?? .monospacedSystemFont(ofSize:size,weight:.regular) }
    private func label(_ l:UILabel,_ size:CGFloat,_ color:UIColor = .white) { l.font = vhs(size); l.textColor = color; l.numberOfLines = 0 }
    private func button(_ b:UIButton,_ text:String,_ action:Selector,icon:String) {
        b.setTitle(text,for:.normal); b.tintColor = .white; b.titleLabel?.font = .systemFont(ofSize:13,weight:.semibold)
        b.setImage(UIImage(systemName:icon,withConfiguration:UIImage.SymbolConfiguration(pointSize:15,weight:.medium)),for:.normal)
        if !text.isEmpty { b.titleEdgeInsets = UIEdgeInsets(top:0,left:5,bottom:0,right:-5) }
        b.backgroundColor = UIColor(red:0.06,green:0.075,blue:0.075,alpha:0.91)
        b.layer.borderWidth = 1
        b.layer.borderColor = UIColor(white:0.7,alpha:0.28).cgColor
        b.layer.cornerRadius = 12
        b.addTarget(self,action:action,for:.touchUpInside); b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(greaterThanOrEqualToConstant:46).isActive = true
    }
    private func setupUI() {
        for v in [sceneView,danger,controls,shade] { v.frame = view.bounds; v.autoresizingMask = [.flexibleWidth,.flexibleHeight]; view.addSubview(v) }
        sceneView.antialiasingMode = .multisampling2X; sceneView.preferredFramesPerSecond = 60; sceneView.rendersContinuously = false; sceneView.isUserInteractionEnabled = false
        danger.backgroundColor = .red; danger.alpha = 0; danger.isUserInteractionEnabled = false
        for v in [lookSurface,stick,status,objective,message,hint,use,lightButton,crouchButton,sprintButton,phoneButton,pauseButton] { v.translatesAutoresizingMaskIntoConstraints = false; controls.addSubview(v) }
        lookSurface.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(look(_:))))
        label(status,14); label(objective,14,UIColor(red:0.84,green:0.74,blue:0.5,alpha:1)); label(message,17); message.textAlignment = .center; label(hint,13); hint.textAlignment = .center
        button(use,"USE",#selector(interact),icon:"hand.tap")
        button(lightButton,"LIGHT ON",#selector(toggleLight),icon:"flashlight.on.fill")
        button(sprintButton,"RUN",#selector(toggleRun),icon:"figure.run")
        button(crouchButton,"CROUCH",#selector(toggleCrouch),icon:"figure.strengthtraining.functional")
        button(phoneButton,"CALL WALEED",#selector(phoneAction),icon:"phone.fill")
        button(pauseButton,"",#selector(pauseGame),icon:"pause.fill")
        pauseButton.accessibilityLabel = "Pause"
        sprintButton.accessibilityLabel = "Sprint"
        phoneButton.titleLabel?.adjustsFontSizeToFitWidth = true
        phoneButton.titleLabel?.minimumScaleFactor = 0.7
        lightButton.titleLabel?.font = .systemFont(ofSize:11,weight:.semibold)
        phoneButton.titleLabel?.font = .systemFont(ofSize:11,weight:.semibold)
        let safe = controls.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            lookSurface.leadingAnchor.constraint(equalTo:controls.centerXAnchor),lookSurface.trailingAnchor.constraint(equalTo:controls.trailingAnchor),lookSurface.topAnchor.constraint(equalTo:controls.topAnchor),lookSurface.bottomAnchor.constraint(equalTo:controls.bottomAnchor),
            stick.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:30),stick.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-26),stick.widthAnchor.constraint(equalToConstant:traitCollection.userInterfaceIdiom == .pad ? 192 : 160),stick.heightAnchor.constraint(equalTo:stick.widthAnchor),
            status.topAnchor.constraint(equalTo:safe.topAnchor,constant:16),status.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:22),status.trailingAnchor.constraint(lessThanOrEqualTo:phoneButton.leadingAnchor,constant:-10),
            objective.topAnchor.constraint(equalTo:status.bottomAnchor,constant:9),objective.leadingAnchor.constraint(equalTo:status.leadingAnchor),objective.widthAnchor.constraint(lessThanOrEqualTo:safe.widthAnchor,multiplier:0.78),
            pauseButton.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-20),pauseButton.topAnchor.constraint(equalTo:safe.topAnchor,constant:14),pauseButton.widthAnchor.constraint(equalToConstant:52),
            message.centerXAnchor.constraint(equalTo:safe.centerXAnchor),message.topAnchor.constraint(equalTo:objective.bottomAnchor,constant:17),message.widthAnchor.constraint(lessThanOrEqualTo:safe.widthAnchor,multiplier:0.80),
            use.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-24),use.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-28),use.widthAnchor.constraint(equalToConstant:116),
            crouchButton.trailingAnchor.constraint(equalTo:use.trailingAnchor),crouchButton.bottomAnchor.constraint(equalTo:use.topAnchor,constant:-10),crouchButton.widthAnchor.constraint(equalTo:use.widthAnchor),
            sprintButton.trailingAnchor.constraint(equalTo:use.trailingAnchor),sprintButton.bottomAnchor.constraint(equalTo:crouchButton.topAnchor,constant:-10),sprintButton.widthAnchor.constraint(equalTo:use.widthAnchor),
            lightButton.trailingAnchor.constraint(equalTo:pauseButton.leadingAnchor,constant:-8),lightButton.centerYAnchor.constraint(equalTo:pauseButton.centerYAnchor),lightButton.widthAnchor.constraint(equalToConstant:92),
            phoneButton.trailingAnchor.constraint(equalTo:lightButton.leadingAnchor,constant:-8),phoneButton.centerYAnchor.constraint(equalTo:pauseButton.centerYAnchor),phoneButton.widthAnchor.constraint(equalToConstant:112),
            hint.centerXAnchor.constraint(equalTo:controls.centerXAnchor),hint.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-14),hint.widthAnchor.constraint(equalTo:controls.widthAnchor,multiplier:0.35)])
        let crosshair = UILabel(); crosshair.text = "·"; crosshair.textColor = .white; crosshair.font = .systemFont(ofSize:28); crosshair.translatesAutoresizingMaskIntoConstraints = false; crosshair.isUserInteractionEnabled = false; controls.addSubview(crosshair)
        NSLayoutConstraint.activate([crosshair.centerXAnchor.constraint(equalTo:controls.centerXAnchor),crosshair.centerYAnchor.constraint(equalTo:controls.centerYAnchor)])
        shade.backgroundColor = .black
        menuArtwork.image = UIImage(named:"TitleArtwork-Empty.png")
        menuArtwork.contentMode = .scaleAspectFill; menuArtwork.clipsToBounds = true
        menuArtwork.frame = shade.bounds; menuArtwork.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        shade.addSubview(menuArtwork)
        let dim = UIView(frame:shade.bounds)
        dim.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        dim.isUserInteractionEnabled = false
        menuGradient.colors = [UIColor(white:0.012,alpha:0.98).cgColor,
                               UIColor(white:0.012,alpha:0.74).cgColor,
                               UIColor(white:0.012,alpha:0.14).cgColor]
        menuGradient.locations = [0,0.54,1]
        menuGradient.startPoint = CGPoint(x:0,y:0.4)
        menuGradient.endPoint = CGPoint(x:1,y:0.5)
        dim.layer.addSublayer(menuGradient)
        shade.addSubview(dim)
        label(eyebrow,12,UIColor(white:0.71,alpha:1)); eyebrow.text = "BROTHER STUDIOS"
        label(clockLabel,19,UIColor(red:0.93,green:0.42,blue:0.35,alpha:1)); clockLabel.text = "AT 3 AM"
        label(footer,11,UIColor(white:0.55,alpha:1)); footer.text = "HEADPHONES RECOMMENDED"
        footer.translatesAutoresizingMaskIntoConstraints = false; shade.addSubview(footer)
        NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo:shade.safeAreaLayoutGuide.leadingAnchor,constant:48),footer.bottomAnchor.constraint(equalTo:shade.safeAreaLayoutGuide.bottomAnchor,constant:-24)])
        menu.axis = .vertical; menu.spacing = 18; menu.alignment = .fill; menu.translatesAutoresizingMaskIntoConstraints = false; shade.addSubview(menu)
        titleLabel.font = vhs(64); titleLabel.textColor = UIColor(red:0.87,green:0.81,blue:0.7,alpha:1); titleLabel.numberOfLines = 0
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOffset = CGSize(width:0,height:3); titleLabel.layer.shadowOpacity = 0.9; titleLabel.layer.shadowRadius = 8
        detailLabel.font = vhs(17); detailLabel.numberOfLines = 0; detailLabel.textColor = UIColor(white:0.76,alpha:1)
        button(startButton,"Play",#selector(menuAction),icon:"play.fill")
        button(soundButton,"Sound on",#selector(toggleSound),icon:"speaker.wave.2.fill")
        button(helpButton,"Controls",#selector(showHelp),icon:"gamecontroller")
        button(newLayoutButton,"New layout",#selector(newLayout),icon:"shuffle")
        newLayoutButton.isHidden = true
        startButton.backgroundColor = UIColor(red:0.44,green:0.10,blue:0.085,alpha:0.96)
        startButton.layer.borderColor = UIColor(red:0.72,green:0.28,blue:0.24,alpha:1).cgColor
        startButton.contentHorizontalAlignment = .leading
        startButton.contentEdgeInsets = UIEdgeInsets(top:9,left:19,bottom:9,right:19)
        let secondary = UIStackView(arrangedSubviews:[helpButton,soundButton])
        secondary.axis = .horizontal
        secondary.spacing = 10
        secondary.distribution = .fillEqually
        for b in [soundButton,helpButton] {
            b.backgroundColor = UIColor(white:0.10,alpha:0.64)
            b.titleLabel?.font = .systemFont(ofSize:12,weight:.semibold)
        }
        retryActions.axis = .vertical
        retryActions.spacing = 9
        retryActions.distribution = .fillEqually
        for button in [startButton,newLayoutButton] {
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.69
            retryActions.addArrangedSubview(button)
        }
        for v in [eyebrow,titleLabel,clockLabel,detailLabel,retryActions,secondary] { menu.addArrangedSubview(v) }
        let safeMenu = shade.safeAreaLayoutGuide
        let preferred = menu.widthAnchor.constraint(equalTo:safeMenu.widthAnchor,multiplier:0.48)
        preferred.priority = .defaultHigh
        NSLayoutConstraint.activate([
            menu.leadingAnchor.constraint(equalTo:safeMenu.leadingAnchor,constant:34),
            menu.centerYAnchor.constraint(equalTo:safeMenu.centerYAnchor,constant:-11),
            preferred,
            menu.widthAnchor.constraint(lessThanOrEqualToConstant:605)
        ])
    }
    private func setupIntro() {
        introOverlay.frame = view.bounds
        introOverlay.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        introOverlay.isHidden = true
        view.addSubview(introOverlay)

        introCaption.font = .systemFont(ofSize:17,weight:.semibold)
        introCaption.textColor = UIColor(white:0.95,alpha:1)
        introCaption.numberOfLines = 0
        introCaption.textAlignment = .center
        introCaption.layer.shadowColor = UIColor.black.cgColor
        introCaption.layer.shadowOpacity = 1
        introCaption.layer.shadowRadius = 5
        introCaption.layer.shadowOffset = .zero

        let skip = introSkip
        button(skip,"Skip",#selector(skipIntro),icon:"forward.end.fill")
        endCard.textColor = UIColor(red:0.92,green:0.86,blue:0.76,alpha:1)
        endCard.textAlignment = .center
        endCard.numberOfLines = 0
        endCard.isHidden = true
        for item in [introCaption,introPhone,skip,endCard] {
            item.translatesAutoresizingMaskIntoConstraints = false
            introOverlay.addSubview(item)
        }
        let safe = introOverlay.safeAreaLayoutGuide
        let phoneWidth = introPhone.widthAnchor.constraint(equalTo:safe.heightAnchor,multiplier:0.36)
        phoneWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            introPhone.centerXAnchor.constraint(equalTo:safe.centerXAnchor),
            introPhone.centerYAnchor.constraint(equalTo:safe.centerYAnchor,constant:-8),
            phoneWidth,
            introPhone.widthAnchor.constraint(lessThanOrEqualToConstant:218),
            introPhone.heightAnchor.constraint(equalTo:introPhone.widthAnchor,multiplier:336.0/180.0),
            introPhone.bottomAnchor.constraint(lessThanOrEqualTo:introCaption.topAnchor,constant:-8),
            introCaption.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:18),
            introCaption.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-18),
            introCaption.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-24),
            skip.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-20),
            skip.topAnchor.constraint(equalTo:safe.topAnchor,constant:14),
            skip.widthAnchor.constraint(equalToConstant:88),
            endCard.centerXAnchor.constraint(equalTo:safe.centerXAnchor),
            endCard.centerYAnchor.constraint(equalTo:safe.centerYAnchor),
            endCard.widthAnchor.constraint(lessThanOrEqualTo:safe.widthAnchor,multiplier:0.86)
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
        world = SCNScene(); televisionScreen = nil; serviceKeyNode = nil; relayLights.removeAll(); lamps = []; lightPanels = []; thermalScreens = []; cupboards = []; fridgeHinge = nil; fridgeLamp = nil; world.background.contents = UIColor.black
        world.fogColor = UIColor(red:0.025,green:0.03,blue:0.035,alpha:1); world.fogStartDistance = 12; world.fogEndDistance = 35
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.color = UIColor(red:0.22,green:0.27,blue:0.36,alpha:1); ambient.light?.intensity = 240; world.rootNode.addChildNode(ambient)
        houseAmbient = ambient.light
        buildSurfaces()
        let extensionRooms = OpeningScene()
        extensionRooms.setLit(false)
        opening = extensionRooms
        world.rootNode.addChildNode(extensionRooms.root)
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
        for cell in House.closets { buildWardrobe(at:cell) }
        for site in House.cupboards { buildCupboard(at:site) }
        buildStoryFixtures()
        buildHouseDecor()
        let panel = point(House.panel)
        box(SCNVector3(0.89,1.24,0.28),SCNVector3(panel.x,1.45,panel.z+0.6),UIColor(white:0.21,alpha:1))
        box(SCNVector3(0.78,0.95,0.05),SCNVector3(panel.x,1.40,panel.z+0.445),.darkGray)
        let frame = box(SCNVector3(0.82,0.10,0.025),SCNVector3(panel.x,1.93,panel.z+0.435),.darkGray)
        frame.geometry?.firstMaterial?.specular.contents = UIColor(white:0.35,alpha:1)
        for x in [Float(-0.24),0,0.24] {
            box(SCNVector3(0.16,0.38,0.035),SCNVector3(panel.x+x,1.36,panel.z+0.408),.black)
            for y in [Float(1.22),1.50] {
                box(SCNVector3(0.095,0.047,0.041),SCNVector3(panel.x+x,y,panel.z+0.388),UIColor(red:0.73,green:0.51,blue:0.23,alpha:1))
            }
        }
        box(SCNVector3(0.12,0.12,0.06),SCNVector3(panel.x,1.83,panel.z+0.44),.systemRed,glow:true)
        buildExit()
        enemy = SCNNode()
        enemy.position = point(House.enemy)
        world.rootNode.addChildNode(enemy)
        let coat = UIColor(red:0.115,green:0.127,blue:0.115,alpha:1)
        let cloth = UIColor(red:0.095,green:0.088,blue:0.082,alpha:1)
        let skin = UIColor(red:0.37,green:0.29,blue:0.24,alpha:1)
        let torso = WaleedMesh.sculpt([
            .init(y:0.93,width:0.16,depth:0.12),
            .init(y:0.98,width:0.28,depth:0.17),
            .init(y:1.16,width:0.30,depth:0.19,shift:0.02),
            .init(y:1.38,width:0.29,depth:0.18),
            .init(y:1.65,width:0.36,depth:0.24,shift:0.015),
            .init(y:1.78,width:0.39,depth:0.21,shift:0.033),
            .init(y:1.90,width:0.30,depth:0.17,shift:0.02),
            .init(y:2.00,width:0.13,depth:0.12)
        ],material:material(coat))
        torso.name = "Waleed coat mesh"
        enemy.addChildNode(torso)
        for y in [Float(1.29),1.52] {
            box(SCNVector3(0.15,0.028,0.031),SCNVector3(0.18,y,-0.177),.darkGray,parent:enemy)
        }
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
        torch.light?.shadowMapSize = CGSize(width:1024,height:1024)
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
        thermalScreens.forEach { $0.isHidden = !televisionOn && patrolActivity != .television }
    }

    private func buildSurfaces() {
        let wall = material(UIColor(white:0.73,alpha:1))
        let hardwood = material(UIColor(red:0.39,green:0.25,blue:0.17,alpha:1))
        let tiles = HouseMaterials.make(.tile,tint:UIColor(red:0.83,green:0.89,blue:0.88,alpha:1))
        func floorKind(_ x:Int,_ z:Int) -> Bool {
            (x >= 9 && x <= 15 && z >= 1 && z <= 4) ||
            (x >= 1 && x <= 7 && z >= 11 && z <= 15)
        }
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
            let surfaces = (material.copy() as? SCNMaterial) ?? material
            surfaces.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(tiles),1,1)
            mesh.materials = [surfaces]
            let node = SCNNode(geometry:mesh)
            node.position = SCNVector3(x,y,z)
            world.rootNode.addChildNode(node)
        }
        for (z,row) in house.rows.enumerated() {
            var start = 0
            while start < row.count {
                if z == house.rows.count-1 && start == House.exit.x {
                    start += 1
                    continue
                }
                let solid = row[start] == "#"
                var end = start+1
                let tiled = floorKind(start,z)
                while end < row.count && (z != house.rows.count-1 || end != House.exit.x) &&
                      (row[end] == "#") == solid &&
                      (solid || floorKind(end,z) == tiled) { end += 1 }
                let t = House.tile, width = Float(end-start)*t
                let x = Float(start)*t+width/2, y = (Float(z)+0.5)*t
                if solid {
                    strip(wall,width,3.3,t,x,1.65,y,end-start)
                    strip(trim,width,0.14,t+0.018,x,0.10,y,1)
                } else {
                    strip(tiled ? tiles : hardwood,width,0.08,t,x,-0.04,y,end-start)
                }
                start = end
            }
        }
        let span = Float(house.rows.count)*House.tile
        strip(ceiling,span,0.08,span,span/2,3.34,span/2,1)
    }

    private func buildDoors() {
        innerDoors.removeAll()
        let painted = UIColor(red:0.61,green:0.54,blue:0.43,alpha:1)
        let wood = UIColor(red:0.34,green:0.19,blue:0.11,alpha:1)
        let raised = UIColor(red:0.42,green:0.25,blue:0.15,alpha:1)
        let brass = UIColor(red:0.71,green:0.53,blue:0.26,alpha:1)
        let oak = HouseMaterials.make(.oak,tint:UIColor(red:0.67,green:0.55,blue:0.45,alpha:1))
        for doorway in house.doorways {
            let frame = SCNNode()
            frame.position = point(doorway.cell)
            frame.eulerAngles.y = doorway.rotated ? .pi/2 : 0
            world.rootNode.addChildNode(frame)
            for x in [Float(-0.985),0.985] {
                box(SCNVector3(0.43,2.425,0.32),SCNVector3(x,1.2125,0),painted,parent:frame)
            }
            box(SCNVector3(2.40,0.875,0.32),SCNVector3(0,2.8625,0),painted,parent:frame)
            box(SCNVector3(1.58,0.024,0.32),SCNVector3(0,0.012,0),wood,parent:frame)
            let hinge = SCNNode()
            hinge.position = SCNVector3(-0.77,0,0)
            frame.addChildNode(hinge)
            let leaf = box(SCNVector3(1.50,2.37,0.09),SCNVector3(0.75,1.20,0),wood,parent:hinge)
            leaf.geometry?.materials = [oak]
            for side in [Float(-1),1] {
                for y in [Float(0.56),1.73] {
                    box(SCNVector3(1.14,0.87,0.031),SCNVector3(0.75,y,0.057*side),raised,parent:hinge)
                    let panel = box(SCNVector3(0.98,0.73,0.017),SCNVector3(0.75,y,0.078*side),wood,parent:hinge)
                    panel.geometry?.materials = [oak]
                }
                box(SCNVector3(0.068,0.18,0.016),SCNVector3(1.34,1.05,0.058*side),brass,parent:hinge)
                let knob = sphere(0.045,SCNVector3(1.34,1.07,0.097*side),brass,hinge)
                knob.scale.z = 0.72
            }
            innerDoors.append((hinge,frame.position))
        }
    }

    private func buildExit() {
        let frame = SCNNode()
        frame.position = point(House.exit)
        frame.position.z += House.tile/2
        frame.name = "Green exit and back yard"
        world.rootNode.addChildNode(frame)
        let plaster = UIColor(red:0.43,green:0.43,blue:0.37,alpha:1)
        let green = UIColor(red:0.16,green:0.34,blue:0.28,alpha:1)
        let brass = UIColor(red:0.62,green:0.43,blue:0.21,alpha:1)
        let night = UIColor(red:0.16,green:0.20,blue:0.22,alpha:1)
        for x in [Float(-1.015),1.015] {
            box(SCNVector3(0.37,2.48,2.4),SCNVector3(x,1.24,1.2),plaster,parent:frame)
            box(SCNVector3(0.12,2.48,0.16),SCNVector3(x/1.15,1.24,-0.06),green,parent:frame)
        }
        box(SCNVector3(2.4,0.82,2.4),SCNVector3(0,2.89,1.2),plaster,parent:frame)
        box(SCNVector3(1.86,0.12,0.16),SCNVector3(0,2.42,-0.07),green,parent:frame)
        exitLight = box(SCNVector3(0.66,0.15,0.045),SCNVector3(0,2.68,-0.032),.systemRed,parent:frame,glow:true)
        exitHinge = SCNNode()
        exitHinge.name = "Exit door hinge"
        exitHinge.position = SCNVector3(-0.82,0,0.14)
        frame.addChildNode(exitHinge)
        box(SCNVector3(1.64,2.32,0.11),SCNVector3(0.82,1.17,0),green,parent:exitHinge)
        for z in [Float(-0.062),0.062] {
            for y in [Float(0.58),1.72] {
                box(SCNVector3(1.24,0.77,0.027),SCNVector3(0.82,y,z),UIColor(red:0.12,green:0.26,blue:0.22,alpha:1),parent:exitHinge)
            }
            sphere(0.055,SCNVector3(1.39,1.06,z*1.70),brass,exitHinge)
        }
        box(SCNVector3(13,0.18,19),SCNVector3(0,-0.20,9.5),night,parent:frame)
        let path = box(SCNVector3(2.18,0.13,9.75),SCNVector3(0,-0.067,4.875),night,parent:frame)
        path.geometry?.materials = [HouseMaterials.make(.tile,tint:night)]
        let fence = UIColor(red:0.15,green:0.18,blue:0.16,alpha:1)
        for side in [Float(-1),1] {
            box(SCNVector3(0.15,1.54,10),SCNVector3(side*3.08,0.67,7.46),fence,parent:frame)
            for z in [Float(4.4),7.1,10.2] {
                let hedge = sphere(0.68,SCNVector3(side*2.42,0.28,z),fence,frame)
                hedge.scale = SCNVector3(0.84,0.74,1.65)
                box(SCNVector3(0.15,1.66,0.18),SCNVector3(side*2.98,0.73,z),fence,parent:frame)
            }
        }
        box(SCNVector3(6.25,1.54,0.16),SCNVector3(0,0.67,12.45),fence,parent:frame)
        box(SCNVector3(0.25,0.20,0.16),SCNVector3(1.14,2.23,2.49),brass,parent:frame)
        box(SCNVector3(0.17,0.09,0.13),SCNVector3(1.14,2.12,2.50),UIColor(red:0.91,green:0.70,blue:0.38,alpha:1),parent:frame,glow:true)
        let porch = SCNNode()
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red:0.94,green:0.77,blue:0.53,alpha:1)
        light.intensity = 525
        light.attenuationEndDistance = 6
        porch.light = light
        porch.position = SCNVector3(1.14,2.04,2.77)
        frame.addChildNode(porch)
    }

    private func moveDoors(dt:Float) {
        for door in innerDoors {
            let approaching = distance(camera.position,door.center) < 3.8 || distance(enemy.position,door.center) < 3.8
            let angle: Float = approaching ? -1.61 : 0
            door.pivot.eulerAngles.y += (angle-door.pivot.eulerAngles.y)*min(1,dt*9)
        }
    }

    private func wardrobeCenter(_ cell:Cell) -> SCNVector3 {
        let p = point(cell)
        return SCNVector3(p.x+(cell.x < 8 ? -0.62 : 0.62),0,p.z)
    }

    private func buildWardrobe(at cell:Cell) {
        let cabinet = SCNNode()
        cabinet.position = wardrobeCenter(cell)
        cabinet.eulerAngles.y = cell.x < 8 ? .pi/2 : -.pi/2
        world.rootNode.addChildNode(cabinet)
        let oak = UIColor(red:0.21,green:0.13,blue:0.08,alpha:1)
        let lining = UIColor(red:0.16,green:0.10,blue:0.064,alpha:1)
        let oakFinish = HouseMaterials.make(.oak,tint:UIColor(red:0.55,green:0.41,blue:0.29,alpha:1))
        box(SCNVector3(1.56,2.35,0.068),SCNVector3(0,1.18,-0.484),lining,parent:cabinet)
        for y in [Float(0.045),2.33] {
            box(SCNVector3(1.58,0.09,0.99),SCNVector3(0,y,0),oak,parent:cabinet)
        }
        for sign in [Float(-1),1] {
            box(SCNVector3(0.074,2.34,0.99),SCNVector3(sign*0.76,1.16,0),oak,parent:cabinet)
            let leaf = box(SCNVector3(0.69,2.28,0.063),SCNVector3(sign*0.414,1.18,0.468),oak,parent:cabinet)
            leaf.geometry?.materials = [oakFinish]
            box(SCNVector3(0.048,0.15,0.069),SCNVector3(sign*0.14,1.14,0.521),.systemYellow,parent:cabinet,glow:true)
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

    private func buildCupboard(at site:House.WallSite) {
        let cell = site.cell
        let root = SCNNode()
        let width = House.cupboardWidth
        let depth = House.cupboardDepth
        root.name = "Searchable cupboard"
        root.position = point(cell)
        root.position.x += Float(site.wallX)*House.cupboardOffset
        root.position.z += Float(site.wallZ)*House.cupboardOffset
        root.eulerAngles.y = site.facing
        world.rootNode.addChildNode(root)
        let wood = UIColor(red:0.34,green:0.23,blue:0.15,alpha:1)
        let oak = HouseMaterials.make(.oak,tint:wood)
        let brass = UIColor(red:0.68,green:0.54,blue:0.33,alpha:1)
        box(SCNVector3(width,1.28,0.05),SCNVector3(0,0.65,-depth/2+0.025),wood,parent:root)
        box(SCNVector3(width-0.10,0.10,depth-0.03),SCNVector3(0,0.057,0),wood,parent:root)
        for y in [Float(0.15),0.68,1.28] {
            let shelf = box(SCNVector3(width,0.056,depth),SCNVector3(0,y,0),wood,parent:root)
            shelf.geometry?.materials = [oak]
        }
        var doors = [SCNNode]()
        for side in [Float(-1),1] {
            box(SCNVector3(0.054,1.08,depth),SCNVector3(side*(width/2-0.027),0.72,0),wood,parent:root)
            let hinge = SCNNode()
            hinge.position = SCNVector3(side*(width/2-0.026),0,depth/2-0.013)
            root.addChildNode(hinge)
            let center = -side*0.243
            let leaf = box(SCNVector3(0.477,1.08,0.035),SCNVector3(center,0.717,0.014),wood,parent:hinge)
            leaf.geometry?.materials = [oak]
            box(SCNVector3(0.37,0.93,0.015),SCNVector3(center,0.717,0.037),wood,parent:hinge)
            box(SCNVector3(0.04,0.14,0.047),SCNVector3(-side*0.411,0.79,0.064),brass,parent:hinge)
            doors.append(hinge)
        }
        let tin = UIColor(red:0.38,green:0.43,blue:0.39,alpha:1)
        for x in [Float(-0.29),0.31] {
            box(SCNVector3(0.15,0.18,0.18),SCNVector3(x,0.27,-0.05),tin,parent:root)
            box(SCNVector3(0.16,0.027,0.19),SCNVector3(x,0.37,-0.05),.darkGray,parent:root)
        }
        let fuse = house.fuses.contains(cell) ? makeFuse(at:SCNVector3(0,0.764,-0.015),parent:root) : nil
        fuse?.isHidden = true
        let frontX = -Float(site.wallX)
        let frontZ = -Float(site.wallZ)
        let front = SCNVector3(root.position.x+frontX*(depth/2+0.08),0.79,root.position.z+frontZ*(depth/2+0.08))
        cupboards.append(Cupboard(cell:cell,front:front,doors:doors,forwardX:frontX,forwardZ:frontZ,fuse:fuse))
    }

    private func makeFuse(at p:SCNVector3,parent:SCNNode) -> SCNNode {
        let cartridge = SCNNode()
        cartridge.position = p
        parent.addChildNode(cartridge)
        cartridge.name = "Glass safety fuse"
        let casing = UIColor(red:0.55,green:0.77,blue:0.76,alpha:1)
        let metal = UIColor(red:0.64,green:0.66,blue:0.64,alpha:1)
        let shell = UIColor(red:0.10,green:0.30,blue:0.31,alpha:1)
        box(SCNVector3(0.37,0.097,0.16),SCNVector3Zero,shell,parent:cartridge)
        let tube = SCNCylinder(radius:0.053,height:0.32)
        tube.radialSegmentCount = 14
        let glass = material(casing)
        glass.transparency = 0.58
        glass.specular.contents = UIColor(white:0.75,alpha:1)
        glass.shininess = 70
        tube.materials = [glass]
        let body = SCNNode(geometry:tube)
        body.eulerAngles.z = .pi/2
        cartridge.addChildNode(body)
        let wire = SCNCylinder(radius:0.008,height:0.29)
        wire.materials = [material(UIColor(red:0.76,green:0.59,blue:0.34,alpha:1))]
        let wireNode = SCNNode(geometry:wire)
        wireNode.position.y = 0.012
        wireNode.eulerAngles.z = .pi/2
        cartridge.addChildNode(wireNode)
        for i in 0..<5 {
            let band = SCNTorus(ringRadius:0.022,pipeRadius:0.003)
            band.ringSegmentCount = 12
            band.pipeSegmentCount = 5
            band.materials = wire.materials
            let ring = SCNNode(geometry:band)
            ring.position.x = Float(i-2)*0.041
            ring.eulerAngles.z = .pi/2
            cartridge.addChildNode(ring)
        }
        for x in [Float(-0.166),0.166] {
            let cap = SCNCylinder(radius:0.058,height:0.079)
            cap.radialSegmentCount = 14
            let finish = material(metal)
            finish.specular.contents = UIColor(white:0.62,alpha:1)
            finish.shininess = 55
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
        let quilt = box(SCNVector3(1.55,0.075,1.37),SCNVector3(p.x,0.62,p.z+0.35),blanket)
        quilt.geometry?.materials = [HouseMaterials.make(.cloth,tint:blanket)]
        let seam = blanket.withAlphaComponent(0.7)
        for index in -2...2 {
            let z = p.z+0.35+Float(index)*0.24
            box(SCNVector3(1.51,0.008,0.015),SCNVector3(p.x,0.661,z),seam)
        }
        box(SCNVector3(0.067,0.22,1.36),SCNVector3(p.x-0.75,0.51,p.z+0.35),blanket)
        box(SCNVector3(0.067,0.22,1.36),SCNVector3(p.x+0.75,0.51,p.z+0.35),blanket)
        sideTable(at:SCNVector3(p.x-1.50,0,p.z-0.64))
    }

    private func sofa(at p:SCNVector3) {
        let frame = SCNNode()
        frame.position = p
        frame.eulerAngles.y = .pi
        world.rootNode.addChildNode(frame)
        let fabric = UIColor(red:0.34,green:0.42,blue:0.36,alpha:1)
        let cushions = UIColor(red:0.42,green:0.50,blue:0.43,alpha:1)
        let upholstery = HouseMaterials.make(.cloth,tint:fabric)
        let couch = box(SCNVector3(2.58,0.31,0.91),SCNVector3(0,0.30,0),fabric,parent:frame)
        couch.geometry?.materials = [upholstery]
        box(SCNVector3(2.56,0.66,0.17),SCNVector3(0,0.68,-0.38),fabric,parent:frame)
        for x in [Float(-1.14),1.14] {
            box(SCNVector3(0.26,0.43,0.91),SCNVector3(x,0.55,0),fabric,parent:frame)
        }
        for x in [Float(-0.68),0,0.68] {
            let seat = box(SCNVector3(0.65,0.12,0.63),SCNVector3(x,0.50,0.065),cushions,parent:frame)
            seat.geometry?.materials = [upholstery]
            box(SCNVector3(0.65,0.40,0.15),SCNVector3(x,0.76,-0.235),cushions,parent:frame)
        }
    }

    private func furnishRoom(_ kind: RoomKind, at p: SCNVector3) {
        let wall = p.z - 1.02
        let darkMetal = UIColor(white:0.15,alpha:1)
        let enamel = UIColor(red:0.64,green:0.69,blue:0.62,alpha:1)
        switch kind {
        case .bedroom:
            bed(at:p,blanket:UIColor(red:0.29,green:0.14,blue:0.19,alpha:1))
        case .kitchen:
            buildKitchen(at:p)
            box(SCNVector3(1.04,2.26,0.39),SCNVector3(p.x,1.13,wall+0.09),enamel)
            box(SCNVector3(0.92,1.97,0.019),SCNVector3(p.x,1.11,wall+0.288),darkMetal)
            for y in [Float(0.53),0.94,1.36] {
                box(SCNVector3(0.90,0.049,0.16),SCNVector3(p.x,y,wall+0.315),.lightGray)
            }
            let hinge = SCNNode()
            hinge.position = SCNVector3(p.x+0.51,0,wall+0.393)
            world.rootNode.addChildNode(hinge)
            fridgeHinge = hinge
            box(SCNVector3(1.02,2.18,0.093),SCNVector3(-0.51,1.12,0),enamel,parent:hinge)
            box(SCNVector3(1.01,0.039,0.016),SCNVector3(-0.51,1.54,0.05),darkMetal,parent:hinge)
            for y in [Float(1.24),1.77] {
                box(SCNVector3(0.07,0.24,0.08),SCNVector3(-0.87,y,0.067),darkMetal,parent:hinge)
            }
            let bulb = SCNNode()
            let light = SCNLight()
            light.type = .omni
            light.color = UIColor(red:0.72,green:0.84,blue:0.96,alpha:1)
            light.intensity = 0
            light.attenuationEndDistance = 2.9
            bulb.light = light
            bulb.position = SCNVector3(p.x,1.75,wall+0.52)
            fridgeLamp = light
            world.rootNode.addChildNode(bulb)
        case .lounge:
            let tv = point(House.loungeTV)
            let couch = point(House.sofaStop)
            let standZ = tv.z-0.79
            box(SCNVector3(2.14,0.63,0.61),SCNVector3(tv.x,0.315,standZ),UIColor(red:0.37,green:0.22,blue:0.14,alpha:1))
            for x in [Float(-0.53),0.53] {
                box(SCNVector3(0.69,0.43,0.02),SCNVector3(tv.x+x,0.36,standZ+0.312),.darkGray)
            }
            sofa(at:SCNVector3(couch.x,0,couch.z+0.73))
            for x in [Float(-0.46),0.46] {
                box(SCNVector3(0.11,0.10,0.38),SCNVector3(tv.x+x,0.682,standZ),darkMetal)
            }
            let television = box(SCNVector3(1.48,0.94,0.17),SCNVector3(tv.x,1.19,standZ),darkMetal)
            television.name = "Lounge television"
            let screen = box(SCNVector3(1.31,0.75,0.018),SCNVector3(tv.x,1.20,standZ+0.091),UIColor(red:0.14,green:0.43,blue:0.48,alpha:1),glow:true)
            thermalScreens.append(screen)
            screen.isHidden = true
            televisionScreen = screen
        case .study: // Study: crowded shelves.
            let shelves = point(House.studyShelves)
            let back = shelves.z-0.92
            for y in [Float(0.75), 1.37, 1.99] {
                let shelf = box(SCNVector3(1.78,0.10,0.43),SCNVector3(shelves.x,y,back),UIColor(red:0.26,green:0.14,blue:0.075,alpha:1))
                shelf.name = "Study shelf"
                for i in 0..<6 {
                    let height: Float = i.isMultiple(of:2) ? 0.34 : 0.42
                    let color: UIColor = i.isMultiple(of:3) ? .systemBrown : .darkGray
                    box(SCNVector3(0.18,height,0.26),SCNVector3(shelves.x-0.63+Float(i)*0.25,y+0.05+height/2,back+0.02),color)
                }
            }
        case .laundry: // Laundry: circular washer door.
            let washer = point(House.laundryWasher)
            let casework = box(SCNVector3(1.2,1.25,0.43),SCNVector3(washer.x,0.625,washer.z-0.91),enamel)
            casework.name = "Laundry washer"
            let door = sphere(0.40,SCNVector3(washer.x,0.58,washer.z-0.68),darkMetal,world.rootNode)
            door.scale.z = 0.10
            box(SCNVector3(0.25,0.055,0.02),SCNVector3(washer.x+0.27,1.10,washer.z-0.685),.systemOrange,glow:true)
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
            let frame = UIColor(red:0.28,green:0.20,blue:0.15,alpha:1)
            let trim = UIColor(red:0.47,green:0.38,blue:0.31,alpha:1)
            let linen = UIColor(red:0.34,green:0.27,blue:0.30,alpha:1)
            let cloth = HouseMaterials.make(.cloth,tint:linen)
            box(SCNVector3(3.27,1.52,0.13),SCNVector3(p.x,1.95,wall),frame)
            let pane = box(SCNVector3(3.09,1.34,0.022),SCNVector3(p.x,1.95,wall+0.075),.black)
            pane.name = "Rain window"
            pane.geometry?.materials = [HouseMaterials.make(.window)]
            box(SCNVector3(3.38,0.10,0.31),SCNVector3(p.x,1.22,wall+0.099),trim)
            for x in [Float(-0.52),0.52] {
                box(SCNVector3(0.059,1.35,0.055),SCNVector3(p.x+x,1.95,wall+0.10),trim)
            }
            box(SCNVector3(3.10,0.057,0.056),SCNVector3(p.x,1.91,wall+0.10),trim)
            for sign in [Float(-1),1] {
                for index in 0..<6 {
                    let x = p.x+sign*(1.30+Float(index)*0.079)
                    let fold = box(SCNVector3(0.096,1.79,0.13),
                                   SCNVector3(x,1.82,wall+0.20+Float(index%2)*0.045),linen)
                    fold.geometry?.materials = [cloth]
                }
            }
            let moon = SCNNode()
            moon.position = SCNVector3(p.x,2.62,wall+0.38)
            moon.eulerAngles = SCNVector3(-0.62,.pi,0)
            let light = SCNLight()
            light.type = .spot
            light.color = UIColor(red:0.40,green:0.57,blue:0.79,alpha:1)
            light.intensity = 125
            light.spotInnerAngle = 28
            light.spotOuterAngle = 68
            light.attenuationEndDistance = 8
            moon.light = light
            world.rootNode.addChildNode(moon)
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

    private func buildStoryFixtures() {
        let oak = UIColor(red:0.32,green:0.21,blue:0.16,alpha:1)
        let metal = UIColor(red:0.26,green:0.31,blue:0.30,alpha:1)
        let desk = point(House.serviceDesk)
        let deskZ = desk.z-0.88
        box(SCNVector3(1.52,0.11,0.52),SCNVector3(desk.x,0.82,deskZ),oak)
        for x in [Float(-0.66),0.66] {
            box(SCNVector3(0.13,0.78,0.49),SCNVector3(desk.x+x,0.39,deskZ),oak)
        }
        box(SCNVector3(0.67,0.48,0.13),SCNVector3(desk.x-0.23,1.17,deskZ-0.15),metal)
        box(SCNVector3(0.58,0.36,0.022),SCNVector3(desk.x-0.23,1.19,deskZ-0.074),
            UIColor(red:0.15,green:0.29,blue:0.23,alpha:1),glow:true)
        box(SCNVector3(0.52,0.04,0.22),SCNVector3(desk.x-0.23,0.90,deskZ+0.13),metal)
        let key = SCNNode()
        key.name = "Service cabinet key"
        key.position = SCNVector3(desk.x+0.43,0.91,deskZ+0.04)
        world.rootNode.addChildNode(key)
        let brass = UIColor(red:0.74,green:0.54,blue:0.26,alpha:1)
        let ring = SCNTorus(ringRadius:0.063,pipeRadius:0.013)
        ring.materials = [material(brass,glow:true)]
        key.addChildNode(SCNNode(geometry:ring))
        box(SCNVector3(0.21,0.023,0.034),SCNVector3(-0.139,0,0),brass,parent:key)
        box(SCNVector3(0.038,0.023,0.07),SCNVector3(-0.225,0,0.024),brass,parent:key)
        serviceKeyNode = key

        for (index,cell) in [House.kitchenRelay,House.laundryRelay].enumerated() {
            let p = point(cell)
            let panel = SCNNode()
            panel.name = "Security relay \(index+1)"
            panel.position = SCNVector3(p.x+(index == 0 ? 1.08 : 0),1.32,p.z+(index == 0 ? 0 : 1.04))
            panel.eulerAngles.y = index == 0 ? -.pi/2 : .pi
            world.rootNode.addChildNode(panel)
            box(SCNVector3(0.53,0.60,0.14),SCNVector3Zero,metal,parent:panel)
            box(SCNVector3(0.14,0.24,0.10),SCNVector3(0,-0.08,0.09),oak,parent:panel)
            relayLights[cell] = box(SCNVector3(0.095,0.06,0.045),SCNVector3(0.15,0.16,0.091),.systemRed,parent:panel,glow:true)
        }
    }

    private func buildHouseDecor() {
        let wood = UIColor(red:0.30,green:0.19,blue:0.13,alpha:1)
        let pottery = UIColor(red:0.38,green:0.24,blue:0.19,alpha:1)
        let green = UIColor(red:0.16,green:0.28,blue:0.20,alpha:1)
        for (index,site) in House.decorationSites.enumerated() {
            let fixture = SCNNode()
            fixture.position = point(site.cell)
            fixture.position.x += Float(site.wallX)*0.96
            fixture.position.z += Float(site.wallZ)*0.96
            fixture.eulerAngles.y = site.facing
            world.rootNode.addChildNode(fixture)
            if index.isMultiple(of:2) {
                let pot = SCNCone(topRadius:0.21,bottomRadius:0.16,height:0.31)
                pot.radialSegmentCount = 12
                pot.materials = [material(pottery)]
                let node = SCNNode(geometry:pot)
                node.position.y = 0.155
                fixture.addChildNode(node)
                for growth in 0..<6 {
                    let theta = Float(growth)*1.13
                    let leaf = sphere(0.13,SCNVector3(cos(theta)*0.14,0.40+Float(growth)*0.085,sin(theta)*0.14),green,fixture)
                    leaf.scale = SCNVector3(0.56,1.52,0.24)
                    leaf.eulerAngles = SCNVector3(0.26,theta,0.55)
                }
            } else {
                box(SCNVector3(0.42,0.74,0.42),SCNVector3(0,0.38,0),wood,parent:fixture)
                box(SCNVector3(0.27,0.045,0.33),SCNVector3(0,0.801,0.028),pottery,parent:fixture)
                let vase = sphere(0.11,SCNVector3(0.10,0.92,-0.06),green,fixture)
                vase.scale = SCNVector3(0.66,1.10,0.66)
            }
            box(SCNVector3(0.63,0.45,0.037),SCNVector3(0,1.57,-0.20),wood,parent:fixture)
            let print = box(SCNVector3(0.53,0.35,0.016),SCNVector3(0,1.57,-0.175),green,parent:fixture)
            print.geometry?.firstMaterial?.diffuse.contents = HouseMaterials.make(.window).diffuse.contents
        }
    }

    private func newsArt() -> UIImage {
        UIGraphicsImageRenderer(size:CGSize(width:480,height:270)).image { renderer in
            let context = renderer.cgContext
            UIColor(red:0.07,green:0.14,blue:0.20,alpha:1).setFill()
            context.fill(CGRect(x:0,y:0,width:480,height:270))
            UIColor(red:0.15,green:0.28,blue:0.37,alpha:1).setFill()
            context.fill(CGRect(x:270,y:0,width:210,height:270))
            UIColor(white:0.065,alpha:1).setFill()
            context.fillEllipse(in:CGRect(x:348,y:47,width:53,height:72))
            context.fillEllipse(in:CGRect(x:320,y:107,width:109,height:112))
            UIColor(red:0.63,green:0.12,blue:0.12,alpha:1).setFill()
            context.fill(CGRect(x:0,y:179,width:480,height:62))
            let lines: [(String,CGPoint,CGFloat)] = [
                ("NIGHT REPORT",CGPoint(x:25,y:30),20),
                ("PUBLIC SAFETY",CGPoint(x:25,y:86),26),
                ("BREAKING  ·  WALEED STILL AT LARGE",CGPoint(x:22,y:196),21),
                ("Stay indoors. Lock every entrance.",CGPoint(x:24,y:246),15)
            ]
            for (line,position,size) in lines {
                (line as NSString).draw(at:position,withAttributes:[
                    .font:UIFont.systemFont(ofSize:size,weight:.semibold),
                    .foregroundColor:UIColor(white:0.97,alpha:1)
                ])
            }
        }
    }

    private func useTelevision() {
        guard let screen = televisionScreen else { return }
        if newsStarted != nil {
            tell("The emergency bulletin is still playing.")
            return
        }
        televisionOn.toggle()
        screen.isHidden = !televisionOn
        if televisionOn {
            let screenMaterial = material(.white)
            let picture = newsArt()
            screenMaterial.diffuse.contents = picture
            screenMaterial.emission.contents = picture
            screen.geometry?.materials = [screenMaterial]
            newsStarted = elapsed
            newsLine = -1
            updateBulletin()
        } else {
            play("door-latch")
        }
    }

    private func updateBulletin() {
        guard let start = newsStarted else { return }
        let time = elapsed-start
        let line = min(3,Int(time/6.6))
        guard line != newsLine else { return }
        newsLine = line
        if line == bulletin.count {
            newsStarted = nil
            if story.advance(.watchBroadcast) {
                enemy.isHidden = false
                enemyAwake = false
                nextCall = elapsed+29
                phoneButton.isHidden = false
                updatePhoneButton()
                nextHello = elapsed+20
                tell("Find three fuses in the cupboards, then use the red security panel.",duration:8)
            }
            return
        }
        tell("TV: "+bulletin[line],duration:6.5)
        guard soundEnabled else { return }
        phoneVoice.stopSpeaking(at:.immediate)
        let voice = AVSpeechUtterance(string:bulletin[line])
        voice.voice = AVSpeechSynthesisVoice(language:"en-GB")
        voice.rate = 0.49
        voice.volume = 0.9
        phoneVoice.speak(voice)
    }

    @discardableResult
    private func playRoomSound(_ source:SCNAudioSource,at position:SCNVector3,duration:TimeInterval = 3) -> SCNNode {
        let node = SCNNode()
        node.name = "roomEffect"
        node.position = position
        world.rootNode.addChildNode(node)
        node.addAudioPlayer(SCNAudioPlayer(source:source))
        node.runAction(.sequence([.wait(duration:duration),.removeFromParentNode()]))
        return node
    }

    private func tripFloorboard() -> Bool {
        let p = camera.position
        let current = House.cell(p.x,p.z)
        let trap = traps.contains(current) && distance(p,point(current)) < 0.84 ? current : nil
        defer { lastTrap = trap }
        guard let trap, trap != lastTrap, !hidden, elapsed >= nextTrap else { return false }
        nextTrap = elapsed+3.5
        players["door-latch"]?.volume = 0.44
        play("door-latch")
        UIImpactFeedbackGenerator(style:.light).impactOccurred()
        return distance(p,enemy.position) < 27
    }

    private func makeFace() -> (head: SCNNode, eyes: [SCNNode], jaw: SCNNode) {
        let head = SCNNode()
        let skin = UIColor(red:0.42,green:0.38,blue:0.30,alpha:1)
        let hood = sphere(0.35,SCNVector3(0,0.085,0.105),UIColor(white:0.074,alpha:1),head)
        hood.scale = SCNVector3(1.0,1.11,0.83)
        let skull = WaleedMesh.sculpt([
            .init(y:-0.26,width:0.057,depth:0.075),
            .init(y:-0.20,width:0.168,depth:0.15,shift:-0.028),
            .init(y:-0.125,width:0.213,depth:0.205,shift:-0.012),
            .init(y:-0.040,width:0.256,depth:0.238),
            .init(y:0.064,width:0.244,depth:0.238),
            .init(y:0.148,width:0.249,depth:0.255),
            .init(y:0.238,width:0.234,depth:0.232,shift:0.024),
            .init(y:0.299,width:0.181,depth:0.19,shift:0.038),
            .init(y:0.342,width:0.045,depth:0.050,shift:0.051)
        ],material:material(skin))
        skull.name = "Waleed sculpted face"
        head.addChildNode(skull)
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
            let ear = sphere(0.064,SCNVector3(x*2.18,0.015,-0.009),skin,head)
            ear.scale = SCNVector3(0.49,1.09,0.75)
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
        let panel = UIAlertController(title:"HOW TO SURVIVE",message:"Left thumb: move. RUN toggles sprint. Drag the right side to look.\n\nCrouch to move quietly. Waleed can still spot you up close. Run stands you up. Follow the current objective and use the action button to interact.\n\nCALL WALEED rings his phone in another room. HANG UP before he traces you. SILENCE incoming calls and break line of sight before hiding.\n\nUse the steel shelter in the study when you can reach it safely. Some boards will give you away. Read notes for clues.\n\nContains sudden sounds and jumpscares.",preferredStyle:.alert)
        panel.addAction(UIAlertAction(title:"GOT IT",style:.default))
        present(panel,animated:true)
    }
    private func stopSceneAudio() {
        world.rootNode.childNodes.filter { $0.name == "roomEffect" }.forEach {
            $0.removeAllAudioPlayers()
            $0.removeFromParentNode()
        }
        remoteRing?.removeAllAudioPlayers()
    }

    private func resumeSceneAudio() {
        guard soundEnabled else { return }
        if let ringtone { remoteRing?.addAudioPlayer(SCNAudioPlayer(source:ringtone)) }
        if !televisionOn, patrolActivity == .television, let source = televisionBuzz, patrolPauseUntil > elapsed {
            patrolTVAudio = playRoomSound(source,at:point(House.loungeTV,y:1.20),
                                          duration:TimeInterval(patrolPauseUntil-elapsed))
        }
    }

    private func ambientBurp() {
        guard soundEnabled, let source = burpSources.randomElement() else { return }
        guard enemyAwake && distance(enemy.position,camera.position) < 12 else { return }
        playRoomSound(source,at:SCNVector3(enemy.position.x,1.4,enemy.position.z))
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
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback,mode:.default,options:[.mixWithOthers])
        if soundEnabled { try? session.setActive(true) }
        for i in 1...3 {
            if let source = SCNAudioSource(fileNamed:"burp\(i).wav") {
                source.isPositional = true; source.shouldStream = false; source.volume = 1
                source.load(); burpSources.append(source)
            }
        }
        activityCreak = SCNAudioSource(fileNamed:"door-latch.wav")
        televisionBuzz = SCNAudioSource(fileNamed:"tv-buzz.wav")
        for source in [activityCreak,televisionBuzz].compactMap({ $0 }) {
            source.isPositional = true
            source.volume = 0.94
            source.load()
        }
        ringtone = loopingSource("ring.wav",volume:0.95)
        if let knock = SCNAudioSource(fileNamed:"door-knock.wav") {
            knock.isPositional = true
            knock.volume = 1
            knock.load()
            wardrobeKnock = knock
        }
        for name in ["drone","ring","ringback","step-a","step-b","step-c","step-d","garden-step-a","garden-step-b","rain","line-static","door-knock","door-latch","sting","pickup","heartbeat","blackout","scare-burp"] {
            if let url = Bundle.main.url(forResource:name,withExtension:"wav"),let p = try? AVAudioPlayer(contentsOf:url) { p.prepareToPlay(); players[name] = p }
        }
        players["sting"]?.volume = 0.25
        players["scare-burp"]?.volume = 1
        players["drone"]?.volume = 0.14
        players["heartbeat"]?.volume = 0.25
        for name in ["rain","drone","heartbeat","ring","ringback"] { players[name]?.numberOfLoops = -1 }
        for name in ["step-a","step-b","step-c","step-d","garden-step-a","garden-step-b"] {
            players[name]?.enableRate = true
        }
        players["ring"]?.volume = 0.94
        players["ringback"]?.volume = 0.80
    }
    private func play(_ name:String) { guard soundEnabled else { return }; players[name]?.currentTime = 0; players[name]?.play() }

    private func footsteps(distance:Float,sprinting:Bool,stairs:Bool = false) {
        guard distance > 0.002 else { return }
        distanceSinceStep += distance
        let stride: Float = stairs ? 0.50 : (sprinting ? 1.01 : 0.78)
        guard distanceSinceStep >= stride else { return }
        distanceSinceStep.formTruncatingRemainder(dividingBy:stride)
        let garden = camera.position.x < 0 && camera.position.z < frontDoorWorldZ
        let names = garden ? ["garden-step-a","garden-step-b"] : ["step-a","step-b","step-c","step-d"]
        let name = names[stepVoice % names.count]
        stepVoice = (stepVoice+1)%4
        players[name]?.volume = sprinting ? 0.61 : (stairs ? 0.47 : 0.43)
        players[name]?.rate = Float.random(in:0.91...1.09)
        play(name)
    }
    @objc private func toggleSound() {
        soundEnabled.toggle()
        soundButton.setTitle(soundEnabled ? "Sound on" : "Sound off",for:.normal)
        soundButton.setImage(UIImage(systemName:soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"),for:.normal)
        if soundEnabled {
            try? AVAudioSession.sharedInstance().setActive(true)
        } else {
            players.values.forEach { $0.stop() }
            phoneVoice.stopSpeaking(at:.immediate)
            stopSceneAudio()
            try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        }
    }
    private func showMenu(_ title:String,_ detail:String,_ action:String) {
        let icon = phase == .caught || phase == .escaped ? "arrow.counterclockwise" : "play.fill"
        startButton.setImage(UIImage(systemName:icon,withConfiguration:UIImage.SymbolConfiguration(pointSize:15,weight:.medium)),for:.normal)
        titleLabel.text = title; detailLabel.text = detail; updateMenuFonts(); startButton.setTitle(action,for:.normal); shade.isHidden = false; controls.isHidden = true; stick.reset(); setRunning(false)
        players.values.forEach { $0.stop() }; stopSceneAudio(); sceneView.isPlaying = false
        clockLabel.isHidden = phase != .title; eyebrow.isHidden = phase != .title
        newLayoutButton.isHidden = phase != .caught
        retryActions.axis = view.bounds.height < 600 && phase == .caught ? .horizontal : .vertical
        phoneVoice.stopSpeaking(at:.immediate)
        if newsStarted != nil { newsLine = -1 }
        UIApplication.shared.isIdleTimerDisabled = false
    }
    @objc private func menuAction() {
        if phase == .title || phase == .escaped {
            beginIntro()
            return
        }
        if phase == .paused && pausedFrom == .downstairs {
            resumeDownstairs()
            return
        }
        if phase == .caught {
            restartFromFoyer(keepLayout:true)
            return
        }
        if phase != .paused { resetGame() }
        beginPlaying()
    }

    @objc private func newLayout() {
        guard phase == .caught else { return }
        restartFromFoyer(keepLayout:false)
    }

    private func restartFromFoyer(keepLayout:Bool) {
        let resumeInside = keepLayout && (story.stage == .broadcast || activeHouseHunt)
        resetGame(keepLayout:keepLayout)
        enterAfterDoor()
        if resumeInside {
            story.advance(.resetGardenPower)
            restoreHouseLights()
            lockAfterRetreat()
        }
    }

    private func showGameplay() {
        introOverlay.isHidden = true
        shade.isHidden = true
        controls.isHidden = false
        sceneView.isPlaying = true
        lastTime = 0
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func beginPlaying() {
        phase = .playing
        showGameplay()
        crouchButton.isHidden = false
        lightButton.isHidden = false
        phoneButton.isHidden = !activeHouseHunt
        use.setTitle("USE",for:.normal)
        if soundEnabled {
            players["drone"]?.play()
            if case .incoming = phoneState { players["ring"]?.play() }
            if case .ringing = breaker.stage { players["ring"]?.play() }
            if case .outgoing = phoneState { players["ringback"]?.play() }
        }
        resumeSceneAudio()
        if gardenDoorOpen { rainVolume(camera.position.z < frontDoorWorldZ ? 0.76 : 0.29) }
    }

    private func beginIntro() {
        resetGame()
        opening?.setLit(true)
        houseAmbient?.intensity = 525
        setRoomPower(660)
        torch.light?.intensity = 0
        enemy.isHidden = true
        phase = .intro
        introElapsed = 0
        introBeat = -1
        lastTime = 0
        shade.isHidden = true
        introOverlay.isHidden = false
        introSkip.isHidden = false
        introOverlay.backgroundColor = .clear
        introPhone.isHidden = true
        introPhone.alpha = 0
        introPhone.transform = CGAffineTransform(translationX:14,y:145)
        sceneView.isPlaying = true
        UIApplication.shared.isIdleTimerDisabled = true
        play("drone")
        updateIntro(dt:0)
    }

    private func updateIntro(dt:Float) {
        introElapsed += dt
        let sitting = min(1,max(0,(introElapsed-13.0)/1.9))
        let eased = sitting*sitting*(3-2*sitting)
        let floor = OpeningLayout.upperFloor
        let motion: Float = UIAccessibility.isReduceMotionEnabled ? 0 : 1
        let breath = sin(introElapsed*1.72)*motion
        let glance = min(introElapsed/2.3,1)
        let phoneGlance = sin(introElapsed*0.91+0.45)*0.038*motion
        camera.position = SCNVector3(OpeningLayout.worldX-1.94+1.22*eased+phoneGlance*0.47,
                                     floor+0.73+0.87*eased+breath*0.018,
                                     OpeningLayout.worldZ+4.85-1.20*eased)
        camera.eulerAngles = SCNVector3(-0.32+0.32*eased+breath*0.021,
                                        -0.12+0.27*glance-0.15*eased+phoneGlance,
                                        (0.12+breath*0.014)*(1-eased))
        if motion > 0 && introElapsed >= 2.14 && introElapsed < 11.5 {
            introPhone.transform = CGAffineTransform(translationX:CGFloat(phoneGlance*58),y:CGFloat(breath*3))
                .rotated(by:CGFloat(phoneGlance*0.36))
        }
        let cue: Int
        switch introElapsed {
        case ..<1.6: cue = 0
        case ..<3.1: cue = 1
        case ..<4.4: cue = 2
        case ..<5.6: cue = 3
        case ..<6.7: cue = 4
        case ..<9.0: cue = 5
        case ..<11.5: cue = 6
        case ..<15.2: cue = 7
        default:
            skipIntro()
            return
        }
        guard cue != introBeat else { return }
        introBeat = cue
        switch cue {
        case 0:
            introCaption.text = "YAMEN’S BEDROOM · 3:00 AM"
        case 1:
            introPhone.screen = .lock
            introPhone.isHidden = false
            UIView.animate(withDuration:0.48) {
                self.introPhone.alpha = 1
                self.introPhone.transform = .identity
            }
            introCaption.text = nil
        case 2: introPhone.screen = .home
        case 3: introPhone.screen = .recents
        case 4: introPhone.screen = .contact
        case 5:
            introPhone.screen = .dialing
            play("ringback")
        case 6:
            players["ringback"]?.stop()
            introPhone.screen = .connected
            introCaption.text = "Waleed: “Do you have a stick—”"
            if soundEnabled {
                let reply = AVSpeechUtterance(string:"Do you have a stick")
                reply.voice = AVSpeechSynthesisVoice(language:"en-GB")
                reply.rate = 0.43
                reply.pitchMultiplier = 0.86
                phoneVoice.speak(reply)
            }
        default:
            phoneVoice.stopSpeaking(at:.immediate)
            play("line-static")
            introPhone.screen = .lost
            introCaption.text = "Yamen: “Hello?”"
            DispatchQueue.main.asyncAfter(deadline:.now()+0.59) { [weak self] in
                guard let self, self.phase == .intro else { return }
                self.speakYamen("Hello?")
            }
            UIView.animate(withDuration:0.43,delay:0.32,options:[.curveEaseIn],animations:{
                self.introPhone.alpha = 0
                self.introPhone.transform = CGAffineTransform(translationX:12,y:125)
            },completion:nil)
        }
    }

    @objc private func skipIntro() {
        if phase == .ending { completeEnding(); return }
        guard phase == .intro else { return }
        introSkip.isHidden = true
        introPhone.isHidden = true
        players["ringback"]?.stop()
        players["line-static"]?.stop()
        phoneVoice.stopSpeaking(at:.immediate)
        let bed = OpeningLayout.bedside
        camera.position = SCNVector3(OpeningLayout.worldX+bed.x,OpeningLayout.upperFloor+1.6,OpeningLayout.worldZ+bed.z)
        camera.eulerAngles = SCNVector3Zero
        yaw = 0; pitch = 0; lookRoll = 0
        movement = .zero
        distanceSinceStep = 0
        elapsed = 0
        nextKnock = 0.70
        message.text = ""
        resumeDownstairs()
    }

    private func resumeDownstairs() {
        phase = .downstairs
        showGameplay()
        crouchButton.isHidden = true
        lightButton.isHidden = true
        phoneButton.isHidden = true
        use.setTitle("OPEN",for:.normal)
        status.text = "3:00 AM"
        hint.text = "FOLLOW THE STAIRS"
        stick.reset()
        if soundEnabled { players["drone"]?.play() }
    }

    private func updateDownstairs(dt:Float) {
        elapsed += dt
        let runningHere = running && stamina > 2
        let speed: Float = runningHere ? 3.4 : 2.1
        let forward = -Float(stick.vector.y), strafe = Float(stick.vector.x)
        let dx = (-sin(yaw)*forward+cos(yaw)*strafe)*speed*dt
        let dz = (-cos(yaw)*forward-sin(yaw)*strafe)*speed*dt
        let previous = camera.position
        var p = previous
        if OpeningLayout.walkableInHouse(house,x:p.x+dx,z:p.z) { p.x += dx }
        if OpeningLayout.walkableInHouse(house,x:p.x,z:p.z+dz) { p.z += dz }
        p.y = OpeningLayout.heightInHouse(x:p.x,z:p.z)+1.60
        camera.position = p
        camera.eulerAngles = SCNVector3(pitch,yaw,0)
        let traveled = distance(previous,p)
        let localZ = p.z-OpeningLayout.worldZ
        let staircase = p.x < 0 && (OpeningLayout.stairEnd...0).contains(localZ)
        footsteps(distance:traveled,sprinting:runningHere,stairs:staircase)
        stamina = min(100,max(0,stamina+(runningHere && traveled > 0.002 ? -13 : 13)*dt))
        if running && stamina <= 2 { setRunning(false) }
        if elapsed >= nextKnock {
            players["door-knock"]?.volume = staircase || (p.x < 0 && localZ > 0) ? 0.53 : 0.91
            play("door-knock")
            nextKnock = elapsed+Float.random(in:4.7...6.4)
        }
        if p.x < 0 && localZ > OpeningLayout.stairEnd {
            objective.text = "GO DOWNSTAIRS"
            hint.text = "FOLLOW THE STAIRS"
        } else {
            objective.text = "ANSWER THE FRONT DOOR"
            hint.text = atFrontDoor ? "TAP OPEN" : "FOLLOW THE KNOCKING"
        }
        use.isEnabled = atFrontDoor
        use.alpha = use.isEnabled ? 1 : 0.46
    }

    private var atFrontDoor: Bool {
        OpeningLayout.canOpenDoor(x:camera.position.x-OpeningLayout.worldX,z:camera.position.z-OpeningLayout.worldZ)
    }

    private func answerFrontDoor() {
        guard atFrontDoor else { return }
        phase = .openingDoor
        introElapsed = 0
        doorCue = 0
        doorCameraStart = camera.position
        doorFacingStart = yaw
        doorPitchStart = pitch
        controls.isHidden = true
        introPhone.isHidden = true
        players["door-knock"]?.stop()
        players["drone"]?.stop()
        opening?.reachForKnob()
    }

    private var frontDoorWorldZ: Float { OpeningLayout.worldZ+OpeningLayout.frontDoorZ }

    private func gardenPoint(x:Float,z:Float,y:Float = 0) -> SCNVector3 {
        SCNVector3(OpeningLayout.worldX+x,y,OpeningLayout.worldZ+z)
    }

    private func doorTransition(dt:Float) {
        introElapsed += dt
        let t = introElapsed
        let approach = min(1,t/0.54)
        let goal = gardenPoint(x:0.20,z:OpeningLayout.frontDoorZ+1.05,y:1.57)
        camera.position = SCNVector3(doorCameraStart.x+(goal.x-doorCameraStart.x)*approach,
                                     doorCameraStart.y+(goal.y-doorCameraStart.y)*approach,
                                     doorCameraStart.z+(goal.z-doorCameraStart.z)*approach)
        let turn = atan2(sin(doorFacingStart),cos(doorFacingStart))
        camera.eulerAngles = SCNVector3(doorPitchStart*(1-approach),turn*(1-approach),0)
        if t >= 0.65 && doorCue == 0 {
            doorCue = 1
            play("door-latch")
            opening?.openFrontDoor()
            rainVolume(0.64)
        }
        if t >= 1.44 && doorCue == 1 {
            doorCue = 2
            introOverlay.backgroundColor = .clear
            introOverlay.isHidden = false
            introSkip.isHidden = true
            introCaption.text = "Yamen: …Hello?"
            speakYamen("Hello? Is anyone out there?")
        }
        if t >= 2.95 && doorCue == 2 {
            doorCue = 3
            opening?.slamFrontDoor()
            introCaption.text = nil
            rainVolume(0)
            play("door-latch")
        }
        if t >= 3.62 && doorCue == 3 {
            doorCue = 4
            opening?.setLit(false)
            setRoomPower(0)
            houseAmbient?.intensity = 110
            play("blackout")
            introCaption.text = "Yamen: What? Who turned off the lights?"
            speakYamen("What? Who turned off the lights?")
        }
        if t >= 6.45 { enterAfterDoor() }
    }

    private func enterAfterDoor() {
        guard story.advance(.closeRainDoor) else { return }
        opening?.slamFrontDoor()
        opening?.setLit(false)
        setRoomPower(0)
        houseAmbient?.intensity = 145
        enemy.isHidden = true
        camera.position = gardenPoint(x:0.20,z:OpeningLayout.frontDoorZ+1.05,y:1.60)
        yaw = 0
        pitch = 0
        camera.eulerAngles = SCNVector3Zero
        elapsed = 0
        stamina = 100
        movement = .zero
        stick.reset()
        use.isEnabled = true
        use.alpha = 1
        rainVolume(0)
        beginPlaying()
        tell("The service breaker is outside, on the right-hand garden wall.",duration:7)
    }

    private func restoreHouseLights() {
        opening?.restoreGardenPower()
        opening?.setLit(true)
        houseAmbient?.intensity = 320
        setRoomPower(535)
    }

    private func revealInGarden() {
        guard story.advance(.resetGardenPower) else { return }
        restoreHouseLights()
        play("pickup")
        phase = .gardenReveal
        controls.isHidden = true
        introElapsed = 0
        lastTime = 0
        doorFacingStart = yaw
        doorPitchStart = pitch
        let figure = OpeningLayout.gardenFigure
        enemy.position = gardenPoint(x:figure.x,z:figure.z)
        enemy.eulerAngles.y = .pi
        enemy.isHidden = false
        enemyEyes.forEach { $0.isHidden = false }
        introOverlay.isHidden = false
        introOverlay.backgroundColor = .clear
        introSkip.isHidden = true
        introCaption.text = "Yamen: Waleed? Is that you?"
        speakYamen("Waleed? Is that you?")
    }

    private func updateGardenReveal(dt:Float) {
        introElapsed += dt
        let target = atan2(camera.position.x-enemy.position.x,camera.position.z-enemy.position.z)
        let angle = atan2(sin(target-doorFacingStart),cos(target-doorFacingStart))
        let t = min(1,introElapsed/0.82)
        camera.eulerAngles = SCNVector3(doorPitchStart*(1-t),doorFacingStart+angle*t,0)
        torch.light?.intensity = 990
        if introElapsed >= 2.45 {
            phoneVoice.stopSpeaking(at:.immediate)
            yaw = .pi
            pitch = 0
            camera.eulerAngles = SCNVector3(0,yaw,0)
            stamina = 100
            retreatStarted = elapsed
            beginPlaying()
            setCrouched(false)
            setRunning(true)
            tell("Run up the garden path. Get inside and lock the front door.",duration:6)
        }
    }

    private var nearFrontThreshold: Bool {
        abs(camera.position.x-OpeningLayout.worldX) < 0.96 &&
            abs(camera.position.z-frontDoorWorldZ) < 1.55
    }

    private var nearGardenBreaker: Bool {
        let position = OpeningLayout.gardenBox
        return distance(camera.position,gardenPoint(x:position.x,z:position.z)) < 1.72
    }

    private var activeHouseHunt: Bool {
        switch story.stage {
        case .fuses,.serviceKey,.relays,.release,.exit: true
        default: false
        }
    }

    private func rainVolume(_ volume:Float) {
        guard soundEnabled, let rain = players["rain"] else { return }
        rain.volume = volume
        if volume > 0 {
            if !rain.isPlaying { rain.play() }
        } else { rain.stop() }
    }

    private func updateRetreat(dt:Float) -> Bool {
        let destination = camera.position
        let dx = destination.x-enemy.position.x, dz = destination.z-enemy.position.z
        let range = hypot(dx,dz)
        if range <= 1.16 {
            finishCaught()
            return false
        }
        if elapsed-retreatStarted > 0.75 {
            let step = min(range,3.12*dt)
            enemy.position.x += dx/range*step
            enemy.position.z += dz/range*step
            enemy.eulerAngles.y = atan2(-dx,-dz)
            gait += step*4.9
            let stride = sin(gait)*0.68
            for (index,limb) in enemyLimbs.enumerated() {
                limb.eulerAngles.x = index.isMultiple(of:2) ? -stride : stride
            }
        }
        danger.alpha = CGFloat(0.13*max(0,1-range/9))
        return true
    }

    private func lockAfterRetreat() {
        guard story.advance(.lockFrontDoor) else { return }
        gardenDoorOpen = false
        opening?.lockFrontDoor()
        rainVolume(0)
        play("door-latch")
        enemy.isHidden = true
        enemy.position = point(House.enemy)
        enemy.eulerAngles = SCNVector3Zero
        enemyLimbs.forEach { $0.eulerAngles.x = 0 }
        enemyEyes.forEach { $0.isHidden = true }
        danger.alpha = 0
        setRunning(false)
        tell("Yamen: I need to know what’s happening. The TV is in the lounge.",duration:7)
        speakYamen("I need to know what's happening. The TV is in the lounge.")
    }

    private func resetGame(keepLayout:Bool = false) {
        if !keepLayout { house = house.reshuffled() }
        breaker = BreakerEncounter()
        story = StoryProgress()
        gardenDoorOpen = false
        retreatStarted = 0
        televisionOn = false
        newsStarted = nil
        newsLine = -1
        setCrouched(false)
        sightTime = 0
        patrolPauseUntil = 0
        patrolActivity = nil
        patrolTVAudio = nil
        patrolPose = 0
        nextHello = Float.random(in:22...38)
        wardrobeReturn = nil
        reader.isHidden = true
        nextTrap = 0; lastTrap = nil; readNotes = []; distanceSinceStep = 0
        movement = .zero; stepPhase = 0; lookRoll = 0
        elapsed = 0; nextBurp = 9; yaw = 0; pitch = 0; hidden = false; flashlight = true
        battery = 100; stamina = 100; collected = []; power = false; nextCall = 24
        phoneState = .idle; nextOutgoing = 0; lure = nil; remoteRing = nil
        huntUntil = 0; route = []; routeTime = 0; patrolIndex = 0; gait = 0
        enemyTarget = House.enemy; routedTarget = nil; enemyAwake = false
        lastKnownPlayer = nil; searchRoute = []
        buildWorld()
        setRoomPower(0)
        setRunning(false)
        updatePhoneButton()
        danger.alpha = 0
        lightButton.setTitle("LIGHT ON",for:.normal)
        tell("Search the cupboards. CALL WALEED to distract him.",duration:7)
    }

    @objc private func pauseGame() {
        guard phase == .playing || phase == .downstairs else { return }
        pausedFrom = phase
        phase = .paused
        let detail = pausedFrom == .downstairs ? "Go downstairs and answer the knocking at the front door." : missionObjective
        showMenu("Stay quiet",detail,"Resume")
    }

    @objc private func background() {
        if phase == .reading { closeDocument() }
        if phase == .intro { skipIntro() }
        if phase == .openingDoor || phase == .gardenReveal { lastTime = 0 }
        if phase == .ending { lastTime = 0 }
        pauseGame()
    }

    @objc private func toggleRun() {
        guard (phase == .playing || phase == .downstairs), !hidden, stamina > 2 else { return }
        if crouched { setCrouched(false) }
        setRunning(!running)
    }

    @objc private func toggleCrouch() {
        guard phase == .playing, !hidden else { return }
        setCrouched(!crouched)
    }

    private func setCrouched(_ enabled:Bool) {
        crouched = enabled
        if enabled { setRunning(false) }
        crouchButton.setTitle(enabled ? "STAND" : "CROUCH",for:.normal)
        crouchButton.backgroundColor = enabled ? UIColor(red:0.23,green:0.29,blue:0.18,alpha:0.94) : UIColor(white:0.06,alpha:0.8)
        crouchButton.accessibilityValue = enabled ? "Crouched" : "Standing"
    }

    private func speakYamen(_ text:String) {
        guard soundEnabled else { return }
        phoneVoice.stopSpeaking(at:.immediate)
        let voice = AVSpeechUtterance(string:text)
        voice.voice = AVSpeechSynthesisVoice(language:"en-US")
        voice.rate = 0.39
        voice.pitchMultiplier = 0.99
        voice.volume = 0.58
        phoneVoice.speak(voice)
    }

    private func updateYamenVoice() {
        guard elapsed >= nextHello else { return }
        nextHello = elapsed + Float.random(in:28...57)
        guard !hidden, !crouched, !breaker.isActive, elapsed >= huntUntil, case .idle = phoneState else { return }
        speakYamen("Hello?")
    }

    private func setRunning(_ enabled: Bool) {
        running = enabled
        sprintButton.setTitle(enabled ? "RUN ON" : "RUN",for:.normal)
        sprintButton.backgroundColor = enabled ? UIColor(red:0.34,green:0.11,blue:0.08,alpha:0.9) : UIColor(white:0.06,alpha:0.8)
        sprintButton.accessibilityValue = enabled ? "On" : "Off"
    }

    @objc private func toggleLight() { guard phase == .playing,!hidden else { return }; flashlight.toggle(); if battery < 1 { flashlight = false }; lightButton.setTitle(flashlight ? "LIGHT ON" : "LIGHT OFF",for:.normal) }

    @objc private func phoneAction() {
        guard phase == .playing, activeHouseHunt else { return }
        if breaker.isActive {
            if breaker.answer(at:elapsed) {
                players["ring"]?.stop()
                tell("Waleed, whispering: “I’m at the front door.”",duration:3.0)
                whisper("I'm at the front door.")
            } else if breaker.hangUp() {
                phoneVoice.stopSpeaking(at:.immediate)
                nextCall = elapsed+26
                tell("You hung up. Look for the service key in the study.")
            }
            updatePhoneButton()
            return
        }
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
            play("ringback")
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

    private func whisper(_ words:String) {
        guard soundEnabled else { return }
        phoneVoice.stopSpeaking(at:.immediate)
        let line = AVSpeechUtterance(string:words)
        line.voice = AVSpeechSynthesisVoice(language:"en-GB")
        line.rate = 0.44
        line.pitchMultiplier = 0.80
        line.volume = 0.53
        phoneVoice.speak(line)
    }

    private func restorePower() {
        power = true
        endCall()
        phoneVoice.stopSpeaking(at:.immediate)
        breaker.start(at:elapsed)
        setRoomPower(560)
        play("pickup")
        tell("The breaker clicks. The lights flicker.",duration:2)
    }

    private func updateBreaker() {
        if case .flicker = breaker.stage {
            setRoomPower(breaker.isLit(at:elapsed) ? 560 : 0)
        }
        guard let cue = breaker.advance(to:elapsed) else { return }
        switch cue {
        case .ring:
            setRoomPower(560)
            tell("WALEED IS CALLING",duration:6)
            play("ring")
        case .knock:
            if soundEnabled, let clip = wardrobeKnock,
               let closet = House.closets.min(by:{ distance(point($0), camera.position) < distance(point($1), camera.position) }) {
                let place = wardrobeCenter(closet)
                playRoomSound(clip,at:SCNVector3(place.x,1.24,place.z))
            }
            tell("Three knocks come from inside the wardrobe.",duration:3)
        case .clue:
            nextCall = elapsed+28
            let clue = "The study console controls the green back door."
            tell("Waleed: “\(clue)”",duration:7)
            whisper(clue)
        case .missed:
            players["ring"]?.stop()
            nextCall = elapsed+28
            tell("Missed call. The security panel is back online.")
        }
    }

    private func endCall() {
        if case .outgoing = phoneState { nextOutgoing = elapsed+12 }
        phoneState = .idle
        players["ring"]?.stop()
        players["ringback"]?.stop()
        remoteRing?.removeAllAudioPlayers()
        remoteRing?.removeFromParentNode()
        remoteRing = nil
    }

    private func updatePhoneButton() {
        if breaker.isActive {
            switch breaker.stage {
            case .ringing: phoneButton.setTitle("ANSWER",for:.normal); phoneButton.isEnabled = true
            case .connected: phoneButton.setTitle("HANG UP",for:.normal); phoneButton.isEnabled = true
            default: phoneButton.setTitle("NO SIGNAL",for:.normal); phoneButton.isEnabled = false
            }
            phoneButton.alpha = phoneButton.isEnabled ? 1 : 0.62
            return
        }
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
        if breaker.isActive {
            updateBreaker()
            return false
        }
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
        let d = g.translation(in:lookSurface); g.setTranslation(.zero,in:lookSurface); guard (phase == .playing || phase == .downstairs), !hidden || wardrobeReturn != nil else { return }
        let scale = traitCollection.userInterfaceIdiom == .pad ? Float(0.0036) : 0.0046
        yaw -= Float(d.x)*scale
        pitch = min(0.88,max(-0.88,pitch-Float(d.y)*scale*0.83))
        if wardrobeReturn != nil {
            yaw = min(wardrobeYaw+0.36,max(wardrobeYaw-0.36,yaw))
            pitch = min(0.25,max(-0.25,pitch))
            camera.eulerAngles = SCNVector3(pitch,yaw,0)
        }
    }
    private func distance(_ a:SCNVector3,_ b:SCNVector3) -> Float { hypot(a.x-b.x,a.z-b.z) }
    private func near(_ c:Cell,range:Float = 2.6) -> Bool { let p = point(c); return distance(camera.position,p) < range && house.visible(camera.position.x,camera.position.z,p.x,p.z) }
    private func nearbyCupboard() -> Int? {
        let player = camera.position
        var nearest: Int?
        var best: Float = 1.75
        for (index,cupboard) in cupboards.enumerated() {
            let dx = cupboard.front.x-player.x, dz = cupboard.front.z-player.z
            let range = hypot(dx,dz)
            let inFront = -(dx*cupboard.forwardX+dz*cupboard.forwardZ) > 0.08
            guard inFront, range < best, -sin(yaw)*dx-cos(yaw)*dz >= 0.50*range,
                  house.visible(player.x,player.z,cupboard.front.x,cupboard.front.z) else { continue }
            nearest = index
            best = range
        }
        return nearest
    }

    private func canTakeFuse(from cupboard: Cupboard) -> Bool {
        cupboard.isOpen && cupboard.fuse != nil && !collected.contains(cupboard.cell)
    }

    private func searchCupboard(at index: Int) {
        let cupboard = cupboards[index]
        guard elapsed >= cupboard.readyAt else { return }
        if canTakeFuse(from:cupboard), let fuse = cupboard.fuse {
            collected.insert(cupboard.cell)
            let lift = SCNAction.moveBy(x:0,y:0.16,z:0.24,duration:0.22)
            lift.timingMode = .easeOut
            fuse.runAction(.sequence([.group([lift,.fadeOut(duration:0.22)]),.removeFromParentNode()]))
            play("pickup")
            tell("Fuse \(collected.count) / 3 collected.")
            return
        }
        let opening = !cupboard.isOpen
        cupboards[index].isOpen = opening
        cupboards[index].readyAt = elapsed+0.35
        for (i,hinge) in cupboard.doors.enumerated() {
            let direction: CGFloat = i == 0 ? -1 : 1
            let swing = SCNAction.rotateTo(x:0,y:opening ? direction*1.20 : 0,z:0,duration:0.35,usesShortestUnitArc:true)
            swing.timingMode = .easeInEaseOut
            hinge.runAction(swing,forKey:"cupboard-door")
        }
        if opening && !collected.contains(cupboard.cell) { cupboard.fuse?.isHidden = false }
        play("door-latch")
        if opening && !canTakeFuse(from:cupboards[index]) {
            tell(collected.contains(cupboard.cell) ? "You already took the fuse here." : "No fuse in this cupboard.")
        }
    }
    private func tell(_ text:String,duration:Float = 4) { message.text = text; messageUntil = elapsed+duration }
    private func showDocument(title:String, author:String, body:String) {
        phase = .reading
        controls.isHidden = true
        stick.reset()
        movement = .zero
        sceneView.isPlaying = false
        players.values.forEach { $0.pause() }
        stopSceneAudio()
        reader.present(title:title,by:author,body:body)
    }

    private func closeDocument() {
        guard phase == .reading else { return }
        reader.isHidden = true
        beginPlaying()
    }

    @objc private func interact() {
        if phase == .downstairs { answerFrontDoor(); return }
        guard phase == .playing else { return }
        if hidden {
            hidden = false
            if let outside = wardrobeReturn {
                camera.position = outside.position
                yaw = outside.yaw; pitch = outside.pitch
                camera.eulerAngles = SCNVector3(pitch,yaw,0)
                wardrobeReturn = nil
            }
            tell("You step out. Listen before moving.")
            return
        }
        if interactWithMission() { return }
        guard activeHouseHunt else { return }
        if let index = nearbyCupboard() {
            searchCupboard(at:index)
            return
        }
        for (index,note) in notes.enumerated() where !readNotes.contains(note.cell) && near(note.cell,range:1.8) {
            readNotes.insert(note.cell)
            noteNodes[index].isHidden = true
            play("pickup")
            showDocument(title:note.title, author:note.author, body:note.body)
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

        if let cell = House.closets.first(where:{ near($0,range:2) }) {
            if !crouched && huntUntil > elapsed && seesPlayer(distance(camera.position,enemy.position)) {
                tell("He saw you. Break line of sight first.")
                return
            }
            wardrobeReturn = (camera.position,yaw,pitch)
            let inside = wardrobeCenter(cell)
            wardrobeYaw = cell.x < 8 ? -.pi/2 : .pi/2
            hidden = true
            setRunning(false)
            flashlight = false
            lightButton.setTitle("LIGHT OFF",for:.normal)
            movement = .zero
            stick.reset()
            yaw = wardrobeYaw
            pitch = 0
            camera.position = SCNVector3(inside.x,1.25,inside.z)
            camera.eulerAngles = SCNVector3(0,yaw,0)
            tell("Hidden. Look through the gap. USE to leave.",duration:8)
            return
        }
        tell("Nothing within reach. Face a cupboard or find a gold handle.")
    }
    private func interactWithMission() -> Bool {
        switch story.stage {
        case .garden:
            if nearFrontThreshold {
                gardenDoorOpen.toggle()
                if gardenDoorOpen { opening?.openFrontDoor() } else { opening?.slamFrontDoor() }
                rainVolume(gardenDoorOpen ? 0.66 : 0)
                play("door-latch")
            } else if nearGardenBreaker {
                revealInGarden()
            } else {
                tell("The garden breaker is outside on the right-hand wall.")
            }
            return true
        case .retreat:
            if nearFrontThreshold && camera.position.z > frontDoorWorldZ+0.13 {
                lockAfterRetreat()
            } else {
                tell("Get inside the front door, then use the bolt.")
            }
            return true
        case .broadcast:
            if near(House.loungeTV,range:2.35) {
                useTelevision()
            } else {
                tell("Turn on the TV in the lounge. Stay near it for the bulletin.")
            }
            return true
        default: break
        }
        if near(House.panel,range:2.02) {
            if story.stage == .fuses && collected.count == 3 && story.advance(.installFuses) {
                restorePower()
                tell("Security panel online. Retrieve the service key from the study desk.",duration:8)
            } else if story.stage == .fuses {
                tell("Security panel needs \(3-collected.count) more fuses.")
            } else {
                tell("Security panel online.")
            }
            return true
        }
        if near(House.exit,range:2.1) {
            if story.stage == .exit { beginEnding() }
            else { tell("The security lock is still engaged. Check the objective.") }
            return true
        }
        if near(House.serviceDesk,range:2.05) && story.stage == .serviceKey {
            if story.advance(.takeKey) {
                serviceKeyNode?.isHidden = true
                play("pickup")
                tell("Service key found. Use it on the kitchen and laundry relays.",duration:8)
            }
            return true
        }
        if near(House.serviceDesk,range:2.05) && story.stage == .release {
            if story.advance(.releaseExit) {
                setIndicator(exitLight,.systemGreen)
                play("door-latch")
                tell("The green back exit is unlocked. Get out.",duration:8)
            }
            return true
        }
        if let relay = [House.kitchenRelay,House.laundryRelay].first(where:{ near($0,range:1.77) }) {
            if story.advance(.resetRelay(relay)) {
                setIndicator(relayLights[relay],.systemGreen)
                play("door-latch")
                tell(story.stage == .release ?
                     "Both relays are online. Release the escape lock at the study console." :
                     "Relay online. One more to reset.",duration:7)
            } else {
                tell(story.resetRelays.contains(relay) ? "This relay is already online." : "The relay needs the service key.")
            }
            return true
        }
        if near(House.loungeTV,range:2.35) {
            useTelevision()
            return true
        }
        return false
    }

    private func setIndicator(_ node:SCNNode?,_ color:UIColor) {
        node?.geometry?.firstMaterial?.diffuse.contents = color
        node?.geometry?.firstMaterial?.emission.contents = color
    }

    private var missionObjective: String {
        switch story.stage {
        case .doorstep: "ANSWER THE FRONT DOOR"
        case .garden: "01  •  RESET THE GARDEN BREAKER"
        case .retreat: "02  •  RUN INSIDE AND LOCK THE DOOR"
        case .broadcast: "03  •  WATCH THE LOUNGE TV"
        case .fuses: collected.count == 3 ? "04  •  INSTALL THE FUSES AT THE RED PANEL" : "04  •  SEARCH CUPBOARDS  \(collected.count)/3"
        case .serviceKey: "05  •  GET THE SERVICE KEY FROM THE STUDY"
        case .relays: "06  •  RESET KITCHEN AND LAUNDRY RELAYS  \(story.resetRelays.count)/2"
        case .release: "07  •  RELEASE THE LOCK AT THE STUDY CONSOLE"
        case .exit: "08  •  ESCAPE THROUGH THE GREEN BACK DOOR"
        }
    }

    private var missionHint: String? {
        switch story.stage {
        case .garden:
            if nearFrontThreshold { return gardenDoorOpen ? "USE  ·  CLOSE DOOR" : "USE  ·  OPEN FRONT DOOR" }
            return nearGardenBreaker ? "USE  ·  RESET GARDEN BREAKER" : "FOLLOW THE PATH AND LOOK RIGHT"
        case .retreat:
            return nearFrontThreshold && camera.position.z > frontDoorWorldZ+0.13 ? "USE  ·  LOCK THE DOOR" : "RUN TOWARDS THE HOUSE"
        case .broadcast:
            return near(House.loungeTV,range:2.35) && newsStarted == nil ? "USE  ·  TURN ON TV" : "THE TV IS IN THE LOUNGE"
        case .serviceKey where near(House.serviceDesk,range:2.05): return "USE  ·  TAKE SERVICE KEY"
        case .relays where [House.kitchenRelay,House.laundryRelay].contains(where:{ near($0,range:1.77) }):
            return "USE  ·  UNLOCK AND RESET RELAY"
        case .release where near(House.serviceDesk,range:2.05): return "USE  ·  RELEASE EXIT LOCK"
        default: return nil
        }
    }

    private func playerCanMove(x:Float,z:Float) -> Bool {
        if story.stage == .garden || story.stage == .retreat {
            return OpeningLayout.walkableWithGarden(house,x:x,z:z,doorOpen:gardenDoorOpen)
        }
        return OpeningLayout.walkableInHouse(house,x:x,z:z)
    }

    private func beginEnding() {
        phase = .ending
        endCall()
        phoneVoice.stopSpeaking(at:.immediate)
        finishPatrolActivity()
        stopSceneAudio()
        players.values.forEach { $0.stop() }
        movement = .zero
        stick.reset()
        setRunning(false)
        danger.alpha = 0
        controls.isHidden = true
        endingStart = camera.position
        endingYaw = yaw
        endingPitch = pitch
        endingTime = 0
        endingBeat = -1
        endCard.font = cinematicFont(view.bounds.height < 590 ? 43 : 74)
        endCard.isHidden = true
        introOverlay.isHidden = false
        introOverlay.backgroundColor = .clear
        introSkip.isHidden = false
        introCaption.text = nil
        introPhone.layer.removeAllAnimations()
        introPhone.isHidden = true
        introPhone.alpha = 0
        introPhone.transform = .identity
        updateEnding(dt:0)
    }

    private func updateEnding(dt:Float) {
        endingTime += dt
        let door = point(House.exit)
        let threshold = door.z+House.tile/2
        let targetYaw = Float.pi
        let cues = EscapeSequence.cues
        func progress(from start:Float,to end:Float) -> Float {
            let t = min(1,max(0,(endingTime-start)/(end-start)))
            return t*t*(3-2*t)
        }
        let stepOut = cues[EscapeSequence.Beat.stepOut.rawValue]
        let doorShuts = cues[EscapeSequence.Beat.doorShuts.rawValue]
        if endingTime < stepOut {
            let t = progress(from:0,to:stepOut)
            camera.position = SCNVector3(endingStart.x+(door.x-endingStart.x)*t,
                                         endingStart.y+(1.58-endingStart.y)*t,
                                         endingStart.z+(threshold-0.64-endingStart.z)*t)
            let angle = atan2(sin(targetYaw-endingYaw),cos(targetYaw-endingYaw))
            camera.eulerAngles = SCNVector3(endingPitch*(1-t),endingYaw+angle*t,0)
        } else {
            let t = progress(from:stepOut+0.36,to:doorShuts)
            camera.position = SCNVector3(door.x,1.58,threshold-0.64+4.60*t)
            let turn = progress(from:doorShuts-0.12,to:doorShuts+1.15)
            camera.eulerAngles = SCNVector3(-0.045*turn,targetYaw*(1-turn),0)
            torch.light?.intensity = flashlightIntensity*CGFloat(1-t)
        }

        let beat = EscapeSequence.beat(at:endingTime)
        guard beat.rawValue != endingBeat else { return }
        endingBeat = beat.rawValue
        switch beat {
        case .approach:
            play("door-latch")
        case .stepOut:
            let swing = SCNAction.rotateTo(x:0,y:-1.42,z:0,duration:0.59,usesShortestUnitArc:true)
            swing.timingMode = .easeOut
            exitHinge.runAction(swing,forKey:"escape-door")
            play("step-c")
        case .doorShuts:
            let shut = SCNAction.rotateTo(x:0,y:0,z:0,duration:0.20,usesShortestUnitArc:true)
            shut.timingMode = .easeIn
            exitHinge.runAction(shut,forKey:"escape-door")
            play("door-latch")
        case .knocks:
            play("door-knock")
            introCaption.text = "Three knocks from behind the door."
        case .call:
            play("ring")
            introCaption.text = nil
            introPhone.screen = .ending
            introPhone.isHidden = false
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            introPhone.transform = reduceMotion ? .identity : CGAffineTransform(translationX:0,y:125)
            UIView.animate(withDuration:0.38) {
                self.introPhone.alpha = 1
                self.introPhone.transform = .identity
            }
        case .blackout:
            players["ring"]?.stop()
            introPhone.isHidden = true
            introOverlay.backgroundColor = .black
            play("line-static")
        case .title:
            endCard.text = "The End"
            endCard.isHidden = false
        case .question:
            endCard.text = "The End?"
        case .credits:
            endCard.font = .systemFont(ofSize:view.bounds.height < 590 ? 20 : 32,weight:.medium)
            endCard.text = "Yamen and Waleed will be returning"
        case .results:
            completeEnding()
        }
    }

    private func completeEnding() {
        guard phase == .ending else { return }
        phase = .escaped
        endCard.isHidden = true
        introSkip.isHidden = true
        introPhone.isHidden = true
        introCaption.text = nil
        introOverlay.backgroundColor = .clear
        introOverlay.isHidden = true
        let detail = readNotes.count == notes.count ?
            "You escaped with all three notes. The service log was right. Disconnecting the line changed nothing." :
            "The front door started it. The back door got you out."
        showMenu("You got out",detail,"Play again")
    }

    private func finishCaught() {
        phase = .caught
        phoneVoice.stopSpeaking(at:.immediate)
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
        if soundEnabled {
            try? AVAudioSession.sharedInstance().setActive(true)
            play("scare-burp")
        }
        UIImpactFeedbackGenerator(style:.heavy).impactOccurred(intensity:1)

        DispatchQueue.main.asyncAfter(deadline:.now()+1.70) { [weak self] in
            guard let self, self.phase == .caught else { return }
            self.showMenu("He found you.","Crouch to move quietly. Break line of sight before hiding.", "Retry this layout")
        }
    }

    private func seesPlayer(_ range:Float) -> Bool {
        guard !hidden else { return false }
        let p = camera.position, e = enemy.position
        let facing = enemy.eulerAngles.y
        let toward = (p.x-e.x)*(-sin(facing))+(p.z-e.z)*(-cos(facing))
        guard House.canNotice(range:range, forward:toward, flashlight:flashlight, crouched:crouched),
              hasSight(from:e,to:p) else { return false }
        return true
    }

    private func hasSight(from a:SCNVector3,to b:SCNVector3) -> Bool {
        if a.x >= 0 && b.x >= 0 { return house.visible(a.x,a.z,b.x,b.z) }
        guard OpeningLayout.heightInHouse(x:b.x,z:b.z) < 0.12 else { return false }
        return canTravel(from:a,to:b,radius:0)
    }

    private func canTravel(from a:SCNVector3,to b:SCNVector3,radius:Float) -> Bool {
        if a.x >= 0.39 && b.x >= 0.39 {
            return house.walkableBetween(a.x,a.z,b.x,b.z,radius:radius)
        }
        let steps = max(1,Int(ceil(distance(a,b)/0.10)))
        for i in 0...steps {
            let t = Float(i)/Float(steps)
            let x = a.x+(b.x-a.x)*t, z = a.z+(b.z-a.z)*t
            if !OpeningLayout.walkableInHouse(house,x:x,z:z,radius:radius) { return false }
        }
        return true
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
        var next = position
        if OpeningLayout.walkableInHouse(house,x:nx,z:nz,radius:0.18) {
            next = SCNVector3(nx,position.y,nz)
        } else {
            if OpeningLayout.walkableInHouse(house,x:nx,z:position.z,radius:0.18) { next.x = nx }
            if OpeningLayout.walkableInHouse(house,x:next.x,z:nz,radius:0.18) { next.z = nz }
        }
        let traveled = distance(position,next)
        guard traveled > 0.001 else { return 0 }
        enemy.position = next
        let bearing = atan2(-vx,-vz)
        let angleDelta = bearing-enemy.eulerAngles.y
        enemy.eulerAngles.y += atan2(sin(angleDelta),cos(angleDelta))*min(1,dt*13)
        return traveled
    }

    private func updateEnemy(dt: Float, sprint: Bool, moving: Bool, traced: Bool) -> Bool {
        let p = camera.position
        let cell = p.x < 0 ? House.foyerEntrance : House.cell(p.x,p.z)
        let separation = distance(p,enemy.position)
        let sight = seesPlayer(separation)
        let incoming: Bool
        if case .incoming = phoneState { incoming = true } else if case .ringing = breaker.stage { incoming = true } else { incoming = false }
        let heardFootsteps = moving && separation < (crouched ? 0.68 : (sprint ? 7.9 : 2.15))
        sightTime = sight ? min(1.15,sightTime+dt) : max(0,sightTime-dt*2.0)
        let detected = !hidden &&
            (sightTime >= (crouched ? 0.95 : 0.78) || heardFootsteps || (incoming && separation < 10) || traced)

        if !enemyAwake && (lure != nil || traced || elapsed >= nextCall-20) { enemyAwake = true }
        if enemyAwake, detected {
            huntUntil = elapsed+7.4
            finishPatrolActivity()
            patrolPauseUntil = 0
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
                    finishPatrolActivity()
                    patrolPauseUntil = 0
                    enemyTarget = lure.target
                } else {
                    lure = nil
                    if reached(enemyTarget), enemyTarget == house.patrol[patrolIndex] {
                        if patrolPauseUntil == 0 {
                            beginPatrolActivity(at:enemyTarget)
                        } else if elapsed >= patrolPauseUntil {
                            finishPatrolActivity()
                            patrolPauseUntil = 0
                            patrolIndex = (patrolIndex+1)%house.patrol.count
                        }
                    }
                    enemyTarget = house.patrol[patrolIndex]
                }
            }

            let speed: Float = hunting ? (power ? 4.45 : 4.15) : 2.26
            let waiting = !hunting && elapsed < patrolPauseUntil
            let moved: Float = waiting ? 0 : advanceEnemy(visiblePlayer:sight && hunting ? p : nil,speed:speed,dt:dt)
            let sit = waiting && patrolActivity == .television
            patrolPose += ((sit ? 1 : 0)-patrolPose)*min(1,dt*5)
            enemy.pivot = SCNMatrix4MakeTranslation(0,0,-0.36*patrolPose)
            if waiting {
                animatePatrolActivity(dt:dt)
            } else {
                enemyHead.eulerAngles.x = 0
            }
            gait += moved*4.9
            let amount: Float = hunting ? 0.74 : 0.45
            let stride = moved > 0.001 ? sin(gait)*amount : 0
            let hip: Float = 1.15*patrolPose
            let arm: Float = waiting && patrolActivity == .fridge ? -0.61 : 0
            let target: [Float] = [-stride+arm,stride,stride-hip,-stride-hip]
            let bend: [Float] = [0.38+max(0,stride)*0.42,0.38+max(0,-stride)*0.42,
                                 -max(0,-stride)*0.88+hip,-max(0,stride)*0.88+hip]
            for index in enemyLimbs.indices {
                enemyLimbs[index].eulerAngles.x += (target[index]-enemyLimbs[index].eulerAngles.x)*min(1,dt*17)
                enemyBend[index].eulerAngles.x += (bend[index]-enemyBend[index].eulerAngles.x)*min(1,dt*17)
            }
            enemy.eulerAngles.x = hunting && moved > 0.001 ? 0.12 : 0
            enemy.position.y = (moved > 0.001 ? abs(sin(gait))*0.05 : 0)-0.43*patrolPose
        }

        let e = enemy.position
        let dist = distance(e,p)
        let close = !hidden && dist < 5.8 && hasSight(from:e,to:p)
        enemyEyes.forEach { $0.isHidden = !close }
        if close {
            let facing = atan2(e.x-p.x,e.z-p.z)-enemy.eulerAngles.y
            enemyHead.eulerAngles.y = atan2(sin(facing),cos(facing))
        } else {
            enemyHead.eulerAngles.y = 0
        }
        if enemyAwake && !hidden && dist <= 1.30 && hasSight(from:e,to:p) && canTravel(from:e,to:p,radius:0) {
            finishCaught()
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

    private func beginPatrolActivity(at cell:Cell) {
        switch cell {
        case House.fridgeStop:
            patrolActivity = .fridge
            patrolPauseUntil = elapsed+4.7
            let open = SCNAction.rotateTo(x:0,y:0.89,z:0,duration:0.61,usesShortestUnitArc:true)
            open.timingMode = .easeInEaseOut
            fridgeHinge?.runAction(open,forKey:"fridge-door")
            fridgeLamp?.intensity = 270
            if soundEnabled, let source = activityCreak {
                playRoomSound(source,at:SCNVector3(enemy.position.x,1.4,enemy.position.z-0.70))
            }
        case House.sofaStop:
            patrolActivity = .television
            patrolPauseUntil = elapsed+7.2
            thermalScreens.forEach { $0.isHidden = false }
            if !televisionOn, soundEnabled, let source = televisionBuzz {
                patrolTVAudio = playRoomSound(source,at:point(House.loungeTV,y:1.20),duration:7.0)
            }
        case House.listeningStop:
            patrolActivity = .listen
            patrolPauseUntil = elapsed+4.3
        default:
            patrolPauseUntil = elapsed+Float.random(in:1.8...3.9)
        }
    }

    private func finishPatrolActivity() {
        switch patrolActivity {
        case .fridge:
            fridgeHinge?.runAction(.rotateTo(x:0,y:0,z:0,duration:0.37,usesShortestUnitArc:true),forKey:"fridge-door")
            fridgeLamp?.intensity = 0
        case .television:
            thermalScreens.forEach { $0.isHidden = !televisionOn }
            patrolTVAudio?.removeFromParentNode()
            patrolTVAudio = nil
        default: break
        }
        patrolActivity = nil
    }

    private func animatePatrolActivity(dt:Float) {
        let facing: Float
        switch patrolActivity {
        case .fridge:
            facing = 0
            enemyHead.eulerAngles.x = 0.26 + sin(elapsed*2.0)*0.10
        case .television:
            facing = 0
            enemyHead.eulerAngles.x = -0.04 + sin(elapsed*0.8)*0.07
        case .listen:
            facing = -.pi/2
            enemyHead.eulerAngles.x = 0.08
        default:
            enemy.eulerAngles.y += sin(elapsed*1.6)*dt*0.74
            return
        }
        let delta = facing-enemy.eulerAngles.y
        enemy.eulerAngles.y += atan2(sin(delta),cos(delta))*min(1,dt*7)
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
        if let player = visiblePlayer, canTravel(from:e,to:player,radius:0.18) {
            route.removeAll()
            routedTarget = nil
            routeTime = elapsed
            return moveEnemy(toward:player,speed:speed,dt:dt)
        }
        if e.x < 0 {
            let threshold = SCNVector3(-0.29,0,OpeningLayout.portalWorldZ)
            let target = OpeningLayout.portalWorldZ
            let entry = abs(e.z-target) > 0.09 ? threshold : point(House.foyerEntrance)
            return moveEnemy(toward:entry,speed:speed,dt:dt)
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
        guard phase == .playing || phase == .intro || phase == .downstairs || phase == .openingDoor || phase == .gardenReveal || phase == .ending else {
            lastTime = 0
            return
        }
        guard lastTime != 0 else { lastTime = link.timestamp; return }
        let dt = min(Float(link.timestamp-lastTime),0.05)
        lastTime = link.timestamp
        switch phase {
        case .intro: updateIntro(dt:dt); return
        case .downstairs: updateDownstairs(dt:dt); return
        case .openingDoor: doorTransition(dt:dt); return
        case .gardenReveal: updateGardenReveal(dt:dt); return
        case .ending: updateEnding(dt:dt); return
        default: break
        }
        elapsed += dt
        if activeHouseHunt && elapsed > nextBurp {
            if !breaker.isActive && newsStarted == nil { ambientBurp() }
            nextBurp = elapsed+Float.random(in:16...32)
        }
        if elapsed > messageUntil { message.text = "" }
        let moving = !hidden && hypot(stick.vector.x,stick.vector.y) > 0.12
        let sprint = running && moving && !crouched && stamina > 2
        var stepped = false
        if !hidden {
            let speed: Float = crouched ? 1.22 : (sprint ? (story.stage == .retreat ? 4.8 : 4) : 2.2)
            let requested = moving ? SIMD2<Float>(Float(stick.vector.x),-Float(stick.vector.y))*speed : .zero
            movement += (requested-movement)*min(1,dt*(moving ? 12 : 19))
            let dx = (-sin(yaw)*movement.y+cos(yaw)*movement.x)*dt
            let dz = (-cos(yaw)*movement.y-sin(yaw)*movement.x)*dt
            let previous = camera.position
            var p = previous
            if playerCanMove(x:p.x+dx,z:p.z) { p.x += dx }
            if playerCanMove(x:p.x,z:p.z+dz) { p.z += dz }
            let traveled = distance(previous,p)
            stepped = traveled > 0.002
            stepPhase += traveled*(sprint ? 4.5 : 5.1)
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            let targetHeight: Float = OpeningLayout.heightInHouse(x:p.x,z:p.z)+(crouched ? 0.95 : 1.60) + (stepped && !reduceMotion ? sin(stepPhase)*(sprint ? 0.046 : 0.028) : 0)
            p.y += (targetHeight-p.y)*min(1,dt*18)
            let tilt = reduceMotion ? 0 : -movement.x*0.010
            lookRoll += (tilt-lookRoll)*min(1,dt*9)
            camera.position = p
            camera.eulerAngles = SCNVector3(pitch,yaw,lookRoll)
            if !crouched { footsteps(distance:traveled,sprinting:sprint) }
        }
        stamina = min(100,max(0,stamina+(sprint && stepped ? -13 : 13)*dt))
        if running && stamina <= 2 { setRunning(false) }
        battery = min(100,max(0,battery+(flashlight && !hidden ? -0.65 : 1.25)*dt))
        if battery <= 0 { flashlight = false; lightButton.setTitle("LIGHT OFF",for:.normal) }
        torch.light?.intensity = flashlight && !hidden ? flashlightIntensity : 0
        camera.camera?.exposureOffset = wardrobeReturn != nil ? 0.34 : (hidden ? -1 : 0)
        moveDoors(dt:dt)
        updateBulletin()
        if activeHouseHunt {
            if newsStarted == nil { updateYamenVoice() }
            let traced = updatePhone()
            let trap = tripFloorboard()
            guard updateEnemy(dt:dt,sprint:sprint,moving:stepped,traced:traced || trap) else { return }
        } else if story.stage == .retreat && !updateRetreat(dt:dt) { return }
        if gardenDoorOpen {
            rainVolume(camera.position.z < frontDoorWorldZ ? 0.76 : 0.29)
        }
        status.text = "3:\(String(format:"%02d",min(59,Int(elapsed/12)))) AM   LIGHT \(Int(battery))%   BREATH \(Int(stamina))%"
        objective.text = missionObjective
        if hidden { hint.text = wardrobeReturn != nil ? "LOOK THROUGH THE GAP · USE TO LEAVE" : "HIDDEN · USE TO LEAVE" }
        else if let missionHint { hint.text = missionHint }
        else if let index = nearbyCupboard() {
            let cupboard = cupboards[index]
            hint.text = canTakeFuse(from:cupboard) ? "USE · TAKE FUSE" :
                (cupboard.isOpen ? "USE · CLOSE CUPBOARD" : "USE · OPEN CUPBOARD")
        }
        else if near(shelter,range:2) { hint.text = "USE · STEEL SHELTER" }
        else if notes.contains(where:{ !readNotes.contains($0.cell) && near($0.cell,range:1.8) }) { hint.text = "USE · READ NOTE" }
        else if near(House.panel) { hint.text = "USE · FUSE BOX" } else if near(House.exit) { hint.text = story.stage == .exit ? "USE · ESCAPE" : "EXIT LOCKED" }
        else if House.closets.contains(where:{ near($0,range:2) }) { hint.text = "USE · HIDE" } else { hint.text = elapsed < huntUntil ? "HE’S LOOKING FOR YOU" : "DRAG RIGHT SIDE TO LOOK" }
    }
}
