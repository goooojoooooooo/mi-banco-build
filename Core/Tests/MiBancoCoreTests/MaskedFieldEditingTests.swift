import Testing
@testable import MiBancoCore

/// Editar un importe con el ojo cerrado (decisión del dueño): la cifra guardada nunca se enseña; lo tecleado sí; salir sin
/// teclear conserva el valor; la máscara nunca se guarda.
@Suite struct MaskedFieldEditingTests {
    @Test func conElOjoAbiertoNadaCambia() {
        var field = MaskedFieldEditing()
        field.begin(stored: "340,20", hidden: false)
        #expect(field.shown(stored: "340,20", hidden: false, editing: true) == .text("340,20"))
        #expect(field.type("341") == "341")
        #expect(field.spoken(stored: "341", hidden: false, editing: true) == "341")
        #expect(field.shown(stored: "", hidden: false, editing: false) == .text(""))
    }

    @Test func conElOjoCerradoSinEditarEsLaMascara() {
        let field = MaskedFieldEditing()
        #expect(field.shown(stored: "340,20", hidden: true, editing: false) == .mask)
        #expect(field.shown(stored: "", hidden: true, editing: false) == .text(""))
        #expect(field.spoken(stored: "340,20", hidden: true, editing: false) == "importe oculto")
    }

    /// Al enfocar con el ojo cerrado el campo se abre vacío: ni la cifra ni nada de ella, ni en lo que se ve ni en lo que
    /// se dice.
    @Test func alEnfocarConElOjoCerradoSeAbreVacio() {
        var field = MaskedFieldEditing()
        field.begin(stored: "340,20", hidden: true)
        let shown = field.shown(stored: "340,20", hidden: true, editing: true)
        #expect(shown == .text(""))
        #expect(field.spoken(stored: "340,20", hidden: true, editing: true) == "importe oculto")
    }

    /// Lo tecleado se ve mientras se teclea y es lo que se guarda.
    @Test func loTecleadoSeVeYSeGuarda() {
        var field = MaskedFieldEditing()
        field.begin(stored: "340,20", hidden: true)
        var stored = field.type("5")
        #expect(stored == "5")
        stored = field.type("512,34")
        #expect(stored == "512,34")
        #expect(field.shown(stored: stored, hidden: true, editing: true) == .text("512,34"))
        #expect(field.spoken(stored: stored, hidden: true, editing: true) == "512,34")
        field.end()
        #expect(field.shown(stored: stored, hidden: true, editing: false) == .mask)
    }

    /// Entrar y salir sin teclear (o borrarlo todo) conserva el valor de antes: nunca un 0 ni un vacío.
    @Test func salirSinTeclearConservaElValor() {
        var field = MaskedFieldEditing()
        field.begin(stored: "340,20", hidden: true)
        #expect(field.type("") == "340,20")
        #expect(field.type("9") == "9")
        #expect(field.type("") == "340,20", "borrarlo todo devuelve el valor de antes")
        #expect(field.shown(stored: "340,20", hidden: true, editing: true) == .text(""), "y no lo enseña")
        field.end()
        #expect(!field.editsHidden)
    }

    /// La máscara nunca llega a lo guardado: lo único que se guarda es lo tecleado o el valor de antes.
    @Test func laMascaraNuncaSeGuarda() {
        var field = MaskedFieldEditing()
        field.begin(stored: "340,20", hidden: true)
        for typed in ["", "1", "12", "", "7,5"] {
            let stored = field.type(typed)
            #expect(!stored.contains("•"), "\(stored)")
        }
    }

    /// Si el ojo se cierra con el campo ya enfocado (empezó con el ojo abierto), no hay edición oculta: máscara.
    @Test func elOjoQueSeCierraEditandoEnseñaLaMascara() {
        var field = MaskedFieldEditing()
        field.begin(stored: "340,20", hidden: false)
        #expect(field.shown(stored: "340,20", hidden: true, editing: true) == .mask)
        #expect(field.spoken(stored: "340,20", hidden: true, editing: true) == "importe oculto")
    }
}
