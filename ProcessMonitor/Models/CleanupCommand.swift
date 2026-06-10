import Foundation

struct CleanupCommand: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var isEnabled: Bool
}

// MARK: - Validation

enum ValidationResult: Equatable {
    case ok
    case blocked(reason: String)
}

enum CommandValidator {
    private static let rules: [(pattern: String, reason: String)] = [
        (#"\bchmod\b"#,                                         "chmod modifies file permissions"),
        (#"\bchown\b"#,                                         "chown modifies file ownership"),
        (#"rm\s+-[a-zA-Z]*(?:rf|fr)[a-zA-Z]*\s+/(?:\s|$)"#,     "rm -rf / would erase the root filesystem"),
        (#"rm\s+-[a-zA-Z]*(?:rf|fr)[a-zA-Z]*\s+~/?\s*$"#,     "rm -rf ~ would erase your home directory"),
        (#"rm\s+-[a-zA-Z]*(?:rf|fr)[a-zA-Z]*\s+~/\s"#,        "rm -rf ~/ would erase your home directory"),
        (#"rm\s+-[a-zA-Z]*(?:rf|fr)[a-zA-Z]*\s+\$HOME"#,      "rm -rf $HOME would erase your home directory"),
        (#"rm\s+-[a-zA-Z]*(?:rf|fr)[a-zA-Z]*\s+/\*"#,         "rm -rf /* would erase all files in root"),
        (#":\s*\(\s*\)\s*\{[^}]*:\s*\|[^}]*:&"#,              "This looks like a fork bomb"),
        (#">\s*/dev/sd"#,                                       "Writing to a raw block device is dangerous"),
        (#"\bdd\b.*\bof=/dev/"#,                                "dd to a block device is dangerous"),
    ]

    static func validate(_ command: String) -> ValidationResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        for rule in rules {
            guard let regex = try? NSRegularExpression(
                pattern: rule.pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if regex.firstMatch(in: trimmed, range: range) != nil {
                return .blocked(reason: rule.reason)
            }
        }
        return .ok
    }
}
