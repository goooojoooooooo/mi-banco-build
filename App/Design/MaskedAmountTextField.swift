import SwiftUI

/// Lo que enseña un campo de importe con el ojo cerrado y sin editar: la máscara del kit.
let maskedFieldMask = maskedEUR(0, sign: false)

/// Un campo de importe que puede ir enmascarado (Ajustes, Avisos, bienvenida, Presupuestos: un solo componente).
///
/// Con `masked` (el ojo cerrado y sin editar) el campo CONTIENE la máscara «•••,•• €», no la cifra: la cifra no se
/// monta ni se pinta en transparente. Escribir en el campo enmascarado no hace nada (el setter no guarda); al tocarlo, quien
/// lo usa lo enfoca, deja de estar enmascarado y vuelve el texto de verdad. El cambio de cifra a máscara (y al revés) es en
/// el acto: sin transición de contenido ni animación; el campo es sensible para las capturas del sistema. VoiceOver dice
/// «importe oculto».
///
/// La sonda de las pruebas (solo DEBUG, con `-MiBancoDemoDrawnAmounts`) apunta EL MISMO texto que recibe el campo
/// (`shown`): no se puede separar de lo que se dibuja (lote de cierre, ronda 1, I-1).
struct MaskedAmountTextField: View {
    let placeholder: String
    @Binding var text: String
    let masked: Bool

    var body: some View {
        let shown = shownText
        TextField(placeholder, text: shown)
            .foregroundStyle(textColor)
            .contentTransition(.identity)
            .animation(nil, value: masked)
            .privacySensitive()
            .accessibilityValue((masked ? "importe oculto" : text) + drawnAmountForTests(shown.wrappedValue))
    }

    /// El texto que se le da al campo (y que apunta la sonda).
    private var shownText: Binding<String> {
        #if DEBUG
        // Solo para demostrar que la prueba falla con el defecto de antes (`-MiBancoDemoRegressMaskedField`): el texto
        // real dentro del campo, pintado en transparente.
        if DemoMode.isActive, DemoMode.regressesMaskedField { return $text }
        #endif
        return masked ? Binding(get: { maskedFieldMask }, set: { _ in }) : $text
    }

    private var textColor: Color {
        #if DEBUG
        if DemoMode.isActive, DemoMode.regressesMaskedField, masked { return .clear }
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
