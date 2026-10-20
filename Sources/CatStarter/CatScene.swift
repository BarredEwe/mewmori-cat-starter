import AppKit
import SpriteKit

public final class CatScene: SKScene {
    private let rootScale: CGFloat = 2.6
    private let catRoot = SKNode()
    private var nodes: [String: SKSpriteNode] = [:]
    private var rig: Rig!
    private var clips: [String: AnimationClip] = [:]
    private var startedAt: TimeInterval?
    private var nextWalkAt: TimeInterval?
    private var lastReportedPosition: Int?
    private let walkActionKey = "CatStarter.walk"
    private let isUITesting: Bool

    public var onCatPositionChange: ((CGFloat) -> Void)?

    public init(size: CGSize, isUITesting: Bool = false) {
        self.isUITesting = isUITesting
        super.init(size: size)
    }

    required public init?(coder aDecoder: NSCoder) {
        isUITesting = false
        super.init(coder: aDecoder)
    }

    public override func didMove(to view: SKView) {
        backgroundColor = NSColor(red: 0.10, green: 0.07, blue: 0.05, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        view.ignoresSiblingOrder = true
        loadRig()
        addChild(catRoot)
    }

    public override func update(_ currentTime: TimeInterval) {
        if startedAt == nil {
            startedAt = currentTime
        }
        let elapsed = currentTime - (startedAt ?? currentTime)
        let activeClips = ["breathe", "blink"].compactMap { name -> (AnimationClip, Double)? in
            guard let clip = clips[name] else { return nil }
            return (clip, 1)
        }
        let currentPose = composePose(from: activeClips, at: elapsed)

        nodes["body"]?.yScale = 1 + currentPose.value(for: "body", property: .scaleY)
        nodes["eye.left"]?.alpha = 1 + currentPose.value(for: "eye.left", property: .alpha)
        nodes["eye.right"]?.alpha = 1 + currentPose.value(for: "eye.right", property: .alpha)
        scheduleWalkIfNeeded(at: currentTime)
        let reportedPosition = Int(catRoot.position.x.rounded())
        if reportedPosition != lastReportedPosition {
            lastReportedPosition = reportedPosition
            onCatPositionChange?(catRoot.position.x)
        }
    }

    public override func mouseMoved(with event: NSEvent) {
        guard let view else { return }
        let pointInView = view.convert(event.locationInWindow, from: nil)
        let location = convertPoint(fromView: pointInView)
        let direction = CGVector(dx: location.x / max(size.width / 2, 1), dy: location.y / max(size.height / 2, 1))
        let offset = min(rig.gaze.maxOffset, max(-rig.gaze.maxOffset, direction.dx * rig.gaze.maxOffset))
        for pupil in rig.gaze.pupils {
            nodes[pupil]?.position.x = CGFloat(offset)
        }
    }

    private func loadRig() {
        let decoder = JSONDecoder()
        rig = try! decoder.decode(Rig.self, from: resource(named: "rig", extension: "json", subdirectory: "Resources"))
        let clipNames = ["breathe", "blink"]
        for name in clipNames {
            clips[name] = try! decoder.decode(
                AnimationClip.self,
                from: resource(named: name, extension: "json", subdirectory: "Resources/clips")
            )
        }

        let textures: Set<String> = Set(rig.parts.compactMap { (part: Part) -> String? in
            let file = URL(fileURLWithPath: part.texture)
            let name = file.deletingPathExtension().lastPathComponent
            let fileExtension = file.pathExtension
            guard resourceBundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources/Art") != nil else {
                return nil
            }
            return part.texture
        })
        let issues = RigValidator.validate(rig, availableTextures: textures)
        precondition(issues.allSatisfy { $0.severity != .error }, issues.map(\.description).joined(separator: "\n"))
        buildNodes()
        catRoot.setScale(rootScale)
    }

    private func buildNodes() {
        var pending = rig.parts
        while !pending.isEmpty {
            let ready = pending.filter { part in
                part.parent == nil || nodes[part.parent!] != nil
            }.sorted(by: { $0.z < $1.z })
            precondition(!ready.isEmpty, "rig hierarchy cannot be built")

            for part in ready {
                let texture = SKTexture(image: NSImage(data: resource(named: part.texture, extension: "png", subdirectory: "Resources/Art"))!)
                let node = SKSpriteNode(texture: texture)
                node.name = part.id
                node.anchorPoint = CGPoint(x: part.anchor?.x ?? 0.5, y: part.anchor?.y ?? 0.5)
                node.size = CGSize(
                    width: texture.size().width / rig.pixelsPerUnit,
                    height: texture.size().height / rig.pixelsPerUnit
                )
                node.position = CGPoint(x: part.position.x, y: part.position.y)
                node.zPosition = CGFloat(part.z)

                if let parent = part.parent, let parentNode = nodes[parent] {
                    parentNode.addChild(node)
                } else {
                    catRoot.addChild(node)
                }
                nodes[part.id] = node
                pending.removeAll { $0.id == part.id }
            }
        }
    }

    private func scheduleWalkIfNeeded(at currentTime: TimeInterval) {
        if nextWalkAt == nil {
            nextWalkAt = currentTime + nextPause()
            return
        }

        guard catRoot.action(forKey: walkActionKey) == nil,
              currentTime >= nextWalkAt ?? .infinity
        else {
            return
        }

        let targetX = isUITesting
            ? (catRoot.position.x <= 0 ? 55 : -55)
            : CGFloat.random(in: -55...55)
        let distance = abs(targetX - catRoot.position.x)
        guard distance > 8 else {
            nextWalkAt = currentTime + nextPause()
            return
        }

        let speed: CGFloat = isUITesting ? 110 : 35
        let duration = TimeInterval(distance / speed)
        let move = SKAction.moveTo(x: targetX, duration: duration)
        let sway = SKAction.sequence([
            .moveBy(x: 0, y: 2, duration: duration / 2),
            .moveBy(x: 0, y: -2, duration: duration / 2)
        ])
        catRoot.run(.group([move, sway]), withKey: walkActionKey)
        nextWalkAt = currentTime + duration + nextPause()
    }

    private func nextPause() -> TimeInterval {
        isUITesting ? 1.25 : .random(in: 1.5...3.5)
    }

    private func resource(named name: String, extension: String, subdirectory: String? = nil) -> Data {
        let file = URL(fileURLWithPath: name)
        let resourceName = file.pathExtension == `extension`
            ? file.deletingPathExtension().lastPathComponent
            : name
        let url = resourceBundle.url(forResource: resourceName, withExtension: `extension`, subdirectory: subdirectory)!
        return try! Data(contentsOf: url)
    }

    private var resourceBundle: Bundle {
#if SWIFT_PACKAGE
        Bundle.module
#else
        Bundle.main
#endif
    }
}
