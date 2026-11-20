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

    private enum Phase: Equatable { case asking, restored, failed(String) }

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
            Spacer(minLength: 8)
            switch phase {
            case .restored:
                Text("Copia restaurada")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            case .failed(let message):
                Text(message)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity)
            case .asking:
                EmptyView()
            }
            SlideToConfirm(title: preview.isPrevious ? "Desliza para volver" : "Desliza para restaurar", systemImage: "arrow.counterclockwise", tint: Theme.label,
                           action: run)
                .id(attempt)
                .accessibilityIdentifier("restore-slide")
                .allowsHitTesting(phase != .restored)
            if phase != .restored {
                Button("Cancelar") { dismiss() }
                    .titan(.option)
                    .foregroundStyle(Theme.label2)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("restore-cancel")
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas.ignoresSafeArea())
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.morph, value: phase)
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
                try? await Task.sleep(for: .milliseconds(900))
                finished()
            }
        } catch RestoreError.safetyCopyFailed {
            fail("No se pudo guardar la copia de lo que hay ahora, así que no se ha restaurado nada.")
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
