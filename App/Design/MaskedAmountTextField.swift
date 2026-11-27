import SwiftUI
import MiBancoCore

/// Lo que enseña un campo de importe con el ojo cerrado y sin editar: la máscara del kit.
let maskedFieldMask = maskedEUR(0, sign: false)

/// Un campo de importe que obedece al ojo (Ajustes, Avisos, bienvenida, Presupuestos: un solo componente).
///
/// Qué enseña y qué guarda lo decide Core (`MaskedFieldEditing`, decisión del dueño: con el ojo cerrado la cifra guardada
/// NUNCA se ve, tampoco al tocar el campo para editarlo):
/// - Ojo abierto: el texto guardado, como siempre.
/// - Ojo cerrado y sin editar: el campo CONTIENE la máscara «•••,•• €» (la cifra no se monta ni se pinta en transparente).
/// - Ojo cerrado y editando: el campo se abre vacío y enseña solo lo que se teclea; lo tecleado es lo que se guarda y, si
///   se borra todo, se guarda el valor de antes (nunca un 0, un vacío ni la máscara).
/// El cambio de cifra a máscara es en el acto: sin transición de contenido ni animación; el campo es sensible para las
/// capturas del sistema. `editing` es el foco del campo, que lleva quien lo usa (con `.focused`).
///
/// La sonda de las pruebas (solo DEBUG, con `-MiBancoDemoDrawnAmounts`) apunta EL MISMO texto que recibe el campo
/// (`shown`): no se puede separar de lo que se dibuja.
struct MaskedAmountTextField: View {
    let placeholder: String
    @Binding var text: String
    /// El ojo está cerrado.
    let hidden: Bool
    /// El campo tiene el foco.
    let editing: Bool
    /// Lo que enseña con el ojo cerrado y sin editar (el interés de la cuenta remunerada usa «•,•• %»).
    var mask: String = maskedFieldMask
    /// Lo que dice VoiceOver con el ojo cerrado («interés oculto» en el campo del interés).
    var hiddenSpoken: String = "importe oculto"

    @State private var edit = MaskedFieldEditing()

    var body: some View {
        let shown = shownText
        // Con el ojo cerrado, ni el marcador de posición («0,00 €») parece una cifra: el campo vacío no enseña nada.
        TextField(hidden ? "" : placeholder, text: shown)
            .foregroundStyle(textColor)
            .contentTransition(.identity)
            .animation(nil, value: hidden)
            .animation(nil, value: editing)
            .privacySensitive()
            .accessibilityValue(edit.spoken(stored: text, hidden: hidden, editing: editing, hiddenText: hiddenSpoken)
                + drawnAmountForTests(shown.wrappedValue))
            .onChange(of: editing, initial: true) { _, now in
                if now {
                    edit.begin(stored: text, hidden: hidden)
                } else {
                    edit.end()
                }
            }
    }

    /// El texto que se le da al campo (y que apunta la sonda).
    private var shownText: Binding<String> {
        #if DEBUG
        // Solo para demostrar que la prueba falla con el defecto de antes (`-MiBancoDemoRegressMaskedField`): el texto
        // real dentro del campo, pintado en transparente.
        if DemoMode.isActive, DemoMode.regressesMaskedField { return $text }
        #endif
        switch edit.shown(stored: text, hidden: hidden, editing: editing) {
        case .mask:
            return Binding(get: { mask }, set: { _ in })
        case .text(let shown):
            if !hidden { return $text }
            if editing, edit.editsHidden {
                // Lo tecleado se enseña; lo que se guarda lo decide Core (lo tecleado o, vacío, el valor de antes).
                return Binding(get: { edit.draft }, set: { typed in text = edit.type(typed) })
            }
            return Binding(get: { shown }, set: { _ in })
        }
    }

    private var textColor: Color {
        #if DEBUG
        if DemoMode.isActive, DemoMode.regressesMaskedField, hidden, !editing { return .clear }
        #endif
        return Theme.label
    }
}

/// Solo en la demo con `-MiBancoDemoDrawnAmounts`: lo que DIBUJA un campo o un texto con importe («; dibujado: •••,•• €»),
/// para que una prueba pueda fallar si con el ojo cerrado se dibuja una cifra. En la app de verdad, nada.
func drawnAmountForTests(_ drawn: String) -> String {
    #if DEBUG
    if DemoMode.isActive, DemoMode.exposesDrawnAmounts { return "; dibujado: " + drawn }
    #endif
    return ""
}
