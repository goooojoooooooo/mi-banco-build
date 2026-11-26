import Foundation

/// En qué punto del trámite de conexión está UN banco, tal como lo cuenta el conector de verdad (`ConnectPhase`).
public enum BankConnectStage: Equatable, Sendable {
    /// Nada en marcha para este banco (en reposo, cancelado antes de abrir la web, o el trámite es de otro banco).
    case none
    /// Paso en curso: 0 = Verificar (abriendo), 1 = Conectar (esperando al banco), 2 = Importar (terminando y, si ya
    /// corría al conectar, la primera carga de movimientos).
    case step(Int)
    /// Conectado de verdad (y, si se seguía un porcentaje, la primera carga ya no está en marcha).
    case connected
    /// El trámite falló: el mensaje del conector, tal cual.
    case failed(String)
    /// «¿Ya lo has aprobado…?»: la espera se cortó (cancelada o demasiado tiempo fuera de la app).
    case needsResume
    /// Hay que elegir el banco en la lista de Enable Banking.
    case chooseASPSP([EBASPSP])

    /// Los nombres de los tres pasos (maqueta «Conectando tu banco»).
    public static let steps = ["Verificar", "Conectar", "Importar"]

    /// La fase REAL del conector traducida para la pantalla de `bank`.
    /// - `syncing`: la carga de movimientos de ese banco está en marcha.
    /// - `tracking`: esta pantalla sigue un porcentaje en marcha. Solo entonces una carga que ya corría al conectar
    ///   cuenta dentro del tercer paso (y el éxito espera a que termine).
    public static func of(_ phase: ConnectPhase, bank: BankID, syncing: Bool, tracking: Bool) -> BankConnectStage {
        switch phase {
        case .opening(let b) where b == bank: return .step(0)
        case .waitingForBank(let b) where b == bank: return .step(1)
        case .finishing(let b) where b == bank: return .step(2)
        case .connected(let b) where b == bank: return tracking && syncing ? .step(2) : .connected
        case .failed(let b, let message) where b == bank: return .failed(message)
        case .needsResume(let b) where b == bank: return .needsResume
        case .chooseASPSP(let b, let list) where b == bank: return .chooseASPSP(list)
        // Sin `default`: una fase nueva de `ConnectPhase` no compila hasta decidir aquí qué enseña.
        case .idle, .opening, .waitingForBank, .finishing, .connected, .failed, .needsResume, .chooseASPSP:
            return .none
        }
    }

    /// Lo que se está haciendo, bajo los pasos (los textos de siempre); `nil` fuera de un paso.
    public func caption(bankName: String) -> String? {
        guard case .step(let index) = self else { return nil }
        return index >= 2 ? "Terminando con \(bankName)…" : "Esperando a \(bankName)…"
    }

    /// Se puede cancelar la espera: abriendo o esperando al banco.
    public var canCancel: Bool { self == .step(0) || self == .step(1) }
}

/// El porcentaje del trámite de conexión visto en UNA pantalla, movido solo por la fase real (`BankConnectStage`):
/// - un paso nuevo del mismo trámite avanza el porcentaje (nunca hacia atrás); un trámite nuevo empieza en 0;
/// - 100 y el éxito solo con `.connected` (el trabajo acabó de verdad) y solo si se estaba siguiendo un trámite;
/// - un fallo congela la cifra que se veía; cancelar, «¿Ya lo has aprobado…?» o elegir banco quitan el porcentaje.
/// Valor puro: la pantalla le pasa la etapa y los segundos del paso en curso (ya divididos por la cámara lenta).
public struct BankConnectProgress: Equatable, Sendable {
    /// El porcentaje seguido (`nil` = ninguno).
    public private(set) var percent: StepPercent?
    /// El trámite acabó bien de verdad (hasta «Listo» o «Ver movimientos»).
    public private(set) var success = false
    /// El remate a la vista: el porcentaje corre a 100, el tercer paso se marca y la línea dice «Todo listo». Solo
    /// existe tras un éxito REAL (`.connected` de un trámite seguido); dura `finishHold` y entonces la pantalla llama a
    /// `revealSuccess()`. Un fallo o cancelar nunca lo enseñan.
    public private(set) var finishing = false

    /// Lo que dura el remate (segundos del kit): la cifra corre a 100 (0,25 s) mientras el último nodo se rellena y
    /// dibuja su ✓ (0,3 s), y una pausa de 0,18 s (maqueta y ojo de diseño 14.1).
    public static let finishHold = 0.48
    /// Lo que tardan en irse los pasos, el saldo y el estado antes de que salte el ✓ de «conectado» (14.2).
    public static let clearBeforeSuccess = 0.15
    /// La línea del remate (maqueta «Conectando tu banco», el texto tras el tercer paso).
    public static let finishCaption = "Todo listo"

    public init() {}

    /// Hay un porcentaje en marcha.
    public var isTracking: Bool { percent?.isRunning == true }

    /// «Banco, conectado» a la vista: el éxito, una vez pasado el remate.
    public var showsSuccess: Bool { success && !finishing }

    /// La etapa de `bank` con lo que esta pantalla está siguiendo.
    public func stage(of phase: ConnectPhase, bank: BankID, syncing: Bool) -> BankConnectStage {
        BankConnectStage.of(phase, bank: bank, syncing: syncing, tracking: isTracking)
    }

    public enum Effect: Equatable, Sendable {
        case none
        /// Empezó un paso: la pantalla apunta su hora de inicio.
        case stepStarted
        /// Conectado de verdad: 100 y «conectado».
        case succeeded
        /// Congelado.
        case failed
    }

    /// La etapa cambió. `elapsed`: segundos que lleva el paso en curso; `reduce`: Reducir movimiento (la cifra no
    /// cuenta y se ve el suelo del paso). Con los dos se congela, o se remata, justo la cifra que se DIBUJABA.
    @discardableResult
    public mutating func apply(_ stage: BankConnectStage, elapsed: Double, reduce: Bool = false) -> Effect {
        switch stage {
        case .step(let index):
            if let current = percent, current.isRunning, index >= current.step {
                guard index > current.step else { return .none }
                percent?.enter(step: index)
            } else {
                // Un trámite nuevo (o uno que vuelve a empezar): el porcentaje arranca de cero en su paso.
                var fresh = StepPercent()
                fresh.enter(step: index)
                percent = fresh
                success = false
                finishing = false
            }
            return .stepStarted
        case .connected:
            guard isTracking, let current = percent else { return .none }
            percent?.succeed(shown: current.drawn(elapsed: elapsed, reduce: reduce))
            success = true
            finishing = true
            return .succeeded
        case .failed:
            guard let current = percent, current.isRunning else { return .none }
            percent?.fail(shown: current.drawn(elapsed: elapsed, reduce: reduce))
            return .failed
        case .none, .needsResume, .chooseASPSP:
            // No queda trámite que enseñar (el éxito sí se queda hasta «Listo»).
            if percent?.outcome != .succeeded { percent = nil }
            return .none
        }
    }

    /// Pasado el remate: «Banco, conectado». Solo tras un éxito real.
    public mutating func revealSuccess() {
        guard finishing, success, percent?.outcome == .succeeded else { return }
        finishing = false
    }

    /// «Listo» o «Ver movimientos».
    public mutating func dismissSuccess() {
        success = false
        finishing = false
        percent = nil
    }

    /// Lo que dice la línea bajo los pasos: «Todo listo» durante el remate; si no, el texto del paso en curso.
    public func caption(for stage: BankConnectStage, bankName: String) -> String? {
        finishing ? Self.finishCaption : stage.caption(bankName: bankName)
    }

    /// El porcentaje que se dibuja con esta etapa: el seguido o, en el primer instante de un paso (antes de `apply`), uno
    /// recién empezado en ese paso. Nada con «¿Ya lo has aprobado…?» ni con la lista de bancos.
    public func shown(for stage: BankConnectStage) -> StepPercent? {
        switch stage {
        case .needsResume, .chooseASPSP:
            return nil
        default:
            if let percent { return percent }
            if case .step(let index) = stage {
                var fresh = StepPercent()
                fresh.enter(step: index)
                return fresh
            }
            return nil
        }
    }

    /// Se ofrecen «Conectar» / «Renovar» / «Actualizar ahora»: no hay pasos, ni fallo, ni espera cortada, ni lista.
    public func showsStartActions(for stage: BankConnectStage) -> Bool {
        guard shown(for: stage) == nil else { return false }
        switch stage {
        case .none, .connected: return true
        default: return false
        }
    }
}
