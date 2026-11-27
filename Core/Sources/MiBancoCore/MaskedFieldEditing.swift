import Foundation

/// Qué enseña un campo de importe y qué guarda, según el ojo (decisión del dueño: «con el ojo cerrado, tocar un campo para
/// editarlo NUNCA enseña la cifra guardada»). Valor puro; el campo (`MaskedAmountTextField`) le cuenta lo que pasa.
///
/// - Ojo abierto: el campo es el texto guardado, como siempre.
/// - Ojo cerrado y sin editar: la máscara (o vacío si no hay nada guardado).
/// - Ojo cerrado y editando: el campo se abre VACÍO y enseña solo lo que se teclea. Lo tecleado pasa a ser lo guardado;
///   si se borra todo, lo guardado vuelve a ser el valor de antes: entrar y salir sin teclear nunca guarda un 0 ni un
///   vacío, y la máscara no se guarda jamás.
public struct MaskedFieldEditing: Equatable, Sendable {
    /// Lo que se ha tecleado desde que se empezó a editar con el ojo cerrado.
    public private(set) var draft = ""
    /// El valor guardado cuando se empezó a editar con el ojo cerrado; `nil` si no se está editando así.
    public private(set) var original: String?

    public init() {}

    public enum Shown: Equatable, Sendable {
        /// La máscara del kit.
        case mask
        /// Este texto.
        case text(String)
    }

    /// Se está editando con el ojo cerrado (empezó así).
    public var editsHidden: Bool { original != nil }

    /// El campo recibe el foco. Con el ojo cerrado empieza vacío y apunta el valor guardado.
    public mutating func begin(stored: String, hidden: Bool) {
        guard hidden else {
            original = nil
            draft = ""
            return
        }
        original = stored
        draft = ""
    }

    /// El campo pierde el foco.
    public mutating func end() {
        original = nil
        draft = ""
    }

    /// Se ha tecleado `typed` (el texto entero del campo). Devuelve lo que hay que guardar: lo tecleado o, si está vacío,
    /// el valor de antes. Sin una edición con el ojo cerrado en marcha, lo tecleado tal cual.
    public mutating func type(_ typed: String) -> String {
        guard let original else { return typed }
        draft = typed
        return typed.isEmpty ? original : typed
    }

    /// Lo que enseña el campo.
    public func shown(stored: String, hidden: Bool, editing: Bool) -> Shown {
        guard hidden else { return .text(stored) }
        if editing, editsHidden { return .text(draft) }
        // Con el ojo cerrado nunca la cifra guardada: máscara si hay algo, vacío si no.
        return stored.isEmpty ? .text("") : .mask
    }

    /// Lo que dice VoiceOver: con el ojo cerrado, «importe oculto» (o `hiddenText`, p. ej. «interés oculto») salvo lo que se
    /// está tecleando.
    public func spoken(stored: String, hidden: Bool, editing: Bool, hiddenText: String = "importe oculto") -> String {
        guard hidden else { return stored }
        if editing, editsHidden, !draft.isEmpty { return draft }
        return hiddenText
    }
}
