import SwiftUI
import MiBancoCore

/// C6 / C8: la tarjeta del abanico vuela hasta la cabecera de la pantalla de su banco (momento 2 del vídeo del dueño).
///
/// Va en `RootView`, por encima de las pestañas y de la pantalla del banco abierta sobre Inicio, y por debajo de la hoja
/// única y del bloqueo (otras capas). Cuando el abanico apunta un vuelo (`CardFlight.request`), la capa:
/// 1. pone `landed = false` (la cabecera del banco espera) y dibuja una copia de la tarjeta donde estaba;
/// 2. espera a que la cabecera apunte su sitio (`CardFlight.destination`) y vuela hasta él: sube, gira 25° × (0,6 +
///    0,4·D) (D = lo lejos que va, 0…1), se inclina 9° hacia atrás y se eleva 20 pt a mitad de camino; la cara de la
///    tarjeta se va antes del 34 % y la cara oscura de titanio (la de la cabecera) entra desde el 44 %: nunca se ven
///    las dos a la vez;
/// 3. al aterrizar: `landed = true` (la cabecera entra en ese instante), la petición se limpia y la copia se quita.
/// Si la cabecera no apunta su sitio a tiempo, la copia se funde donde está y la cabecera aparece igual.
/// Con Reducir movimiento no hay vuelo: la cabecera se ve en el acto. Se cancela al bloquear, al salir de primer plano
/// o si se abre la hoja única (`cancel`). La copia no lleva importes: nada que ocultar con el ojo.
struct CardFlightLayer: View {
    let flight: CardFlight
    /// Ya no se puede volar (bloqueo, fuera de primer plano, hoja abierta): se deja todo como si hubiera aterrizado.
    let blocked: Bool

    @Environment(\.motion) private var motion
    @State private var current: CardFlight.Request?
    @State private var target: CGRect?
    @State private var progress: CGFloat = 0
    @State private var fading = false
    @State private var run = 0

    /// El muelle del vuelo: 0,62 s con un rebote de 0,16.
    static let spring = SpringSpec(response: 0.62, dampingFraction: 0.84)
    /// Cuánto espera a que la cabecera apunte su sitio antes de rendirse (s, a nivel Equilibrado).
    static let destinationPatience = 0.6

    var body: some View {
        ZStack {
            if let current, let target {
                CardFlyer(bank: current.bank, card: current.card)
                    .frame(width: current.source.width, height: current.source.height)
                    .modifier(CardFlightEffect(
                        progress: progress, from: current.source, to: target, distance: Self.reach(current.source, target)))
                    .opacity(fading ? 0 : 1)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: flight.request) { _, request in
            guard let request, current == nil else { return }
            start(request)
        }
        .onChange(of: blocked) { _, now in if now { cancel() } }
        .task(id: run) { await fly() }
    }

    /// Lo lejos que va (0…1): la distancia entre los centros respecto al alto de la pantalla.
    static func reach(_ from: CGRect, _ to: CGRect) -> CGFloat {
        let d = hypot(to.midX - from.midX, to.midY - from.midY)
        return min(1, d / 800)
    }

    private func start(_ request: CardFlight.Request) {
        guard !motion.reduce, !blocked, request.source != .zero else {
            // Sin vuelo: la cabecera no espera. La petición se limpia un momento después (quien abre el banco aún la
            // lee para saberse llamado desde el abanico) y no queda colgada para la próxima vez.
            flight.landed = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if flight.request == request { flight.request = nil }
            }
            return
        }
        flight.landed = false
        current = request
        target = nil
        progress = 0
        fading = false
        run += 1
    }

    private func fly() async {
        guard current != nil else { return }
        // Espera a que la cabecera del banco esté puesta y apunte su sitio.
        let deadline = Date().addingTimeInterval(motion.seconds(Self.destinationPatience))
        while flight.destination == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled { return }
        }
        guard let destination = flight.destination else {
            // Sin cabecera a la que ir: la copia se funde donde está y la cabecera (si llega) aparece igual.
            target = current?.source
            withAnimation(motion.fade) { fading = true }
            try? await Task.sleep(for: .seconds(motion.fadeDuration))
            land()
            return
        }
        target = destination
        let spec = MotionMath.scaled(Self.spring, level: motion.level, timeMultiplier: motion.timeMultiplier)
        withAnimation(.spring(response: spec.response, dampingFraction: spec.dampingFraction)) { progress = 1 }
        // Aterriza cuando el muelle se ha posado (una pausa que lee `\.motion`; la `completion` de una animación puede
        // llegar al instante con la app cargada).
        try? await Task.sleep(for: .seconds(spec.response))
        guard !Task.isCancelled else { return }
        land()
    }

    private func land() {
        flight.landed = true
        flight.request = nil
        current = nil
        target = nil
        #if DEBUG
        LaunchProbe.shared.cardLandings += 1
        #endif
    }

    private func cancel() {
        guard current != nil || flight.request != nil else { return }
        run += 1
        flight.landed = true
        flight.request = nil
        current = nil
        target = nil
    }
}

/// La copia que vuela: la cara de la tarjeta (material del banco, logo y nombre; sin importes) y, detrás, la cara oscura
/// de titanio en diagonal que es el fondo de la cabecera del banco. Cuál se ve lo decide `CardFlightEffect`.
private struct CardFlyer: View {
    let bank: BankID
    let card: AccountCard

    @Environment(\.cardFlightFace) private var face

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        ZStack {
            ZStack(alignment: .topLeading) {
                CardSurface(material: card.material, moves: false)
                HStack(spacing: 8) {
                    BankLogo(bank: bank, size: 22)
                    Text(bank.displayName)
                        .titan(.cardTitle)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                }
                .padding(16)
            }
            .opacity(face.front)
            shape
                .fill(LinearGradient(
                    colors: [Color(white: 0.16), Color(white: 0.07), Color(white: 0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(face.back)
        }
        .clipShape(shape)
    }
}

/// Qué cara de la copia se ve (0…1 cada una). Nunca las dos a la vez: la de delante se va antes del 34 % del vuelo y la
/// de detrás entra desde el 44 %.
struct CardFlightFace: Equatable {
    var front: Double = 1
    var back: Double = 0

    static func at(_ k: CGFloat) -> CardFlightFace {
        let front = max(0, min(1, 1 - Double(k) / 0.34))
        let back = max(0, min(1, (Double(k) - 0.44) / 0.3))
        return CardFlightFace(front: front, back: back)
    }
}

extension EnvironmentValues {
    @Entry var cardFlightFace = CardFlightFace()
}

/// El vuelo de la copia, solo con transformaciones: va del marco de origen al de la cabecera (posición y escala en los
/// dos ejes), sube 20 pt a mitad de camino, gira en el plano y se inclina hacia atrás; y elige la cara que se ve.
private struct CardFlightEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGRect
    let to: CGRect
    let distance: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let k = min(max(progress, 0), 1.15)
        let arc = sin(.pi * min(k, 1))
        let x = from.midX + (to.midX - from.midX) * k
        let y = from.midY + (to.midY - from.midY) * k - 20 * arc
        let sx = 1 + (to.width / max(from.width, 1) - 1) * k
        let sy = 1 + (to.height / max(from.height, 1) - 1) * k
        let spin = 25 * (0.6 + 0.4 * distance) * arc
        content
            .environment(\.cardFlightFace, CardFlightFace.at(k))
            .rotation3DEffect(.degrees(9 * arc), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotationEffect(.degrees(spin))
            .scaleEffect(x: sx, y: sy)
            .position(x: x, y: y)
    }
}
