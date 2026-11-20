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
                NavigationLink(value: track) {
                    GuideTrackRow(track: track, status: guideStatus(track, in: model.state))
                }
                .accessibilityIdentifier("guide-track-\(track.rawValue)")
                .listRowBackground(Theme.grouped)
            }

            Label {
                Text("imagin no avisa de los pagos: para imagin usa «\(GuideNames.transactionTrigger)».")
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
                Text(subtitle).titan(.meta).foregroundStyle(Theme.label3)
            }
            Spacer(minLength: 0)
            if case .working = status {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.label)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        switch status {
        case .notYet: "Sin configurar"
        case .working(let since): "Funciona desde el \(Self.day(since))"
        }
    }

    /// "20 nov"
    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }
}
