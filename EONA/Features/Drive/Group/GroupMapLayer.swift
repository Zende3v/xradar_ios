import MapKit
import SwiftUI
import UIKit
import EonaCore

/// Another member of the group as the main map knows them: who, and in which colour. Where they
/// are comes separately, as a string of timed positions (GroupSample).
struct GroupMapMember: Equatable {
    let id: String
    let name: String
    let avatarURL: URL?
    /// Their colour in the group, the same in every list and on every map.
    let colorIndex: Int
}

/// One position of another member, timed on the server's clock (seconds since 1970).
struct GroupSample: Equatable {
    let at: TimeInterval
    let lat: Double
    let lon: Double
    let bearing: Double?
    let speedMps: Double
}

/// What the main map shows of the group.
///
/// Positions arrive as they are sent (the group stream), each timed on the server's clock. The map
/// never guesses ahead: it shows every member a few seconds in the past, between two positions
/// it really received, along that member's own route — the way a video plays from its buffer.
/// The movement is as smooth as the driver's own arrow, and it never goes back on itself.
///
/// Deliberately not observed: the map reads it at every frame, and the driving screen is never
/// redrawn for it. [version] tells the map when the members, the routes or the focus changed.
@MainActor
final class GroupMapLayer {
    private(set) var version = 0
    private(set) var members: [GroupMapMember] = []
    /// Each member's last positions, oldest first.
    private(set) var samples: [String: [GroupSample]] = [:]
    /// The others' routes, by member, with their version and colour.
    private(set) var routes: [String: (rev: Int, colorIndex: Int, points: [GeoPoint])] = [:]
    /// The member the camera follows while following; nil = the driver.
    private(set) var focus: String?
    /// Raised to ask the map for a view of everyone at once.
    private(set) var overviewRequest = 0
    /// The server's clock minus this phone's, in seconds; nil until the server has spoken.
    private(set) var clockOffset: TimeInterval?

    private static let keptSamples = 12

    /// Now, on the server's clock.
    var serverNow: TimeInterval {
        Date().timeIntervalSince1970 + (clockOffset ?? 0)
    }

    /// The server said what time it was. What arrives is always a little late (the trip over the
    /// network), so the latest reading that makes the server look furthest ahead wins, and a lower
    /// one is only eased in slowly — the phone's clock may drift over hours.
    func noteServerTime(_ serverNow: Date?) {
        guard let serverNow else { return }
        let reading = serverNow.timeIntervalSince1970 - Date().timeIntervalSince1970
        guard let current = clockOffset else {
            clockOffset = reading
            return
        }
        clockOffset = reading > current ? reading : current + (reading - current) * 0.05
    }

    func setMembers(_ fresh: [GroupMapMember]) {
        guard fresh != members else { return }
        members = fresh
        let ids = Set(fresh.map(\.id))
        samples = samples.filter { ids.contains($0.key) }
        version += 1
    }

    /// One more position of [memberId]; an older or repeated one is ignored.
    func addSample(_ memberId: String, _ sample: GroupSample) {
        var list = samples[memberId] ?? []
        if let last = list.last, sample.at <= last.at { return }
        list.append(sample)
        if list.count > Self.keptSamples { list.removeFirst(list.count - Self.keptSamples) }
        samples[memberId] = list
    }

    func setRoute(_ memberId: String, rev: Int, colorIndex: Int, points: [GeoPoint]) {
        routes[memberId] = (rev, colorIndex, points)
        version += 1
    }

    /// Only these members keep a route on the map.
    func keepRoutes(for ids: Set<String>) {
        let gone = routes.keys.filter { !ids.contains($0) }
        guard !gone.isEmpty else { return }
        for id in gone { routes[id] = nil }
        version += 1
    }

    func setFocus(_ id: String?) {
        guard id != focus else { return }
        focus = id
        version += 1
    }

    func requestOverview() {
        overviewRequest += 1
        version += 1
    }

    func clear() {
        guard !members.isEmpty || !routes.isEmpty || focus != nil || !samples.isEmpty else { return }
        members = []
        samples = [:]
        routes = [:]
        focus = nil
        version += 1
    }
}

/// Profile pictures, loaded once and kept for the session: the map and the list share them.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private var images: [URL: UIImage] = [:]
    private var waiting: [URL: [(UIImage) -> Void]] = [:]

    func image(_ url: URL?) -> UIImage? {
        url.flatMap { images[$0] }
    }

    /// Hands the picture to [then] as soon as it is there — at once when it already is.
    func load(_ url: URL, then: @escaping (UIImage) -> Void) {
        if let image = images[url] {
            then(image)
            return
        }
        if waiting[url] != nil {
            waiting[url]?.append(then)
            return
        }
        waiting[url] = [then]
        Task {
            let data = try? await URLSession.shared.data(from: url).0
            let image = data.flatMap(UIImage.init(data:))
            let callbacks = waiting.removeValue(forKey: url) ?? []
            guard let image else { return }
            images[url] = image
            for callback in callbacks { callback(image) }
        }
    }
}

/// Another member on the main map.
final class GroupMemberAnnotation: NSObject, MKAnnotation {
    let memberId: String
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(memberId: String, coordinate: CLLocationCoordinate2D) {
        self.memberId = memberId
        self.coordinate = coordinate
        super.init()
    }
}

/// Their picture in a ring of their colour, their heading as a small arrow on the ring, and their
/// name under it. Faded when their phone has gone quiet.
final class GroupMemberView: MKAnnotationView {
    static let reuseId = "xr-group-member"
    private static let photo: CGFloat = 34
    private static let ring: CGFloat = 3

    private let ringView = UIView()
    private let imageView = UIImageView()
    private let initialLabel = UILabel()
    private let arrow = CAShapeLayer()
    private let nameLabel = PaddedLabel()
    private var shownURL: URL?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let side = Self.photo + Self.ring * 2
        frame = CGRect(x: 0, y: 0, width: 96, height: side + 26)
        // The picture's centre sits on the member's position; the name hangs below.
        centerOffset = CGPoint(x: 0, y: (frame.height - side) / 2 - 2)

        ringView.frame = CGRect(x: (frame.width - side) / 2, y: 0, width: side, height: side)
        ringView.layer.cornerRadius = side / 2
        ringView.layer.shadowColor = UIColor.black.cgColor
        ringView.layer.shadowOpacity = 0.3
        ringView.layer.shadowRadius = 3
        ringView.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(ringView)

        imageView.frame = ringView.bounds.insetBy(dx: Self.ring, dy: Self.ring)
        imageView.layer.cornerRadius = Self.photo / 2
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        ringView.addSubview(imageView)

        initialLabel.frame = imageView.frame
        initialLabel.textAlignment = .center
        initialLabel.font = .systemFont(ofSize: 16, weight: .bold)
        initialLabel.textColor = .white
        ringView.addSubview(initialLabel)

        // A small chevron outside the ring, turned to where they go.
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: -5))
        path.addLine(to: CGPoint(x: 5, y: 3))
        path.addLine(to: CGPoint(x: -5, y: 3))
        path.close()
        arrow.path = path.cgPath
        arrow.position = CGPoint(x: side / 2, y: side / 2)
        ringView.layer.addSublayer(arrow)

        nameLabel.frame = CGRect(x: 0, y: side + 4, width: frame.width, height: 18)
        nameLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.layer.cornerRadius = 9
        nameLabel.layer.masksToBounds = true
        addSubview(nameLabel)

        collisionMode = .circle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Shows [member] in [color]; faded when their phone has gone quiet.
    @MainActor
    func show(_ member: GroupMapMember, color: UIColor, online: Bool) {
        ringView.backgroundColor = color
        arrow.fillColor = color.cgColor
        nameLabel.text = member.name
        nameLabel.backgroundColor = color.withAlphaComponent(0.92)
        nameLabel.sizeToFit()
        let width = min(max(nameLabel.bounds.width + 12, 30), frame.width)
        nameLabel.frame = CGRect(x: (frame.width - width) / 2, y: ringView.frame.maxY + 4, width: width, height: 18)
        alpha = online ? 1 : 0.5
        initialLabel.text = String(member.name.prefix(1)).uppercased()

        guard member.avatarURL != shownURL else { return }
        shownURL = member.avatarURL
        imageView.image = AvatarCache.shared.image(member.avatarURL)
        initialLabel.isHidden = imageView.image != nil
        if imageView.image == nil, let url = member.avatarURL {
            AvatarCache.shared.load(url) { [weak self] image in
                guard let self, self.shownURL == url else { return }
                self.imageView.image = image
                self.initialLabel.isHidden = true
            }
        }
    }

    /// The heading, relative to the map's own rotation; hidden when unknown.
    func point(towardDegrees degrees: Double?) {
        guard let degrees else {
            arrow.isHidden = true
            return
        }
        arrow.isHidden = false
        let side = ringView.bounds.width
        let radians = degrees * .pi / 180
        let radius = side / 2 + 4
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrow.position = CGPoint(x: side / 2 + sin(radians) * radius, y: side / 2 - cos(radians) * radius)
        arrow.setAffineTransform(CGAffineTransform(rotationAngle: radians))
        CATransaction.commit()
    }
}

/// A label with a little air on its sides, for the name under a member.
private final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 6, dy: 0))
    }
}

extension GroupPalette {
    static func uiColor(_ index: Int) -> UIColor {
        UIColor(color(index))
    }
}
