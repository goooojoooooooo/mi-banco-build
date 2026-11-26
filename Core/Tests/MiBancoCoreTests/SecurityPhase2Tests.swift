import Foundation
import Testing
@testable import MiBancoCore

/// Pruebas de las reglas puras de Seguridad Fase 2 (SEC-06, SEC-07, SEC-08, SEC-11, SEC-13).
@Suite struct SecurityPhase2Tests {

    // MARK: - SEC-08 · Política de bloqueo sin código ni Face ID

    @Test func lockPolicyEvaluatesAuthWhenAvailable() {
        let decision = LockAuthPolicy.decision(canEvaluateDeviceAuth: true)
        #expect(decision == .evaluateDeviceAuth)
        #expect(LockAuthPolicy.screenMode(for: decision) == .authenticate)
        #expect(LockAuthPolicy.allowsSilentUnlock(canEvaluateDeviceAuth: true) == false)
    }

    @Test func lockPolicyBlocksWithoutSilentUnlockWhenNoPasscode() {
        let decision = LockAuthPolicy.decision(canEvaluateDeviceAuth: false)
        #expect(decision == .requirePasscodeSetup)
        #expect(LockAuthPolicy.screenMode(for: decision) == .noPasscode)
        #expect(LockAuthPolicy.allowsSilentUnlock(canEvaluateDeviceAuth: false) == false)
    }

    @Test func lockPolicyNoPasscodeCopyMatchesSpecExactly() {
        #expect(
            LockAuthPolicy.noPasscodeMessage
                == "Para proteger Onyx, pon un código en el iPhone (Ajustes > Face ID y código)"
        )
        #expect(LockAuthPolicy.disableLockButtonTitle == "Desactivar bloqueo de Onyx")
    }

    @Test func shellStateDisablingLockConsciouslyOnlyUnlocksOnExplicitUnlockAndDoesNotRelock() {
        var shell = ShellState(lockApplies: true, relocksOnBackground: true)
        #expect(shell.showsLock)
        #expect(!shell.homeTakesTouches)
        #expect(shell.hidesHomeFromVoiceOver)

        // Cambiar el ajuste por sí solo nunca quita el bloqueo mientras sigue delante.
        shell.apply(.lockSettingChanged(lockApplies: false, relocksOnBackground: false))
        #expect(shell.showsLock)
        #expect(!shell.homeTakesTouches)

        // Solo al pulsar explícitamente la salida se desbloquea y queda desactivado.
        shell.apply(.unlockSucceeded)
        #expect(!shell.showsLock)
        #expect(!shell.lockApplies)
        #expect(!shell.relocksOnBackground)

        // Al pasar por segundo plano, la tapa opaca cubre igual pero no vuelve a bloquear al volver.
        shell.apply(.scene(.background))
        #expect(shell.showsCover)
        #expect(!shell.showsLock)
        shell.apply(.scene(.active))
        #expect(!shell.showsLock)
        #expect(!shell.showsCover)
    }

    // MARK: - SEC-06 y SEC-13 · Transición del ojo (avisos entregados y voz del resumen)

    @Test func closingEyeRemovesSensitiveNotificationsAndStopsSpeech() {
        let effects = PrivateModeTransitionEffects.evaluate(wasHidden: false, isHidden: true)
        #expect(effects.removeDeliveredSensitiveAlerts == true)
        #expect(effects.stopBriefingSpeech == true)
    }

    @Test func openingEyeOrUnchangedStateDoesNotTriggerClosingEffects() {
        let opened = PrivateModeTransitionEffects.evaluate(wasHidden: true, isHidden: false)
        #expect(opened.removeDeliveredSensitiveAlerts == false)
        #expect(opened.stopBriefingSpeech == false)

        let stayedClosed = PrivateModeTransitionEffects.evaluate(wasHidden: true, isHidden: true)
        #expect(stayedClosed.removeDeliveredSensitiveAlerts == false)
        #expect(stayedClosed.stopBriefingSpeech == false)

        let stayedOpen = PrivateModeTransitionEffects.evaluate(wasHidden: false, isHidden: false)
        #expect(stayedOpen.removeDeliveredSensitiveAlerts == false)
        #expect(stayedOpen.stopBriefingSpeech == false)
    }

    // MARK: - SEC-07 · Política por defecto de logos

    @Test func logoDownloadsRemainOptInByDefault() {
        #expect(LogoCachePolicy.defaultDownloadsEnabled == false)
    }

    // MARK: - SEC-11 · Puerta de onOpenURL sin conexión pendiente y mensajes de CSVLimitErro

    @Test func externalBankCallbackIgnoredWithoutPendingConnection() throws {
        let callbackURL = try #require(URL(string: "mibanco://cb?code=abc&state=xyz"))
        let otherURL = try #require(URL(string: "mibanco://otra?code=abc"))
        let webURL = try #require(URL(string: "https://example.com/cb?code=abc"))

        #expect(shouldHandleIncomingBankCallback(callbackURL, pending: .none) == false)
        #expect(shouldHandleIncomingBankCallback(callbackURL, pending: .valid(.rev)) == true)
        #expect(shouldHandleIncomingBankCallback(callbackURL, pending: .expired(.ima)) == true)

        #expect(shouldHandleIncomingBankCallback(otherURL, pending: .valid(.rev)) == false)
        #expect(shouldHandleIncomingBankCallback(webURL, pending: .valid(.rev)) == false)
        #expect(shouldHandleIncomingBankCallback(otherURL, pending: .none) == false)
    }

    @Test func csvLimitErrorMessagesCoverEveryCaseInSpanish() {
        let rowsMsg = csvLimitErrorMessage(.tooManyRows(limit: CSVTable.maxRows))
        let colsMsg = csvLimitErrorMessage(.tooManyColumns(limit: CSVTable.maxColumns))
        let cellMsg = csvLimitErrorMessage(.cellTooLong(limit: CSVTable.maxCellLength))

        #expect(!rowsMsg.isEmpty)
        #expect(!colsMsg.isEmpty)
        #expect(!cellMsg.isEmpty)
        #expect(rowsMsg.localizedCaseInsensitiveContains("filas"))
        #expect(colsMsg.localizedCaseInsensitiveContains("columnas"))
        #expect(cellMsg.localizedCaseInsensitiveContains("campos"))
    }

    @Test func readFileCappedStopsAtLimitPlusOneForStatements() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sec11-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let limit = 1_024
        let exactURL = tmpDir.appendingPathComponent("exact.csv")
        let overURL = tmpDir.appendingPathComponent("over.csv")
        try Data(repeating: 0x41, count: limit).write(to: exactURL)
        try Data(repeating: 0x42, count: limit * 4).write(to: overURL)

        let exactData = try readFileCapped(exactURL, limit: limit)
        #expect(exactData.count == limit)

        let overData = try readFileCapped(overURL, limit: limit)
        #expect(overData.count == limit + 1)
    }
}
