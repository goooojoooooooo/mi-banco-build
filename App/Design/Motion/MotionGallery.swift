#if DEBUG
import SwiftUI
import MiBancoCore

/// Galería de movimiento solo para compilaciones DEBUG: enseña, sobre negro, cada pieza del kit sin enlazarla a ninguna
/// pantalla. Se abre con `-MiBancoMotionGallery` (junto a `-MiBancoDemo`, para que nada toque datos ni UserDefaults).
/// `-MiBancoMotionGalleryPage cifras|filas|controles|botones|segmentado|pasos` baja hasta esa parte; `-MiBancoMotionReduce` la abre con
/// Reducir movimiento simulado; `-MiBancoMotionGalleryNoPrefs` la monta FUERA del entorno de preferencias (como lo haría
/// una hoja o una ventana nueva que se olvidase de ellas). Datos inventados.
enum MotionGalleryLaunch {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var isActive: Bool { arguments.contains("-MiBancoMotionGallery") }
    static var startsReduced: Bool { arguments.contains("-MiBancoMotionReduce") }
    /// Sin `AppPreferences` en el entorno de la galería.
    static var withoutPreferences: Bool { arguments.contains("-MiBancoMotionGalleryNoPrefs") }
    /// Hasta dónde baja al abrir: una de las seis anclas de arriba (o nada).
    static var page: String? {
        guard let i = arguments.firstIndex(of: "-MiBancoMotionGalleryPage"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}

extension View {
    /// Con `-MiBancoMotionGallery`, tapa toda la app con la galería (y la oculta a la accesibilidad de lo de debajo).
    func motionGalleryOverlay() -> some View {
        modifier(MotionGalleryOverlay())
    }
}

private struct MotionGalleryOverlay: ViewModifier {
    @Environment(AppPreferences.self) private var preferences: AppPreferences?

    func body(content: Content) -> some View {
        // Con la galería, la app de debajo ni se monta (así no deja elementos de accesibilidad ni tareas).
        if MotionGalleryLaunch.isActive {
            MotionGallery()
                .motionEnvironment()
                // `-MiBancoMotionGalleryNoPrefs`: el entorno sin preferencias (el ojo guardado sigue mandando).
                .environment(MotionGalleryLaunch.withoutPreferences ? nil : preferences)
                .background(Color.black.ignoresSafeArea())
        } else {
            content
        }
    }
}

struct MotionGallery: View {
    /// Opcional: sin preferencias la galería usa su propio nivel local y no se cierra.
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    @Environment(\.motion) private var baseMotion

    @State private var forceReduce = MotionGalleryLaunch.startsReduced
    @State private var replay = 0
    @State private var cents = 377475
    @State private var lifted = false
    @State private var burst = 0
    @State private var sheenPhase: CGFloat = 0.3
    @State private var fraction = 0.45
    @State private var step = 0
    @State private var stepsDone = false
    @State private var period = 1
    @State private var localLevel = AppPreferences.defaultMotionLevel

    private var motion: MotionContext {
        var m = baseMotion
        m.reduce = m.reduce || forceReduce
        return m
    }

    private var levelBinding: Binding<MotionLevel> {
        Binding(
            get: { preferences?.motionLevel ?? localLevel },
            set: { if let preferences { preferences.motionLevel = $0 } else { localLevel = $0 } })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 32) {
                    Text("Galería de movimiento")
                        .titan(.sheetTitle)
                        .foregroundStyle(Theme.label)
                        .accessibilityIdentifier("gallery.title")
                        .padding(.top, 24)
                    levelSection
                    markSection
                    Color.clear.frame(height: 1).id("cifras")
                    amountSection
                    Color.clear.frame(height: 1).id("filas")
                    rowsSection
                    Color.clear.frame(height: 1).id("controles")
                    glassSection
                    liftSection
                    burstSection
                    Color.clear.frame(height: 1).id("botones")
                    morphSection
                    Color.clear.frame(height: 1).id("segmentado")
                    segmentedSection
                    fillSection
                    Color.clear.frame(height: 1).id("pasos")
                    stepperSection
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .task {
                guard let page = MotionGalleryLaunch.page else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo(page, anchor: .top)
            }
        }
        .environment(\.motion, motion)
        .foregroundStyle(Theme.label)
        .tint(.white)
    }

    // MARK: Secciones

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .titan(.header)
                .foregroundStyle(Theme.label3)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }

    private func chip(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Theme.raised, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(id)
    }

    private var levelSection: some View {
        section("Intensidad") {
            TitanSegmented(
                selection: levelBinding,
                options: [(.subtle, "Sutil"), (.balanced, "Equilibrado"), (.expressive, "Expresivo")])
            Toggle("Reducir movimiento", isOn: $forceReduce)
                .toggleStyle(TitanToggleStyle())
                .accessibilityIdentifier("gallery.reduce")
        }
    }

    private var markSection: some View {
        section("Marca") {
            MarkReveal(size: 132, replay: replay)
            chip("Repetir marca", id: "gallery.mark.replay") { replay += 1 }
        }
    }

    private var amountSection: some View {
        section("Cifras") {
            RollingAmount(
                cents: cents, countsUp: true,
                style: .hero(euros: 44, cents: 24, centsColor: Theme.label2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("gallery.amount")
            HStack(spacing: 10) {
                chip("Pago", id: "gallery.pay") { cents -= 480 }
                chip("Ingreso", id: "gallery.income") { cents += 124_500 }
                // Sin preferencias el ojo no puede funcionar: no se enseña.
                if let preferences {
                    chip("Ojo", id: "gallery.eye") {
                        withAnimation(motion.fade) { preferences.privateMode.toggle() }
                    }
                } else {
                    // Cierra el ojo guardado sin tocar el estado de la galería (como Ajustes desde otra pantalla): el
                    // importe sin preferencias lo observa en vivo.
                    chip("Cerrar ojo guardado", id: "gallery.storedEye.close") {
                        AppPreferences.privateModeStore.set(true, forKey: AppPreferences.privateModeKey)
                    }
                }
            }
        }
    }

    /// Importes de una línea con la tipografía de una fila puesta por quien los coloca (`.plain` no trae la suya).
    private var rowsSection: some View {
        section("Filas") {
            VStack(spacing: 4) {
                rowAmount("Café", cents: -480, sign: false, color: Theme.label, id: "gallery.row.expense")
                rowAmount("Nómina", cents: 125_000, sign: true, color: Theme.income, id: "gallery.row.income")
                rowAmount("Saldo", cents: 6_120, sign: false, color: Theme.label, id: "gallery.row.plain")
            }
        }
    }

    private func rowAmount(_ name: String, cents: Int, sign: Bool, color: Color, id: String) -> some View {
        HStack {
            Text(name)
                .titan(.subtitle)
                .foregroundStyle(Theme.label2)
            Spacer(minLength: 12)
            RollingAmount(cents: cents, countsUp: false, style: .plain(sign: sign))
                .titan(.row)
                .foregroundStyle(color)
                .accessibilityIdentifier(id)
        }
        .frame(minHeight: 44)
    }

    private var glassSection: some View {
        section("Cristal") {
            Button {
                burst += 1
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 52, height: 52)
                    .glassSurface(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.glassPress)
            .accessibilityLabel("Botón de cristal")
            .accessibilityIdentifier("gallery.glass")
        }
    }

    private var liftSection: some View {
        section("Levantar y brillo") {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CardMaterial.all.gradient)
                .overlay { SheenOverlay(phase: sheenPhase, tilt: 0).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) }
                .frame(width: 230, height: 130)
                .lift(lifted)
                .padding(.vertical, 18)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                chip(lifted ? "Soltar" : "Levantar", id: "gallery.lift") { lifted.toggle() }
                chip("Brillo", id: "gallery.sheen") {
                    sheenPhase = 0
                    withAnimation(.easeInOut(duration: motion.seconds(0.9))) { sheenPhase = 1 }
                }
            }
        }
    }

    private var burstSection: some View {
        section("Destello") {
            ZStack {
                SuccessBurst(trigger: burst)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.income)
                    .accessibilityHidden(true)
            }
            .frame(height: 150)
            chip("Destello", id: "gallery.burst") { burst += 1 }
        }
    }

    private var morphSection: some View {
        section("Botón que se transforma") {
            MorphingButton(title: "Probar aviso", doneTitle: "Enviado") {
                try? await Task.sleep(for: .milliseconds(700))
                return true
            }
            MorphingButton(title: "Probar fallo", doneTitle: "Enviado") {
                try? await Task.sleep(for: .milliseconds(500))
                return false
            }
            // Un hueco alto con un `Spacer` hermano: el botón conserva su alto (K9).
            VStack(spacing: 0) {
                MorphingButton(title: "Probar en hueco", doneTitle: "Enviado") { true }
                Spacer(minLength: 0)
            }
            .frame(height: 200)
        }
    }

    private var segmentedSection: some View {
        section("Segmentado") {
            TitanSegmented(selection: $period, options: [(0, "Hoy"), (1, "Semana"), (2, "Mes")])
                .accessibilityIdentifier("gallery.segmented")
        }
    }

    private var fillSection: some View {
        section("Presupuesto") {
            FillBar(fraction: fraction, label: "Gasto en comida")
                .accessibilityIdentifier("gallery.fill")
            HStack(spacing: 10) {
                chip("Llenar 95 %", id: "gallery.fill.up") { fraction = 0.95 }
                chip("Bajar 45 %", id: "gallery.fill.down") { fraction = 0.45 }
            }
        }
    }

    private var stepperSection: some View {
        section("Pasos") {
            StepperProgress(steps: ["Autorizar", "Leer cuentas", "Listo"], current: step, finished: stepsDone)
                .padding(.horizontal, 12)
            HStack(spacing: 10) {
                chip("Siguiente paso", id: "gallery.step.next") {
                    if step < 2 { step += 1 } else { stepsDone = true }
                }
                chip("Reiniciar pasos", id: "gallery.step.reset") {
                    step = 0
                    stepsDone = false
                }
            }
        }
    }
}
#endif
