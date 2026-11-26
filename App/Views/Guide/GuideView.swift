import SwiftUI
import MiBancoCore

/// La lista de guías de «Avisos al instante»: una por banco y una de Apple Pay por banco, cada una con su estado.
/// Va dentro del `Form` de `AlertsGuideView`; cada fila empuja `GuideStepView` en la misma navegación (sin hoja).
struct GuideView: View {
    let model: LedgerModel
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        Group {
            Text("Tu iPhone le pasa a \(guideAppName) los avisos de tus bancos. Se configura una vez, en \(GuideNames.shortcutsApp).")
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.label2)
                .listRowBackground(Theme.grouped)

            // Qué guía hacer, en líneas cortas.
            VStack(alignment: .leading, spacing: Theme.Space.small) {
                ForEach(guideListAdvice, id: \.self) { line in
                    Text(line)
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("guide-advice")
            .listRowBackground(Theme.grouped)

            ForEach(GuideTrack.allCases, id: \.self) { track in
                NavigationLink {
                    GuideStepView(track: track, model: model, resume: preferences.guideResume(track))
                } label: {
                    GuideTrackRow(track: track, status: guideStatus(track, in: model.state, now: Date()),
                                  resumeIndex: preferences.guideResume(track))
                }
                .accessibilityIdentifier("guide-track-\(track.rawValue)")
                .listRowBackground(Theme.grouped)
            }
        }
    }
}

private struct GuideTrackRow: View {
    let track: GuideTrack
    let status: GuideStatus
    /// Paso en que se dejó la guía a medias (desde 0), si lo hay.
    let resumeIndex: Int?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(track.title).titan(.option).foregroundStyle(Theme.label)
                    if track.isOptional {
                        Text("Opcional")
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(Theme.label2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .overlay(Capsule().stroke(Theme.label3, lineWidth: 1))
                    }
                }
                Text(subtitle).titan(.meta).foregroundStyle(Theme.label3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            switch status {
            case .working:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.label)
                    .accessibilityHidden(true)
            case .silent:
                // Neutro: un aviso que no llega puede ser simplemente que no ha habido pagos.
                Image(systemName: "clock")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.label2)
                    .accessibilityHidden(true)
            case .notYet:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// «Funciona · Último aviso: 20 nov», «Hace 15 días que no llega ningún aviso…», «Vas por el paso 9 de 22» (guía
    /// empezada que todavía no ha avisado) o «Aún no ha llegado ningún aviso».
    private var subtitle: String {
        if case .notYet = status, let resumeIndex {
            return guideResumeLine(index: resumeIndex, total: guideSteps(for: track).count)
        }
        return guideStatusLine(status, applePay: track.isApplePay)
    }
}
