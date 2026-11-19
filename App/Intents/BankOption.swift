import AppIntents
import MiBancoCore

enum BankOption: String, AppEnum {
    case rev, ima, tr

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Banco"
    static let caseDisplayRepresentations: [BankOption: DisplayRepresentation] = [
        .rev: "Revolut", .ima: "imagin", .tr: "Trade Republic",
    ]

    var id: BankID {
        switch self {
        case .rev: .rev
        case .ima: .ima
        case .tr: .tr
        }
    }
}
