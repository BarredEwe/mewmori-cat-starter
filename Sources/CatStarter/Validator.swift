import Foundation

struct ValidationIssue: Equatable, CustomStringConvertible {
    enum Severity: String, Equatable {
        case error
        case warning
    }

    let severity: Severity
    let message: String

    var description: String {
        "\(severity.rawValue): \(message)"
    }
}

enum RigValidator {
    static func validate(_ rig: Rig, availableTextures: Set<String>) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var seen: Set<String> = []
        let ids = Set(rig.parts.map(\.id))

        for part in rig.parts {
            if !seen.insert(part.id).inserted {
                issues.append(.init(severity: .error, message: "duplicate part '\(part.id)'"))
            }
            if let parent = part.parent, !ids.contains(parent) {
                issues.append(.init(severity: .error, message: "part '\(part.id)' references unknown parent '\(parent)'"))
            }
            if !availableTextures.contains(part.texture) {
                issues.append(.init(severity: .error, message: "texture '\(part.texture)' is missing"))
            }
        }

        if rig.partsInHierarchyOrder == nil {
            issues.append(.init(severity: .error, message: "rig hierarchy contains a cycle"))
        }

        return issues
    }
}

private extension Rig {
    var partsInHierarchyOrder: [Part]? {
        var remaining = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var built: Set<String> = []
        var ordered: [Part] = []

        while !remaining.isEmpty {
            let ready = remaining.values.filter { part in
                part.parent == nil || built.contains(part.parent!)
            }
            guard !ready.isEmpty else { return nil }

            for part in ready.sorted(by: { $0.z < $1.z }) {
                ordered.append(part)
                built.insert(part.id)
                remaining.removeValue(forKey: part.id)
            }
        }

        return ordered
    }
}
