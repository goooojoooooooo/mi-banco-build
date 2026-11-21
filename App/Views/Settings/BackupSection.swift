import SwiftUI
import MiBancoCore

/// Grupo "Copia de seguridad" de Ajustes. Cada botón de exportar se transforma: icono → indicador → ✓ trazado.
/// Con Reducir movimiento, fundidos. Los identificadores son para las pruebas de toque.
struct BackupSection: View {
    let model: LedgerModel
    let portfolio: PortfolioModel
    let present: (RootSheet) -> Void
    let importBackup: () -> Void

    private enum Kind { case backup, csv }
    private enum Phase: Equatable { case idle, working, done }

    @State private var phase: [Int: Phase] = [:]
    @State private var failed = false
    /// La copia previa a la última restauración, si existe: se relee al aparecer y tras cada restauración.
    @State private var previous: RestorePreview?
    @State private var doneTick = 0
    @State private var errorTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.presentationGate) private var gate

    static let scrollID = "copia-seguridad"

    var body: some View {
        Section {
            exportRow(.backup, title: "Guardar copia completa", systemImage: "externaldrive", id: "backup-save")
            exportRow(.csv, title: "Exportar movimientos (CSV)", systemImage: "tablecells", id: "backup-csv")
                .id(Self.scrollID)
            Button(action: importBackup) {
                OptionLabel(title: "Restaurar una copia…", detail: "Elige un fichero de copia", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("backup-restore")
            .listRowBackground(Theme.grouped)
            .listRowSeparatorTint(Theme.separator)
            if let previous {
                Button {
                    // Se vuelve a leer al tocar: así el recuento de "lo de ahora" es el de ese momento.
                    // Si la copia desapareció desde que se pintó la fila, la fila se actualiza en vez de no hacer nada.
                    if let fresh = model.previousPreview(portfolioSafetyCopy: portfolio.loadSafetyCopy()) {
                        present(.restore(fresh))
                    } else {
                        self.previous = nil
                    }
                } label: {
                    OptionLabel(title: "Volver a lo de antes de restaurar", detail: "Datos del \(Self.dayText(previous.file.exportedAt))",
                                systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backup-previous")
                .listRowBackground(Theme.grouped)
                .listRowSeparatorTint(Theme.separator)
            }
            if failed {
                Text("No se pudo preparar el fichero. Inténtalo de nuevo.")
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity)
                    .listRowBackground(Theme.grouped)
            }
        } header: {
            SettingsHeader("Copia de seguridad")
        } footer: {
            SettingsFooter("La copia lleva todos tus movimientos, saldos y notas. Guárdala en un sitio tuyo: quien la tenga puede leerla.")
        }
        .task(id: model.restoreCount) { previous = model.previousPreview(portfolioSafetyCopy: portfolio.loadSafetyCopy()) }
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: failed)
        .sensoryFeedback(.success, trigger: doneTick)
        .sensoryFeedback(.error, trigger: errorTick)
    }

    /// "19 nov 2026"
    static func dayText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: Locale(identifier: "es_ES")).day().month(.abbreviated).year()).replacing(".", with: "")
    }

    private func key(_ kind: Kind) -> Int { kind == .backup ? 0 : 1 }

    private func exportRow(_ kind: Kind, title: String, systemImage: String, id: String) -> some View {
        let state = phase[key(kind)] ?? .idle
        return Button {
            Task { await export(kind) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    switch state {
                    case .idle:
                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.iconGlyph)
                            .transition(.opacity)
                    case .working:
                        ProgressView().tint(Theme.label).transition(.opacity)
                    case .done:
                        DrawnCheck(lineWidth: 2, color: Theme.onTileSelected)
                            .frame(width: 16, height: 16)
                            .transition(.opacity)
                    }
                }
                .frame(width: 30, height: 30)
                .background(state == .done ? Theme.tileSelected : Theme.iconTile, in: .rect(cornerRadius: 8, style: .continuous))
                .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.morph, value: state)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).titan(.option).foregroundStyle(Theme.label)
                    Text(detail(state)).titan(.meta).foregroundStyle(Theme.label3)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
        .accessibilityIdentifier(id)
        .accessibilityValue(state == .working ? "Preparando" : state == .done ? "Listo" : "")
        .listRowBackground(Theme.grouped)
        .listRowSeparatorTint(Theme.separator)
    }

    private func detail(_ state: Phase) -> String {
        switch state {
        case .idle: "Se abre la hoja de compartir"
        case .working: "Preparando…"
        case .done: "Listo"
        }
    }

    private func set(_ kind: Kind, _ value: Phase) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.morph) { phase[key(kind)] = value }
    }

    private func export(_ kind: Kind) async {
        failed = false
        // Si desde este toque la app se bloquea o sale de primer plano (aunque luego se desbloquee), el resultado se descarta.
        let generation = gate?.generation
        func stale() -> Bool { gate != nil && gate?.generation != generation }
        set(kind, .working)
        let state = model.state
        let savedPortfolio = portfolio.portfolioForBackup
        let now = Date()
        let result: Result<URL, Error> = await Task.detached {
            Result {
                try kind == .backup
                    ? BackupService.exportBackup(state, portfolio: savedPortfolio, now: now)
                    : BackupService.exportCSV(state, now: now)
            }
        }.value
        switch result {
        case .success(let url):
            if stale() {
                BackupService.remove(url)
                set(kind, .idle)
                return
            }
            set(kind, .done)
            doneTick += 1
            try? await Task.sleep(for: .milliseconds(550))
            if stale() {
                BackupService.remove(url)
                set(kind, .idle)
                return
            }
            present(.share(ShareItem(url: url)))
            try? await Task.sleep(for: .milliseconds(700))
            set(kind, .idle)
        case .failure:
            errorTick += 1
            failed = true
            set(kind, .idle)
        }
    }
}
