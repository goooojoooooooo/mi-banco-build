import SwiftUI
import MiBancoCore

/// La lista de guías de «Avisos al instante»: una por banco y una para Apple Pay, cada una con su progreso.
/// Va dentro del `Form` de `AlertsGuideView`; cada fila empuja `GuideStepView` en la misma navegación (sin hoja).
struct GuideView: View {
    let model: LedgerModel

    var body: some View {
        Group {
            Text("Tu iPhone le pasa a \(guideAppName) los avisos de tus bancos. Se configura una vez, en \(GuideNames.shortcutsApp).")
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.label2)
                .listRowBackground(Theme.grouped)

            ForEach(GuideTrack.allCases, id: \.self) { track in
                NavigationLink {
                    GuideStepView(track: track, model: model)
                } label: {
                    GuideTrackRow(track: track, status: guideStatus(track, in: model.state, now: Date()))
                }
                .accessibilityIdentifier("guide-track-\(track.rawValue)")
                .listRowBackground(Theme.grouped)
            }

            Label {
                Text("imagin no avisa de sus pagos: para imagin usa la guía de Apple Pay. Hay una guía de Apple Pay por banco: si pagas con Apple Pay desde otro banco, haz también la suya.")
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.label2)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.label2)
            }
            .listRowBackground(Theme.grouped)
        }
    }
}

private struct GuideTrackRow: View {
    let track: GuideTrack
    let status: GuideStatus

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).titan(.option).foregroundStyle(Theme.label)
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
                Image(systemName: "exclamationmark.circle")
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

    /// «Funciona · Último aviso: 20 nov», «Hace 15 días que no llega ningún aviso» o «Aún no ha llegado ningún aviso».
    private var subtitle: String { guideStatusLine(status) }
}
