import Foundation

enum TrackProperty: String, Codable {
    case x
    case y
    case rotation
    case scaleX
    case scaleY
    case alpha
}

struct AnimationClip: Codable, Equatable {
    let id: String
    let duration: Double
    let loop: Bool
    let tracks: [Track]
}

struct Track: Codable, Equatable {
    let part: String
    let property: TrackProperty
    let keys: [Keyframe]
    let easing: Easing

    func value(at time: Double) -> Double {
        guard let first = keys.first else { return 0 }
        if time <= first.time { return first.value }
        guard let last = keys.last else { return first.value }
        if time >= last.time { return last.value }

        for pair in zip(keys, keys.dropFirst()) {
            let start = pair.0
            let end = pair.1
            guard time <= end.time else { continue }
            let span = end.time - start.time
            guard span > 0 else { return end.value }
            let progress = (time - start.time) / span
            let eased = (start.easing ?? easing).apply(progress)
            return start.value + (end.value - start.value) * eased
        }

        return last.value
    }
}

struct Keyframe: Codable, Equatable {
    let time: Double
    let value: Double
    let easing: Easing?
}

enum Easing: String, Codable {
    case linear
    case easeInOut

    func apply(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        switch self {
        case .linear:
            return clamped
        case .easeInOut:
            return clamped * clamped * (3 - 2 * clamped)
        }
    }
}

struct Pose {
    private(set) var values: [String: Double] = [:]

    mutating func add(part: String, property: TrackProperty, value: Double, weight: Double = 1) {
        values[key(part, property)] = values[key(part, property), default: 0] + value * weight
    }

    func value(for part: String, property: TrackProperty) -> Double {
        values[key(part, property), default: 0]
    }

    private func key(_ part: String, _ property: TrackProperty) -> String {
        "\(part).\(property.rawValue)"
    }
}

func composePose(from clips: [(AnimationClip, Double)], at time: Double) -> Pose {
    var result = Pose()
    for (clip, weight) in clips {
        let localTime: Double
        if clip.loop, clip.duration > 0 {
            localTime = time.truncatingRemainder(dividingBy: clip.duration)
        } else {
            localTime = min(time, clip.duration)
        }
        for track in clip.tracks {
            result.add(
                part: track.part,
                property: track.property,
                value: track.value(at: localTime),
                weight: weight
            )
        }
    }
    return result
}
