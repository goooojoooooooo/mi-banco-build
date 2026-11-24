import Foundation
import Testing
@testable import MiBancoCore

/// El nombre visible de la app es «Onyx» en todas partes (rulings, RONDA 3/5, punto (b)). La guía de avisos le dice al
/// dueño qué app buscar en Atajos: si no coincide con el nombre bajo el icono, no la encuentra.
@Suite struct AppNameTests {
    @Test func elNombreVisibleEsOnyx() {
        #expect(appDisplayName == "Onyx")
    }

    @Test func laGuiaBuscaLaAppPorSuNombreVisible() {
        #expect(guideAppName == appDisplayName)
        for track in GuideTrack.allCases {
            let all = guideSteps(for: track)
            #expect(all.contains { $0.title == "Escribe \(appDisplayName)" && $0.tapTarget == appDisplayName
                && $0.instruction == "Escribe «\(appDisplayName)» en el buscador." }, "\(track)")
        }
    }

    @Test func ningunTextoDeLaGuiaDiceElNombreViejo() {
        for track in GuideTrack.allCases {
            for step in guideSteps(for: track) {
                let text = [step.title, step.instruction, step.tapTarget, step.place, step.help].joined(separator: " ")
                #expect(!text.localizedCaseInsensitiveContains("mi banco"), "\(track) \(step.id)")
            }
        }
    }

    @Test func losModelosConocenLaAppPorSuNombre() {
        #expect(briefingModelInstructions.contains(appDisplayName))
        #expect(assistantRoutingInstructions.contains(appDisplayName))
        #expect(!briefingModelInstructions.localizedCaseInsensitiveContains("mi banco"))
        #expect(!assistantRoutingInstructions.localizedCaseInsensitiveContains("mi banco"))
    }
}
