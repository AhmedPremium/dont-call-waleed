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
    enum Phase { case title, playing, paused, caught, escaped }
    private var phase = Phase.title
    private let sceneView = SCNView()
    private var world = SCNScene(), camera = SCNNode(), torch = SCNNode(), enemy = SCNNode()
    private var fuseNodes = [SCNNode](), lamps = [SCNNode]()
    private let stick = Stick(frame:.zero), lookSurface = UIView(), controls = UIView(), shade = UIView(), danger = UIView(), scare = UIView()
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
    private var running = false, hidden = false, flashlight = true, power = false, ringing = false, soundEnabled = true
    private var collected = Set<Int>(), route = [Cell]()
    private var nextCall: Float = 24, ringEnd: Float = 0, huntUntil: Float = 0, routeTime: Float = 0, messageUntil: Float = 0, footTime: Float = 0
    private var enemyTarget = House.enemy, routedTarget = House.enemy, patrolIndex = 0
    private var players: [String:AVAudioPlayer] = [:]

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        if let url = Bundle.main.url(forResource:"VCR_OSD_MONO_1.001",withExtension:"ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        }
        setupUI(); buildWorld(); loadAudio()
        showMenu("DON'T CALL\nWALEED", "You made the call.\nSomething answered.","ENTER THE HOUSE   >")
        NotificationCenter.default.addObserver(self,selector:#selector(background),name:UIApplication.willResignActiveNotification,object:nil)
    }
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated)
        if displayLink == nil {
            let link = CADisplayLink(target:self,selector:#selector(tick(_:))); link.preferredFramesPerSecond = 60
            link.add(to:.main,forMode:.common); displayLink = link
        }
    }
    override func viewDidDisappear(_ animated:Bool) { super.viewDidDisappear(animated); displayLink?.invalidate(); displayLink = nil; players.values.forEach { $0.stop() }; UIApplication.shared.isIdleTimerDisabled = false }
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
        for v in [sceneView,danger,controls,shade,scare] { v.frame = view.bounds; v.autoresizingMask = [.flexibleWidth,.flexibleHeight]; view.addSubview(v) }
        sceneView.antialiasingMode = .multisampling2X; sceneView.preferredFramesPerSecond = 60; sceneView.rendersContinuously = true; sceneView.isUserInteractionEnabled = false
        danger.backgroundColor = .red; danger.alpha = 0; danger.isUserInteractionEnabled = false
        for v in [lookSurface,stick,status,objective,message,hint,use,lightButton,sprintButton,phoneButton,pauseButton] { v.translatesAutoresizingMaskIntoConstraints = false; controls.addSubview(v) }
        lookSurface.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(look(_:))))
        label(status,14); label(objective,14,UIColor(red:0.84,green:0.74,blue:0.5,alpha:1)); label(message,17); message.textAlignment = .center; label(hint,13); hint.textAlignment = .center
        button(use,"USE",#selector(interact)); button(lightButton,"LIGHT ON",#selector(toggleLight)); button(sprintButton,"HOLD: RUN",#selector(stopRun)); button(phoneButton,"SILENCE",#selector(silence)); button(pauseButton,"II",#selector(pauseGame))
        sprintButton.addTarget(self,action:#selector(startRun),for:.touchDown)
        sprintButton.addTarget(self,action:#selector(stopRun),for:[.touchUpOutside,.touchCancel,.touchDragExit])
        let safe = controls.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            lookSurface.leadingAnchor.constraint(equalTo:controls.centerXAnchor),lookSurface.trailingAnchor.constraint(equalTo:controls.trailingAnchor),lookSurface.topAnchor.constraint(equalTo:controls.topAnchor),lookSurface.bottomAnchor.constraint(equalTo:controls.bottomAnchor),
            stick.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:30),stick.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-26),stick.widthAnchor.constraint(equalToConstant:138),stick.heightAnchor.constraint(equalTo:stick.widthAnchor),
            status.topAnchor.constraint(equalTo:safe.topAnchor,constant:16),status.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:22),
            objective.topAnchor.constraint(equalTo:status.bottomAnchor,constant:9),objective.leadingAnchor.constraint(equalTo:status.leadingAnchor),objective.widthAnchor.constraint(lessThanOrEqualTo:controls.widthAnchor,multiplier:0.7),
            pauseButton.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-20),pauseButton.topAnchor.constraint(equalTo:safe.topAnchor,constant:14),pauseButton.widthAnchor.constraint(equalToConstant:52),
            message.centerXAnchor.constraint(equalTo:controls.centerXAnchor),message.topAnchor.constraint(equalTo:objective.bottomAnchor,constant:20),message.widthAnchor.constraint(equalTo:controls.widthAnchor,multiplier:0.8),
            use.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-24),use.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-28),use.widthAnchor.constraint(equalToConstant:116),
            sprintButton.trailingAnchor.constraint(equalTo:use.leadingAnchor,constant:-12),sprintButton.bottomAnchor.constraint(equalTo:use.bottomAnchor),sprintButton.widthAnchor.constraint(equalToConstant:116),
            lightButton.trailingAnchor.constraint(equalTo:use.trailingAnchor),lightButton.bottomAnchor.constraint(equalTo:use.topAnchor,constant:-12),lightButton.widthAnchor.constraint(equalToConstant:116),
            phoneButton.trailingAnchor.constraint(equalTo:lightButton.leadingAnchor,constant:-12),phoneButton.bottomAnchor.constraint(equalTo:lightButton.bottomAnchor),phoneButton.widthAnchor.constraint(equalToConstant:116),
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
        scare.isUserInteractionEnabled = false; scare.isHidden = true
    }
    private func material(_ c:UIColor,glow:Bool = false) -> SCNMaterial { let m = SCNMaterial(); m.diffuse.contents = c; m.roughness.contents = 0.95; if glow { m.emission.contents = c }; return m }
    @discardableResult private func box(_ s:SCNVector3,_ p:SCNVector3,_ color:UIColor,parent:SCNNode? = nil,glow:Bool = false) -> SCNNode {
        let g = SCNBox(width:CGFloat(s.x),height:CGFloat(s.y),length:CGFloat(s.z),chamferRadius:0.01); g.materials = [material(color,glow:glow)]
        let n = SCNNode(geometry:g); n.position = p; (parent ?? world.rootNode).addChildNode(n); return n
    }
    private func point(_ c:Cell,y:Float = 0) -> SCNVector3 { SCNVector3((Float(c.x)+0.5)*House.tile,y,(Float(c.z)+0.5)*House.tile) }
    @discardableResult private func sphere(_ r:CGFloat,_ p:SCNVector3,_ c:UIColor,_ parent:SCNNode) -> SCNNode {
        let g = SCNSphere(radius:r); g.segmentCount = 16; g.materials = [material(c,glow:true)]; let n = SCNNode(geometry:g); n.position = p; parent.addChildNode(n); return n
    }
    private func buildWorld() {
        world = SCNScene(); lamps = []; fuseNodes = []; world.background.contents = UIColor.black
        world.fogColor = UIColor(red:0.025,green:0.03,blue:0.035,alpha:1); world.fogStartDistance = 6; world.fogEndDistance = 22
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.color = UIColor(red:0.22,green:0.27,blue:0.36,alpha:1); ambient.light?.intensity = 240; world.rootNode.addChildNode(ambient)
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
        for c in [Cell(x:4,z:2),Cell(x:12,z:2),Cell(x:4,z:7),Cell(x:12,z:7),Cell(x:4,z:12),Cell(x:12,z:12)] {
            let p = point(c)
            box(SCNVector3(2.8,0.015,3.8),SCNVector3(p.x,0.02,p.z),UIColor(red:0.2,green:0.07,blue:0.06,alpha:1))
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
        enemy = SCNNode(); world.rootNode.addChildNode(enemy); enemy.position = point(House.enemy)
        box(SCNVector3(0.65,1.25,0.35),SCNVector3(0,1.35,0),UIColor(white:0.035,alpha:1),parent:enemy)
        for x in [Float(-0.43),0.43] { box(SCNVector3(0.15,1.45,0.18),SCNVector3(x,1.15,0),UIColor(white:0.045,alpha:1),parent:enemy) }
        for x in [Float(-0.2),0.2] { box(SCNVector3(0.16,0.9,0.19),SCNVector3(x,0.45,0),UIColor(white:0.025,alpha:1),parent:enemy) }
        let head = sphere(0.29,SCNVector3(0,2.2,0),UIColor(red:0.58,green:0.56,blue:0.48,alpha:1),enemy); head.scale = SCNVector3(0.85,1.25,0.7)
        for x in [Float(-0.11),0.11] { sphere(0.044,SCNVector3(x,2.24,-0.2),.red,enemy) }
        box(SCNVector3(0.17,0.06,0.025),SCNVector3(0,2.08,-0.21),.black,parent:enemy)
        camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.fieldOfView = 76; camera.camera?.zNear = 0.06; camera.camera?.zFar = 45
        camera.camera?.vignettingIntensity = 0.8; camera.camera?.vignettingPower = 1.8
        camera.position = point(House.spawn,y:1.6); world.rootNode.addChildNode(camera)
        torch = SCNNode(); torch.light = SCNLight(); torch.light?.type = .spot; torch.light?.color = UIColor(red:0.95,green:0.91,blue:0.78,alpha:1); torch.light?.intensity = 1100
        torch.light?.spotInnerAngle = 24; torch.light?.spotOuterAngle = 65; torch.light?.attenuationStartDistance = 2; torch.light?.attenuationEndDistance = 18; camera.addChildNode(torch)
        sceneView.scene = world; sceneView.pointOfView = camera; sceneView.audioListener = camera
    }
    @objc private func showHelp() {
        let panel = UIAlertController(title:"HOW TO SURVIVE",message:"Left thumb: move. Drag the right side to look.\n\nFind three cyan fuses. USE the red fuse box, then the green exit.\n\nRunning and ringing calls reveal your position. SILENCE your phone. Break Waleed's line of sight before using a gold-handled cupboard to hide.\n\nThe flashlight recharges when off. Burps come from different rooms.\n\nContains sudden sounds and jumpscares.",preferredStyle:.alert)
        panel.addAction(UIAlertAction(title:"GOT IT",style:.default))
        present(panel,animated:true)
    }
    private func stopBurps() { world.rootNode.childNodes.filter { $0.name == "ambientBurp" }.forEach { $0.removeAllAudioPlayers(); $0.removeFromParentNode() } }
    private func ambientBurp() {
        guard soundEnabled,let source = burpSources.randomElement() else { return }
        let candidates = House.patrol.filter { distance(point($0),camera.position) > 4 }
        guard let c = candidates.randomElement() else { return }
        let node = SCNNode(); node.name = "ambientBurp"; node.position = point(c,y:1.2)
        world.rootNode.addChildNode(node); node.addAudioPlayer(SCNAudioPlayer(source:source))
        node.runAction(.sequence([.wait(duration:3),.removeFromParentNode()]))
    }
    private func loadAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default)
        for i in 1...3 {
            if let source = SCNAudioSource(fileNamed:"burp\(i).wav") {
                source.isPositional = true; source.shouldStream = false; source.volume = 1
                source.load(); burpSources.append(source)
            }
        }
        for name in ["drone","ring","step","sting","pickup","heartbeat"] {
            if let url = Bundle.main.url(forResource:name,withExtension:"wav"),let p = try? AVAudioPlayer(contentsOf:url) { p.prepareToPlay(); players[name] = p }
        }
        for name in ["drone","ring","heartbeat"] { players[name]?.numberOfLoops = -1; players[name]?.volume = 0.35 }
    }
    private func play(_ name:String) { guard soundEnabled else { return }; players[name]?.currentTime = 0; players[name]?.play() }
    @objc private func toggleSound() { soundEnabled.toggle(); soundButton.setTitle(soundEnabled ? "SOUND: ON" : "SOUND: OFF",for:.normal); if !soundEnabled { players.values.forEach { $0.stop() }; stopBurps() } }
    private func showMenu(_ title:String,_ detail:String,_ action:String) {
        titleLabel.text = title; detailLabel.text = detail; startButton.setTitle(action,for:.normal); shade.isHidden = false; controls.isHidden = true; stick.reset(); running = false
        players.values.forEach { $0.stop() }; stopBurps(); sceneView.isPlaying = false
        clockLabel.isHidden = phase != .title; eyebrow.isHidden = phase != .title
        UIApplication.shared.isIdleTimerDisabled = false
    }
    @objc private func menuAction() {
        if phase != .paused { resetGame() }; phase = .playing; shade.isHidden = true; controls.isHidden = false; sceneView.isPlaying = true; lastTime = 0; UIApplication.shared.isIdleTimerDisabled = true
        if soundEnabled { players["drone"]?.play(); if ringing { players["ring"]?.play() } }
    }
    private func resetGame() {
        elapsed = 0; nextBurp = 9; yaw = 0; pitch = 0; hidden = false; flashlight = true; battery = 100; stamina = 100; collected = []; power = false; ringing = false; nextCall = 24; huntUntil = 0; route = []; routeTime = 0; patrolIndex = 0; footTime = 0
        enemyTarget = House.enemy; buildWorld(); danger.alpha = 0; scare.isHidden = true; lightButton.setTitle("LIGHT ON",for:.normal); tell("Find the cyan fuses. Don’t let him hear you.",duration:7)
    }
    @objc private func pauseGame() { guard phase == .playing else { return }; phase = .paused; showMenu("STAY QUIET","The house is paused.\nFind three cyan fuses, then the red fuse box.\nThe green door is your way out.\nGold handles mark hiding cupboards.","RESUME") }
    @objc private func background() { pauseGame() }
    @objc private func startRun() { running = true }
    @objc private func stopRun() { running = false }
    @objc private func toggleLight() { guard phase == .playing,!hidden else { return }; flashlight.toggle(); if battery < 1 { flashlight = false }; lightButton.setTitle(flashlight ? "LIGHT ON" : "LIGHT OFF",for:.normal) }
    @objc private func silence() { guard phase == .playing,ringing else { return }; ringing = false; players["ring"]?.stop(); tell("Call declined. He heard enough.") }
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
            if huntUntil > elapsed && distance(camera.position,enemy.position) < 8 { tell("He saw you. Lose him before hiding!"); return }
            hidden = true; flashlight = false; lightButton.setTitle("LIGHT OFF",for:.normal); stick.reset(); tell("Hidden. Keep quiet. USE to leave.",duration:8); return
        }
        tell("Nothing within reach. Try a cyan fuse or a gold handle.")
    }
    private func finish(escaped:Bool) {
        phase = escaped ? .escaped : .caught
        if escaped { showMenu("YOU GOT OUT.","The line is dead.\nThis time, leave it that way.\n\nFirst night complete.","PLAY AGAIN") }
        else {
            play("sting"); danger.alpha = 0.6; scare.isHidden = false; scare.backgroundColor = .black; scare.subviews.forEach { $0.removeFromSuperview() }
            let face = UILabel(frame:scare.bounds); face.autoresizingMask = [.flexibleWidth,.flexibleHeight]; face.textAlignment = .center; face.numberOfLines = 0; face.text = "●    ●\n\n▰"; face.textColor = .red; face.font = .systemFont(ofSize:110,weight:.black); scare.addSubview(face)
            UIImpactFeedbackGenerator(style:.heavy).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline:.now()+0.85) { [weak self] in
                guard let self = self,self.phase == .caught else { return }; self.scare.isHidden = true
                self.showMenu("HE FOUND YOU.","Don’t call Waleed at 3 AM.\n\nWalk to stay quiet. Silence incoming calls.\nHide by a gold handle.\nBreak his line of sight before hiding.","TRY AGAIN")
            }
        }
    }
    @objc private func tick(_ link:CADisplayLink) {
        guard phase == .playing else { lastTime = 0; return }; guard lastTime != 0 else { lastTime = link.timestamp; return }
        let dt = min(Float(link.timestamp-lastTime),0.05); lastTime = link.timestamp; elapsed += dt
        if elapsed > nextBurp { ambientBurp(); nextBurp = elapsed+Float.random(in:10...24) }
        if elapsed > messageUntil { message.text = "" }
        let moving = !hidden && hypot(stick.vector.x,stick.vector.y) > 0.12, sprint = running && stamina > 2 && !hidden && hypot(stick.vector.x,stick.vector.y) > 0.12
        stamina = min(100,max(0,stamina+(sprint ? -22 : 12)*dt))
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
        torch.light?.intensity = flashlight && !hidden ? 1100 : 0; camera.camera?.exposureOffset = hidden ? -2 : 0
        if elapsed > nextCall { ringing = true; ringEnd = elapsed+9; nextCall = elapsed+Float.random(in:35...52); tell("WALEED IS CALLING. Silence your phone!",duration:7); play("ring") }
        if ringing && elapsed > ringEnd { ringing = false; players["ring"]?.stop() }; phoneButton.isHidden = !ringing
        let p = camera.position,e = enemy.position,dist = distance(camera.position,enemy.position)
        let sight = !hidden && dist < (flashlight ? 15 : 6) && House.visible(e.x,e.z,p.x,p.z), heard = (ringing && dist < 22) || (sprint && dist < 12)
        if elapsed > 13 && (sight || heard) { huntUntil = elapsed+8; enemyTarget = House.cell(p.x,p.z) }
        let hunting = elapsed < huntUntil
        if elapsed > 13 {
            if !hunting && distance(e,point(enemyTarget)) < 0.4 { patrolIndex = (patrolIndex+1)%House.patrol.count; enemyTarget = House.patrol[patrolIndex] }
            if route.isEmpty || (elapsed > routeTime && routedTarget != enemyTarget) { route = House.path(from:House.cell(e.x,e.z),to:enemyTarget); routeTime = elapsed+0.7; routedTarget = enemyTarget }
            let target = route.first.map { point($0) } ?? point(enemyTarget)
            let d = distance(enemy.position,target)
            if d > 0.06 {
                let speed:Float = hunting ? (power ? 2.5 : 2.25) : 1.3
                let step = min(d,speed*dt)
                let vx = (target.x-enemy.position.x)/d,vz = (target.z-enemy.position.z)/d
                let nx = enemy.position.x+vx*step,nz = enemy.position.z+vz*step
                if House.walkable(nx,nz,radius:0.18) { enemy.position.x = nx; enemy.position.z = nz }
                enemy.eulerAngles.y = atan2(-vx,-vz); if d < 0.08 && !route.isEmpty { route.removeFirst() }
            }
            enemy.position.y = sin(elapsed*5)*0.035
            if !hidden && dist < 0.9 && House.visible(e.x,e.z,p.x,p.z) { finish(escaped:false); return }
        }
        danger.alpha = hunting ? CGFloat(0.06+max(0,1-dist/12)*0.14*(0.6+sin(elapsed*8)*0.4)) : 0
        if hunting && soundEnabled { if players["heartbeat"]?.isPlaying == false { players["heartbeat"]?.play() } } else { players["heartbeat"]?.stop() }
        status.text = "3:\(String(format:"%02d",min(59,Int(elapsed/12)))) AM   LIGHT \(Int(battery))%   BREATH \(Int(stamina))%"
        objective.text = power ? "POWER ON · REACH THE GREEN EXIT" : "FUSES \(collected.count)/3 · \(collected.count == 3 ? "FIND THE RED FUSE BOX" : "SEARCH THE HOUSE")"
        if hidden { hint.text = "HIDDEN · USE TO LEAVE" } else if hunting { hint.text = "HE’S LISTENING" }
        else if House.fuses.indices.contains(where:{ !collected.contains($0) && near(House.fuses[$0]) }) { hint.text = "USE · TAKE FUSE" }
        else if near(House.panel) { hint.text = "USE · FUSE BOX" } else if near(House.exit) { hint.text = "USE · EXIT" }
        else if House.closets.contains(where:{ near($0,range:2) }) { hint.text = "USE · HIDE" } else { hint.text = "DRAG RIGHT SIDE TO LOOK" }
    }
}
