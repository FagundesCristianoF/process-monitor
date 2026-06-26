import Foundation

struct AppPickerSelection {
    let path: String
    let suggestedName: String
    let patternCandidate: String

    init(url: URL) {
        self.path = url.path
        let appFileName = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        let bundleName = bundle?.infoDictionary?["CFBundleName"] as? String
            ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
        self.suggestedName = bundleName ?? appFileName
        self.patternCandidate = "\(appFileName).app"
    }

    func mergedPatterns(into existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return patternCandidate }
        if trimmed.contains(patternCandidate) { return existing }
        return "\(existing), \(patternCandidate)"
    }
}
