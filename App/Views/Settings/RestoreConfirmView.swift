import SwiftUI
import MiBancoCore

/// Hoja de restaurar una copia: dice qué se sustituye, que lo de ahora se guarda antes, y pide deslizar.
/// El control se transforma en ✓ trazado; luego la hoja se cierra (`finished`) y Inicio se vuelve a montar.
/// Si algo falla, el control vuelve a su sitio y se explica sin tocar los datos.
struct RestoreConfirmView: View {
    let preview: RestorePreview
    /// Restaura de verdad (`LedgerModel.restore`); lanza si no se pudo.
    let restore: () throws -> Void
    let finished: () -> Void

    /// `stuck`: los datos YA cambiaron en el disco y no se pudo terminar (R35): solo texto y la salida, sin volver a ofrecer deslizar
    /// (un segundo deslizamiento copiaría lo restaurado encima de la copia de seguridad).
    private enum Phase: Equatable { case asking, restored, failed(String), stuck(String) }

    @State private var phase: Phase = .asking
    @State private var attempt = 0
    @State private var doneTick = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(preview.isPrevious ? "Volver a lo de antes" : "Restaurar una copia")
                .titan(.sheetTitle)
                .foregroundStyle(Theme.label)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)
            Text(summary)
                .titan(.body)
                .foregroundStyle(Theme.label)
            Text("Antes de cambiarlo, lo que hay ahora se guarda como copia en este iPhone y podrás volver a ello desde Copia de seguridad. Esa copia se sustituye cada vez que restauras.")
                .titan(.callout)
                .foregroundStyle(Theme.label2)
            if preview.file.droppedPortfolioEntries > 0 {
                Text(preview.file.portfolio == nil
                     ? "La parte de inversiones de esta copia no se pudo leer; se conservará tu cartera actual."
                     : "Algunas entradas de inversiones de esta copia no se pudieron leer; podrás volver a importar tu extracto.")
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch phase {
            case .restored:
                Text("Copia restaurada")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            case .failed(let message), .stuck(let message):
                Text(message)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity)
            case .asking:
                EmptyView()
            }
            if !isStuck {
                SlideToConfirm(title: preview.isPrevious ? "Desliza para volver" : "Desliza para restaurar", systemImage: "arrow.counterclockwise", tint: Theme.label,
                               action: run)
                    .id(attempt)
                    // R40: al pasar a «No se pudo terminar…» el control sale con la animación normal de la hoja (ninguna con
                    // «Reducir movimiento»).
                    .transition(reduceMotion ? .identity : .opacity)
                    .accessibilityIdentifier("restore-slide")
                    .allowsHitTesting(phase != .restored)
            }
            if phase != .restored {
                Button { dismiss() } label: {
                    // R40: tras «No se pudo terminar…» los datos YA cambiaron: la salida se llama «Cerrar», no «Cancelar».
                    Text(isStuck ? "Cerrar" : "Cancelar")
                        .titan(.option)
                        .foregroundStyle(Theme.label2)
                        // La hoja a media altura se dibuja escalada (0,9636 en iOS 26): 48 pt de diseño dejan más de 44 pt en pantalla.
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("restore-cancel")
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas.ignoresSafeArea())
        .animation(reduceMotion ? (isStuck ? nil : .easeOut(duration: 0.2)) : Theme.Motion.morph, value: phase)
        .sensoryFeedback(.success, trigger: doneTick)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(phase == .restored)
        // Segunda línea de defensa (la primera: RootView cierra la hoja): fuera de primer plano, la hoja es negra.
        .overlay {
            if scenePhase != .active {
                Theme.canvas.ignoresSafeArea().accessibilityHidden(true)
            }
        }
    }

    private var isStuck: Bool {
        if case .stuck = phase { return true }
        return false
    }

    /// "Esto cambia todo lo que hay ahora (182 movimientos) por la copia del 19 nov 2026 (175 movimientos)."
    private var summary: String {
        let date = BackupSection.dayText(preview.file.exportedAt)
        let what = preview.isPrevious ? "los datos que tenías el \(date)" : "la copia del \(date)"
        return "Esto cambia todo lo que hay ahora (\(count(preview.currentCount))) por \(what) (\(count(preview.file.ledger.movements.count)))."
    }

    private func count(_ n: Int) -> String { n == 1 ? "1 movimiento" : "\(n) movimientos" }

    private func run() {
        do {
            try restore()
            doneTick += 1
            phase = .restored
            AccessibilityNotification.Announcement("Copia restaurada").post()
            Task {
                // Tiempo para leer «Copia restaurada» (y para que una prueba lenta lo vea) antes de cerrar la hoja.
                try? await Task.sleep(for: .milliseconds(1_600))
                finished()
            }
        } catch RestoreError.safetyCopyFailed {
            fail("No se pudo guardar la copia de lo que hay ahora, así que no se ha restaurado nada.")
        } catch RestoreError.reloadFailed {
            // Lo escrito ya está en el disco: no se puede decir que los datos no cambiaron, y no se vuelve a ofrecer deslizar.
            phase = .stuck("No se pudo terminar. Cierra la app y vuelve a abrirla.")
        } catch {
            fail("No se pudo restaurar. Tus datos no han cambiado.")
        }
    }

    /// El control ya se había recogido en un círculo: se recrea para que vuelva a estar listo.
    private func fail(_ message: String) {
        phase = .failed(message)
        attempt += 1
    }
}
