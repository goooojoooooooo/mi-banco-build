import SwiftUI
import MiBancoCore

/// El arranque «logo en piezas» cuando NO hay bloqueo delante (con bloqueo, las piezas se montan en la propia pantalla
/// de bloqueo: ver `LockView`). Solo en frío: `AppShellView` la monta una vez y no vuelve a hacerlo al volver de
/// segundo plano.
///
/// Sobre negro, las dos mitades de la ola llegan entre líneas de velocidad y encajan; se dibuja la loseta y aparece el
/// nombre; cruza un brillo; a los 0,78 s Inicio empieza a montarse debajo (`onAssemble`); dos bandas barren el negro y
/// la marca vuela a su ranura de la barra superior mientras el negro se aclara. Dura lo que dice `LaunchTimeline`
/// (≈ 1,34 s en Expresivo); en Sutil y con Reducir movimiento es solo un fundido.
///
/// - Un toque en cualquier sitio la salta: el guion pasa al vuelo y acaba en una décima.
/// - Nunca retrasa Inicio: desde que la marca echa a volar la capa deja pasar los toques, y al acabar se quita
///   (`onFinish`); con ella se van su `TimelineView` y sus lienzos.
/// - No tiene importes ni nada que leer: VoiceOver no la ve.
/// - Va DEBAJO del sitio del bloqueo y nunca se monta con el bloqueo puesto (lo decide `AppShellView`).
struct LaunchSequence: View {
    /// Inicio empieza a montarse debajo (se llama una sola vez).
    let onAssemble: () -> Void
    /// La capa ya no pinta nada: se puede quitar.
    let onFinish: () -> Void

    @Environment(\.motion) private var motion
    @Environment(\.launchAnchor) private var anchor
    @State private var start = LaunchClock.startDate()
    @State private var skippedAt: Date?
    /// La capa ya deja pasar los toques a Inicio: desde que la marca echa a volar, o desde el toque que la salta.
    @State private var passesTouches = false
    @State private var assembled = false
    @State private var clicks = 0
    /// El guion ha terminado: el reloj se para aquí mismo (además de quitarse la capa).
    @State private var finished = false
    /// El ancho del nombre que vuela, para que aterrice del tamaño del de la barra.
    @State private var nameWidth: CGFloat = 0

    private static let markSize: CGFloat = 96
    private static let nameSize: CGFloat = 15

    var body: some View {
        let timeline = LaunchTimeline(motion)
        GeometryReader { proxy in
            LaunchStage(
                timeline: timeline, act: .launch, start: start, skippedAt: skippedAt, finished: finished,
                timeMultiplier: motion.timeMultiplier
            ) { frame in
                scene(frame, size: proxy.size, topInset: proxy.safeAreaInsets.top, pieces: timeline.style == .pieces)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: skip)
        .allowsHitTesting(!passesTouches)
        .accessibilityHidden(true)
        .launchProbe(
            "launch-layer", value: (timeline.style == .pieces ? "piezas" : "fundido") + (passesTouches ? ";libre" : ";tocable"))
        .sensoryFeedback(Haptics.lock, trigger: clicks)
        .task(id: skippedAt) { await run(timeline) }
        .onAppear {
            // Con piezas, la marca y el nombre vuelan a la ranura de la barra de Inicio: mientras tanto la ranura no
            // dibuja los suyos (nunca dos marcas). Con solo fundido nada vuela y la ranura se queda como está.
            if timeline.style == .pieces { anchor?.flying = .markAndName }
            #if DEBUG
            if let began = LaunchProbe.shared.appInitAt {
                LaunchProbe.shared.mountedAfterMs = Int(((Date().timeIntervalSince1970 - began) * 1000).rounded())
            }
            LaunchProbe.shared.launches += 1
            LaunchProbe.shared.style = timeline.style == .pieces ? "piezas" : "fundido"
            LaunchProbe.shared.startsAt = start.timeIntervalSince1970
            #endif
        }
    }

    /// Todo lo que se ve en un fotograma. Solo se mueven transformaciones y opacidades.
    private func scene(_ frame: LaunchFrame, size: CGSize, topInset: CGFloat, pieces: Bool) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
        // Con la ranura de Inicio a la vista, la marca y el nombre ATERRIZAN en ella, enteros, y en ese instante la
        // capa se quita y la ranura dibuja los suyos en el mismo sitio. Sin ranura, se deshacen por el camino.
        let brand = anchor?.brandFrame
        let lands = pieces && brand != nil
        let slot = brand ?? LaunchGeometry.fallbackSlot(topInset: topInset)
        let markSide = lands ? anchor?.brandMarkSide : nil
        let flight = CGFloat(frame.flight)
        let target = LaunchGeometry.markTarget(in: slot, markSide: markSide)
        let nameHome = CGPoint(x: center.x, y: center.y + Self.markSize / 2 + 28)
        let tracking = CGFloat(0.42 - 0.24 * frame.name) * Self.nameSize
        let dissolve = LaunchGeometry.landingOpacity(flight: flight, hasSlot: false)
        let nameSlot = LaunchGeometry.nameTarget(in: slot, markSide: markSide, gap: lands ? anchor?.brandGap : nil)
        // Al aterrizar, el nombre tiene el ancho del de la barra (el mismo tipo; solo difiere con el texto ampliado).
        let nameScale = lands && nameWidth > 0 ? nameSlot.width / nameWidth : 0.7
        return ZStack {
            Theme.canvas.opacity(frame.black)
            LaunchSkyCanvas(frame: frame, center: center)
            LaunchMark(frame: frame, size: Self.markSize)
                .scaleEffect(1 + (target.side / Self.markSize - 1) * flight)
                .position(LaunchGeometry.lerp(center, target.center, flight))
                // Con solo fundido (Sutil, Reducir movimiento) la marca grande nunca se ve más que el negro que tiene
                // debajo: el guion la apaga ENTERA antes de que el negro deje ver Inicio y la marca de su barra (nunca dos).
                .opacity(lands ? 1 : (pieces ? frame.mark * dissolve : min(frame.mark, frame.black)))
            Text(AppIdentity.displayName.uppercased())
                .font(.system(size: Self.nameSize, weight: .semibold))
                .tracking(tracking)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { nameWidth = $0 }
                // El interletraje también va detrás de la última letra: en el centro se compensa para que quede
                // centrado; en la ranura no (el nombre de la barra es el mismo texto, con ese mismo hueco detrás).
                .offset(x: tracking / 2 * (lands ? 1 - min(1, flight) : 1))
                .scaleEffect(1 + (nameScale - 1) * min(1, flight))
                .position(LaunchGeometry.lerp(nameHome, nameSlot.center, flight))
                // Sin ranura, el nombre se va apagando durante el vuelo.
                .opacity(lands ? frame.name : frame.name * frame.mark * Double(max(0, 1 - flight / 0.7)))
            if !frame.joined {
                LaunchHalvesCanvas(
                    frame: frame, center: center, markSize: Self.markSize, distanceScale: motion.level.distanceScale)
            }
        }
    }

    /// Un toque: el guion salta al vuelo y, desde ya, los toques pasan a Inicio.
    private func skip() {
        guard skippedAt == nil, !passesTouches else { return }
        skippedAt = Date()
        release()
        #if DEBUG
        LaunchProbe.shared.skips += 1
        #endif
    }

    /// Los avisos del guion, en orden: el golpe al encajar las piezas, Inicio se monta, la capa deja pasar los toques y
    /// la capa se quita. Los tiempos salen de `LaunchTimeline` por el multiplicador de grabación, así que obedecen la
    /// intensidad, Reducir movimiento y la cámara lenta. Si se toca para saltar, la tarea se relanza con los tiempos nuevos.
    private func run(_ timeline: LaunchTimeline) async {
        let multiplier = max(motion.timeMultiplier, 0.01)
        let began = start
        let skipped = skippedAt.map { max(0, $0.timeIntervalSince(began)) / multiplier }
        func wait(until elapsed: Double) async -> Bool {
            let remaining = elapsed * multiplier - Date().timeIntervalSince(began)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining), tolerance: LaunchClock.tolerance) }
            return !Task.isCancelled
        }
        if skipped == nil, let lockAt = timeline.piecesLockAt {
            guard await wait(until: lockAt) else { return }
            clicks += 1
        }
        guard await wait(until: skipped ?? timeline.assembleAt) else { return }
        if !assembled {
            assembled = true
            onAssemble()
        }
        guard await wait(until: skipped ?? timeline.interactiveAt) else { return }
        release()
        guard await wait(until: timeline.finishesAt(skippedAt: skipped)) else { return }
        #if DEBUG
        LaunchProbe.shared.finishedAfterMs = Int((Date().timeIntervalSince(began) * 1000).rounded())
        #endif
        // El reloj se para aquí (su último fotograma es el final exacto del guion: la marca en su ranura) y, en esta
        // misma actualización, la ranura de la barra vuelve a dibujar su marca y la capa se quita: ni un fotograma con
        // dos marcas ni uno sin ninguna.
        finished = true
        anchor?.flying = nil
        onFinish()
    }

    private func release() {
        guard !passesTouches else { return }
        passesTouches = true
        #if DEBUG
        LaunchProbe.shared.freeAfterMs = Int((Date().timeIntervalSince(start) * 1000).rounded())
        #endif
    }
}

/// La salida del bloqueo: la marca del bloqueo vuela a su ranura de la barra superior mientras Inicio se monta. En el
/// arranque en frío, además, cruzan las dos bandas. Es el tramo final del mismo guion (0,38 s; en Expresivo, 0,43 s).
///
/// Solo existe con la app ya desbloqueada (lo decide `ShellState`: nunca con el bloqueo puesto, y se quita al instante
/// si la app se vuelve a bloquear o sale de primer plano). No recibe toques, no tiene nada que leer y se quita sola.
/// Su primer fotograma es la marca entera justo donde estaba la del bloqueo, que en ese mismo instante deja de
/// dibujar la suya (`LockView.unlockWithFade`): nunca se ven dos marcas.
struct LaunchExit: View {
    /// Marco de la marca del bloqueo, en coordenadas de pantalla: de ahí sale.
    let from: CGRect
    /// Arranque en frío: cruzan las bandas y, si Inicio aún no ha apuntado su ranura, la marca vuela a donde estará.
    let cold: Bool
    let onFinish: () -> Void

    @Environment(\.motion) private var motion
    @Environment(\.launchAnchor) private var anchor
    @State private var start = Date()
    /// Inicio tiene su ranura a la vista: la marca aterriza en ella, entera (se decide una vez, al echar a volar).
    @State private var landsOnSlot: Bool?
    /// El vuelo ha terminado: el reloj se para aquí mismo (además de quitarse la capa).
    @State private var finished = false

    var body: some View {
        let timeline = LaunchTimeline(motion)
        ZStack {
            if timeline.exitDuration != nil {
                GeometryReader { proxy in
                    LaunchStage(
                        timeline: timeline, act: .exit(bands: cold), start: start, finished: finished,
                        timeMultiplier: motion.timeMultiplier
                    ) { frame in
                        scene(frame, topInset: proxy.safeAreaInsets.top)
                    }
                }
                .ignoresSafeArea()
                .launchProbe("launch-exit", value: cold ? "frio" : "templado")
            }
        }
        .allowsHitTesting(false)
        .task {
            // Con solo fundido (Sutil, Reducir movimiento) no hay vuelo: se quita enseguida.
            let seconds = (timeline.exitDuration ?? 0) * max(motion.timeMultiplier, 0.01)
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds), tolerance: LaunchClock.tolerance) }
            guard !Task.isCancelled else { return }
            // En la misma actualización: el reloj se para en su último fotograma (la marca exactamente en la ranura),
            // la ranura de la barra vuelve a dibujar la suya y esta capa se quita.
            finished = true
            anchor?.flying = nil
            onFinish()
        }
        .onAppear {
            if timeline.exitDuration != nil {
                let lands = anchor?.brandFrame != nil
                landsOnSlot = lands
                // La marca de la barra la lleva esta: la ranura no dibuja la suya hasta que aterrice.
                if lands { anchor?.flying = .mark }
                #if DEBUG
                if lands { LaunchProbe.shared.landings += 1 }
                #endif
            }
            #if DEBUG
            if timeline.exitDuration != nil {
                LaunchProbe.shared.exits += 1
                // Para las pruebas: ¿la marca echa a volar con un bloqueo aún fundiéndose y dibujando la suya?
                if LaunchProbe.shared.lockFading, LaunchProbe.shared.lockFadesWithItsMark {
                    LaunchProbe.shared.doubleMarks += 1
                }
            }
            #endif
        }
    }

    private func scene(_ frame: LaunchFrame, topInset: CGFloat) -> some View {
        let home = CGPoint(x: from.midX, y: from.midY)
        let brand = anchor?.brandFrame
        let lands = landsOnSlot ?? (brand != nil)
        let slot = brand ?? (cold ? LaunchGeometry.fallbackSlot(topInset: topInset) : from)
        let flight = CGFloat(frame.flight)
        let target = LaunchGeometry.markTarget(in: slot, markSide: lands && brand != nil ? anchor?.brandMarkSide : nil)
        return ZStack {
            Color.clear
            if cold {
                LaunchSkyCanvas(frame: frame, center: home)
            }
            AppMark(size: from.width)
                .scaleEffect(1 + (target.side / max(from.width, 1) - 1) * flight)
                .position(LaunchGeometry.lerp(home, target.center, flight))
                // Con ranura llega entera hasta ella; sin ranura se deshace por el camino.
                .opacity(lands ? 1 : frame.mark * LaunchGeometry.landingOpacity(flight: flight, hasSlot: false))
        }
        .accessibilityHidden(true)
    }
}

/// Cuentas de sitio del arranque: dónde aterriza la marca.
enum LaunchGeometry {
    /// Donde estará la ranura de la marca de la barra de Inicio (arriba a la izquierda, bajo la barra de estado), para
    /// cuando Inicio aún no ha apuntado su marco.
    static func fallbackSlot(topInset: CGFloat) -> CGRect {
        CGRect(x: 20, y: (topInset > 0 ? topInset : 59) + 14, width: 78, height: 22)
    }

    /// La ranura lleva la marca a la izquierda y el nombre a su derecha. La marca es un cuadrado de `markSide` (lo
    /// apunta la ranura de Inicio) centrado en vertical; sin ese dato, del alto de la ranura.
    static func markTarget(in slot: CGRect, markSide: CGFloat? = nil) -> (center: CGPoint, side: CGFloat) {
        let side = min(markSide ?? slot.height, slot.width)
        return (CGPoint(x: slot.minX + side / 2, y: slot.midY), side)
    }

    /// Dónde va el nombre dentro de la ranura: a la derecha de la marca y su hueco, hasta el borde.
    static func nameTarget(in slot: CGRect, markSide: CGFloat? = nil, gap: CGFloat? = nil) -> (center: CGPoint, width: CGFloat) {
        let side = min(markSide ?? slot.height, slot.width)
        let left = min(slot.maxX, slot.minX + side + (gap ?? 0))
        return (CGPoint(x: (left + slot.maxX) / 2, y: slot.midY), slot.maxX - left)
    }

    /// Con la ranura de Inicio a la vista, la marca llega entera hasta ella. Si aún no hay ranura (vuela hacia donde
    /// estará), se va deshaciendo por el camino: no aterriza encima de nada.
    static func landingOpacity(flight: CGFloat, hasSlot: Bool) -> Double {
        hasSlot ? 1 : Double(max(0, min(1, 1 - (flight - 0.25) / 0.6)))
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }
}
