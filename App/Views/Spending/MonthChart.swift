import SwiftUI
import Charts
import MiBancoCore

/// El gráfico del mes en Gasto: lo gastado acumulado día a día (línea blanca, hasta hoy) sobre el mes anterior entero
/// (línea gris de trazos). Se dibuja solo al entrar: aparecen la rejilla y el mes anterior (0,4 s), la línea del mes se
/// traza de izquierda a derecha (0,9 s), el área bajo ella se funde, y el punto de hoy salta con un anillo que se abre.
/// - Swift Charts pone la escala, la rejilla y la línea del mes anterior; la línea del mes, el área y el punto son formas
///   colocadas con esa misma escala (`ChartProxy`), porque una marca de Charts no se puede trazar con `trim`.
/// - Solo se animan el trazo, la opacidad y la escala, con los tiempos del kit (`\.motion`). Con Reducir movimiento sale
///   dibujado de una vez; sin efectos ricos (Reducir o Bajo consumo) no hay anillo.
/// - Con el ojo cerrado, las etiquetas de importe de la rejilla son «•••» y VoiceOver dice «importe oculto». Para
///   VoiceOver es un solo elemento (los puntos de Charts, que dirían cada importe, no se exponen).
struct MonthChart: View {
    let series: MonthSeries
    /// "Noviembre" y "Octubre": la leyenda.
    let title: String
    let previousTitle: String

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion
    @Environment(\.entrance) private var entrance
    /// La entrada por capas en la que el gráfico ya ha empezado a dibujarse; nil = aún no ha empezado nunca.
    @State private var landed: Int?
    /// Cada dibujo lanza el salto del punto de hoy y (con efectos ricos) su anillo.
    @State private var draw = 0

    private static let previousColor = Color(hex: "#5A5A5E")

    var body: some View {
        let hidden = preferences.privateMode
        VStack(alignment: .leading, spacing: 8) {
            chart(hidden: hidden)
                .frame(height: 124)
            HStack(spacing: 14) {
                key(Theme.label, title)
                key(Self.previousColor, previousTitle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gráfico del gasto de \(title.lowercased()) frente a \(previousTitle.lowercased())")
        .accessibilityValue(hidden
            ? "importe oculto"
            : "\(spokenAmount(series.totalCents, hidden: false)) frente a \(spokenAmount(series.previousTotalCents, hidden: false))")
        .accessibilityIdentifier("gasto.grafico")
        .onAppear { start() }
        // Entrada nueva (se entra en la pestaña): el gráfico, que ya está en blanco (`on`), se dibuja otra vez.
        .onChange(of: entrance.token) { _, _ in start() }
    }

    // MARK: Estado del dibujo

    private var replays: Bool { entrance.active && entrance.scope == .assembly }

    /// true = dibujado (o dibujándose); false = en blanco, a la espera de arrancar. Pasa a false sin animación (cada
    /// pieza anima solo el paso a true) y a true con la animación de cada pieza.
    private var on: Bool {
        guard !motion.reduce else { return true }
        guard let landed else { return false }
        return !(replays && landed != entrance.token)
    }

    private func start() {
        guard !motion.reduce else { return }
        landed = entrance.token
        draw += 1
    }

    /// La animación de una pieza al dibujarse; al ponerse en blanco, ninguna.
    private func draws(_ animation: Animation) -> Animation? { on ? animation : nil }

    // MARK: Piezas

    private func chart(hidden: Bool) -> some View {
        let top = max(series.topCents + series.topCents / 8, 100)
        return Chart {
            ForEach(series.previous) { point in
                LineMark(x: .value("Día", point.day), y: .value("Gasto", point.cents))
            }
            .foregroundStyle(Self.previousColor)
            .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 4]))
            // Los puntos de Charts dirían cada importe: no existen para la accesibilidad (el gráfico se lee entero).
            .accessibilityHidden(true)
        }
        .chartXScale(domain: 0...series.axisDays)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: series.axisTicks()) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.separator)
                AxisValueLabel {
                    if let cents = value.as(Int.self) {
                        Text(hidden ? "•••" : formatEURWhole(cents))
                            .font(.caption2)
                            .foregroundStyle(Theme.label3)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                month(proxy: proxy, geo: geo)
            }
        }
        .opacity(on ? 1 : 0)
        .animation(draws(.easeOut(duration: motion.seconds(0.4))), value: on)
    }

    /// La línea del mes, su área y el punto de hoy, colocados con la escala del gráfico.
    @ViewBuilder private func month(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let anchor = proxy.plotFrame {
            let frame = geo[anchor]
            let points = series.current.compactMap { point in
                proxy.position(for: (x: point.day, y: point.cents)).map { CGPoint(x: frame.minX + $0.x, y: frame.minY + $0.y) }
            }
            if points.count > 1, let end = points.last {
                ZStack {
                    MonthArea(points: points, floor: frame.maxY)
                        .fill(LinearGradient(colors: [Theme.label.opacity(0.16), Theme.label.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .opacity(on ? 1 : 0)
                        .animation(draws(.easeOut(duration: motion.seconds(0.5)).delay(motion.seconds(0.7))), value: on)
                    MonthLine(points: points)
                        .trim(from: 0, to: on ? 1 : 0)
                        .stroke(Theme.label, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .animation(draws(.easeInOut(duration: motion.seconds(0.9)).delay(motion.seconds(0.12))), value: on)
                    // El anillo: espera a que la línea llegue (1 s), aparece al 80 % y se abre de 4 a 14 pt de radio.
                    Circle()
                        .stroke(Theme.label, lineWidth: 1.2)
                        .frame(width: 8, height: 8)
                        .keyframeAnimator(initialValue: RingPulse(), trigger: motion.richEffects ? draw : 0) { content, value in
                            content.scaleEffect(value.scale).opacity(value.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(0.0, duration: motion.seconds(1.0))
                                MoveKeyframe(0.8)
                                CubicKeyframe(0.0, duration: motion.seconds(0.9))
                            }
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(1.0, duration: motion.seconds(1.0))
                                CubicKeyframe(3.5, duration: motion.seconds(0.9))
                            }
                        }
                        .position(end)
                    // El punto de hoy: invisible hasta que llega la línea (1 s) y entonces salta de 0,2 a 1 con rebote. Va
                    // por fotogramas clave (como el anillo) y no con un muelle implícito: un muelle que se repite antes
                    // de haberse asentado se funde con el anterior y el punto se quedaba a la vista desde el principio.
                    // En reposo (y con Reducir movimiento, que no lanza nada) está entero y a la vista.
                    Circle()
                        .fill(Theme.label)
                        .frame(width: 6.4, height: 6.4)
                        .keyframeAnimator(initialValue: DotPop(), trigger: draw) { content, value in
                            content.scaleEffect(value.scale).opacity(value.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.opacity) {
                                MoveKeyframe(0.0)
                                LinearKeyframe(0.0, duration: motion.seconds(1.0))
                                MoveKeyframe(1.0)
                            }
                            KeyframeTrack(\.scale) {
                                MoveKeyframe(0.2)
                                LinearKeyframe(0.2, duration: motion.seconds(1.0))
                                SpringKeyframe(1.0, duration: motion.seconds(0.7),
                                               spring: .bouncy(duration: motion.seconds(0.36), extraBounce: 0.2))
                            }
                        }
                        .position(end)
                }
            }
        }
    }

    private func key(_ color: Color, _ name: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 2)
            Text(name)
                .titan(.caption)
                .foregroundStyle(Theme.label3)
        }
    }
}

/// Lo que se anima del punto de hoy (en reposo, entero y a la vista).
private struct DotPop {
    var scale = 1.0
    var opacity = 1.0
}

/// Lo que se anima del anillo del punto de hoy.
private struct RingPulse {
    var scale = 1.0
    var opacity = 0.0
}

/// La línea del mes: une los puntos (ya en coordenadas de la vista) en orden.
private struct MonthLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

/// El área bajo la línea del mes, hasta el suelo del gráfico.
private struct MonthArea: Shape {
    let points: [CGPoint]
    let floor: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: floor))
        for point in points { path.addLine(to: point) }
        path.addLine(to: CGPoint(x: last.x, y: floor))
        path.closeSubpath()
        return path
    }
}
