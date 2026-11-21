import MiBancoCore
import SwiftUI
import UniformTypeIdentifiers

/// Pantalla de un banco dentro de Ajustes › Bancos (Plan 2, tareas 11 y 12; R20, R41, R42, R43).
/// Permite conectar o renovar con Enable Banking, actualizar ahora, importar extractos CSV o desconectar.
struct BankLinkView: View {
    let model: LedgerModel
    var portfolio: PortfolioModel? = nil
    let bank: BankID

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationGate) private var gate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var importingStatement = false
    @State private var importPreview: ImportPreview?
    @State private var importError: String?
    @State private var confirmingDisconnect = false
    @State private var confirmingForgetAll = false
    @State private var errorTick = 0

    private static let maxStatementBytes = 10 * 1024 * 1024

    private var connector: BankConnector { BankConnector.shared }
    private var syncStatus: BankSyncStatus { BankSyncStatus.shared }

    private var link: BankLinkInfo? {
        model.state.links[bank]
    }

    private var canConnect: Bool {
        connector.canConnect(bank)
    }

    private var statusLines: BankStatusLines {
        if syncStatus.running.contains(bank) {
            return BankStatusLines(
                primary: "Conectado · actualizando…",
                secondary: model.snapshot.bankLines[bank]?.secondary,
                action: nil
            )
        }
        return bankStatusLines(
            bank: bank,
            link: link,
            estimated: model.snapshot.balances[bank]?.estimated,
            canConnect: canConnect,
            now: Date(),
            calendar: DateText.madridCalendar
        )
    }

    private var isWaitingOnThisBank: Bool {
        switch connector.phase {
        case .opening(let b), .waitingForBank(let b), .finishing(let b):
            b == bank
        default:
            false
        }
    }

    private var canCancelWaiting: Bool {
        switch connector.phase {
        case .opening(let b), .waitingForBank(let b):
            b == bank
        default:
            false
        }
    }

    private var showsForgetEverything: Bool {
        BankingCredentials.isReady || !model.state.links.isEmpty
    }

    private var needsResumeForThisBank: Bool {
        if case .needsResume(let b) = connector.phase { return b == bank }
        return false
    }

    private var failedMessageForThisBank: String? {
        if case let .failed(b, msg) = connector.phase, b == bank { return msg }
        return nil
    }

    private var aspspChoicesForThisBank: [EBASPSP]? {
        if case let .chooseASPSP(b, list) = connector.phase, b == bank { return list }
        return nil
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        BankLogo(bank: bank, size: 36)
                        Text(bank.displayName)
                            .titan(.cardTitle)
                            .foregroundStyle(Theme.label)
                    }

                    Text(statusLines.primary)
                        .titan(.sheetTitle)
                        .foregroundStyle(Theme.label)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    if let secondary = statusLines.secondary {
                        Text(secondary)
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if bank == .tr && !canConnect {
                        Text("Trade Republic no se puede conectar gratis. Exporta su extracto en su app (Perfil › Extractos › Exportar transacciones) e impórtalo aquí.")
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Theme.grouped)

                phaseRows
                actionRows
            }

            if let importError {
                Section {
                    Text(importError)
                        .titan(.meta)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Theme.grouped)
                }
            }

            if canConnect || link != nil {
                Section {
                    Text("Primera actualización: últimos 12 meses (lo que dé el banco)")
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label2)
                        .listRowBackground(Theme.grouped)
                } header: {
                    SettingsHeader("Historial")
                }
            }

            if link != nil || showsForgetEverything {
                Section {
                    if link != nil {
                        Button(role: .destructive) {
                            guard gate?.canPresent == true, scenePhase == .active else { return }
                            confirmingDisconnect = true
                        } label: {
                            Text("Desconectar")
                                .titan(.option)
                                .foregroundStyle(Theme.warning)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.grouped)
                        .listRowSeparatorTint(Theme.separator)
                    }

                    if showsForgetEverything {
                        Button(role: .destructive) {
                            guard gate?.canPresent == true, scenePhase == .active else { return }
                            confirmingForgetAll = true
                        } label: {
                            Text("Olvidar clave y conexiones")
                                .titan(.option)
                                .foregroundStyle(Theme.warning)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.grouped)
                        .listRowSeparatorTint(Theme.separator)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(bank.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $importPreview) { preview in
            ImportStatementView(model: model, portfolio: portfolio, bank: bank, preview: preview) {
                importPreview = nil
            }
        }
        .fileImporter(
            isPresented: $importingStatement,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data]
        ) { result in
            handleStatementFile(result)
        }
        .confirmationDialog(
            "Desconectar \(bank.displayName)",
            isPresented: $confirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button("Desconectar", role: .destructive) {
                Task { await connector.disconnect(bank) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se dejan de leer sus movimientos. Lo que ya tienes se queda.")
        }
        .confirmationDialog(
            "Olvidar clave y conexiones",
            isPresented: $confirmingForgetAll,
            titleVisibility: .visible
        ) {
            Button("Olvidar clave y conexiones", role: .destructive) {
                Task {
                    await BankingCredentials.forgetEverything()
                    model.reload()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borran la clave de Enable Banking y las sesiones de este iPhone. Tus movimientos se quedan.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                importingStatement = false
                confirmingDisconnect = false
                confirmingForgetAll = false
            }
        }
        .onChange(of: gate?.isLocked) { _, locked in
            if locked == true {
                importingStatement = false
                confirmingDisconnect = false
                confirmingForgetAll = false
            }
        }
        .onChange(of: importingStatement) { _, on in
            if on && (gate?.canPresent != true || scenePhase != .active) { importingStatement = false }
        }
        .onChange(of: confirmingDisconnect) { _, on in
            if on && (gate?.canPresent != true || scenePhase != .active) { confirmingDisconnect = false }
        }
        .onChange(of: confirmingForgetAll) { _, on in
            if on && (gate?.canPresent != true || scenePhase != .active) { confirmingForgetAll = false }
        }
        .sensoryFeedback(Haptics.error, trigger: errorTick)
        #if DEBUG
        .onAppear {
            if DemoMode.isActive && DemoMode.opensStatementImport && importPreview == nil {
                importPreview = try? model.previewImport(DemoMode.sampleRevolutStatementData(), bank: .rev)
            }
        }
        #endif
    }

    @ViewBuilder
    private var phaseRows: some View {
        if isWaitingOnThisBank {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.label)
                    Text("Esperando a \(bank.displayName)…")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                }
                if canCancelWaiting {
                    Button {
                        connector.cancelWebSession()
                    } label: {
                        Text("Cancelar")
                            .titan(.option)
                            .foregroundStyle(Theme.label2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.raised, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("bank-cancel-wait")
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.grouped)
        } else if needsResumeForThisBank {
            VStack(alignment: .leading, spacing: 12) {
                Text("¿Ya lo has aprobado en la app de \(bank.displayName)?")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Task { await connector.resume() }
                    } label: {
                        Text("Seguir")
                            .titan(.option)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.canvas)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.label, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)

                    Button {
                        Task { await connector.connect(bank) }
                    } label: {
                        Text("Empezar de nuevo")
                            .titan(.option)
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.raised, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.grouped)
        } else if let failed = failedMessageForThisBank {
            VStack(alignment: .leading, spacing: 12) {
                Text(failed)
                    .titan(.subtitle)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await connector.connect(bank) }
                } label: {
                    Text("Empezar de nuevo")
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.canvas)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.label, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.grouped)
        } else if let list = aspspChoicesForThisBank {
            NavigationLink {
                ASPSPPickerView(bank: bank, list: list) { chosen in
                    Task { await connector.connect(bank, aspsp: chosen) }
                }
            } label: {
                Text("Elegir \(bank.displayName) en la lista")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
            }
            .listRowBackground(Theme.grouped)
        }
    }

    @ViewBuilder
    private var actionRows: some View {
        if !isWaitingOnThisBank && !needsResumeForThisBank && failedMessageForThisBank == nil {
            switch statusLines.action {
            case .connect:
                Button {
                    Task { await connector.connect(bank) }
                } label: {
                    actionCapsule("Conectar \(bank.displayName)", prominent: true)
                }
                .buttonStyle(.pressable)
                .listRowBackground(Theme.grouped)

            case .renew:
                Button {
                    Task { await connector.connect(bank) }
                } label: {
                    actionCapsule("Renovar conexión", prominent: true)
                }
                .buttonStyle(.pressable)
                .listRowBackground(Theme.grouped)

            case .refresh:
                Button {
                    Task { _ = await BankSync.shared.refresh(trigger: .manual, only: bank) }
                } label: {
                    actionCapsule("Actualizar ahora", prominent: true)
                }
                .buttonStyle(.pressable)
                .disabled(syncStatus.running.contains(bank))
                .listRowBackground(Theme.grouped)

            case .importStatement, .editBalance, nil:
                EmptyView()
            }
        }

        Button {
            guard gate?.canPresent == true, scenePhase == .active else { return }
            importError = nil
            importingStatement = true
        } label: {
            actionCapsule("Importar extracto", prominent: statusLines.action == .importStatement)
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("bank-import-statement")
        .listRowBackground(Theme.grouped)
    }

    private func actionCapsule(_ title: String, prominent: Bool) -> some View {
        Text(title)
            .titan(.option)
            .fontWeight(prominent ? .semibold : .medium)
            .foregroundStyle(prominent ? Theme.onTileSelected : Theme.label)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(prominent ? Theme.tileSelected : Theme.raised, in: Capsule())
            .contentShape(Capsule())
            .padding(.vertical, 2)
    }

    private func handleStatementFile(_ result: Result<URL, Error>) {
        guard gate?.canPresent == true, scenePhase == .active, case .success(let url) = result else { return }
        let targetBank = bank
        let generation = gate?.generation ?? 0
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Self.readStatementData(from: url)
                }.value
                guard (gate?.generation ?? 0) == generation, gate?.canPresent == true, scenePhase == .active else { return }
                let preview = try model.previewImport(data, bank: targetBank)
                importError = nil
                importPreview = preview
            } catch let error as StatementFileError {
                guard (gate?.generation ?? 0) == generation else { return }
                importError = error.message
                errorTick += 1
            } catch let error as StatementError {
                guard (gate?.generation ?? 0) == generation else { return }
                importError = Self.errorMessage(for: error, bank: targetBank)
                errorTick += 1
            } catch {
                guard (gate?.generation ?? 0) == generation else { return }
                importError = Self.errorMessage(for: .unreadable, bank: targetBank)
                errorTick += 1
            }
        }
    }

    private enum StatementFileError: Error {
        case tooLarge
        case unreadable

        var message: String {
            switch self {
            case .tooLarge:
                "Este archivo es demasiado grande (máx. 10 MB)."
            case .unreadable:
                "No reconocemos este archivo. Usa el CSV que exporta tu banco."
            }
        }
    }

    nonisolated private static func readStatementData(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw StatementFileError.unreadable
        }
        guard size <= maxStatementBytes else {
            throw StatementFileError.tooLarge
        }
        guard let data = try? Data(contentsOf: url) else { throw StatementFileError.unreadable }
        guard data.count <= maxStatementBytes else { throw StatementFileError.tooLarge }
        return data
    }

    static func errorMessage(for error: StatementError, bank: BankID) -> String {
        switch error {
        case .missingColumns(let cols):
            let first = cols.first ?? ""
            let cap = first.prefix(1).uppercased() + first.dropFirst()
            return "Este archivo no parece un extracto de \(bank.displayName). Falta la columna «\(cap)»."
        case .wrongBank(let detected):
            return "Este extracto es de \(detected.displayName). Impórtalo desde su banco."
        case .unknownFormat, .empty, .unreadable:
            return "No reconocemos este archivo. Usa el CSV que exporta tu banco."
        }
    }
}
