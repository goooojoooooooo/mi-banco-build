public enum BankID: String, Codable, CaseIterable, Sendable {
    case rev, ima, tr

    public var displayName: String {
        switch self {
        case .rev: "Revolut"
        case .ima: "imagin"
        case .tr: "Trade Republic"
        }
    }

    public var hexColor: String {
        switch self {
        case .rev: "#E6E3F0"
        case .ima: "#2EC4B6"
        case .tr: "#E9D8A6"
        }
    }
}
