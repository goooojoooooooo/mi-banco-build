import Foundation
import UIKit
import MiBancoCore

/// Esquemas candidatos para abrir las apps de los bancos (SIN verificar en el iPhone real).
/// Solo se muestra el botón «Abrir <banco>» cuando `canOpen` devuelve true.
enum BankApps {
    static func url(for bank: BankID) -> URL? {
        switch bank {
        case .rev: URL(string: "revolut://")
        case .ima: URL(string: "imagin://")
        case .tr: URL(string: "traderepublic://")
        }
    }

    @MainActor
    static func canOpen(_ bank: BankID) -> Bool {
        guard let url = url(for: bank) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// "Abrir bancos: Revolut sí · imagin no · Trade Republic sí" (para la línea de Diagnóstico en Ajustes).
    @MainActor
    static var diagnosticsLine: String {
        let parts = BankID.allCases.map { "\($0.displayName) \(canOpen($0) ? "sí" : "no")" }
        return "Abrir bancos: \(parts.joined(separator: " · "))"
    }
}
