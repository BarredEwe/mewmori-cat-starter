import Foundation

struct Rig: Codable, Equatable {
    let referenceHeight: Double
    let pixelsPerUnit: Double
    let parts: [Part]
    let gaze: Gaze
}

struct Part: Codable, Equatable {
    let id: String
    let texture: String
    let parent: String?
    let position: Point
    let z: Int
    let anchor: Point?
}

struct Gaze: Codable, Equatable {
    let pupils: [String]
    let maxOffset: Double
}

struct Point: Codable, Equatable {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        x = try values.decode(Double.self)
        y = try values.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(x)
        try values.encode(y)
    }
}
