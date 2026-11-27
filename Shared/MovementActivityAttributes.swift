import ActivityKit

/// Compartido por la app (que la inicia) y la extensión de widgets (que la dibuja).
struct MovementActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var bank: String
        var balanceCents: Int?
        /// true = `balanceCents` es una estimación (saldo a mano más movimientos), no el que dio el banco.
        var estimated: Bool
        /// Opcional (SEC-06): nil cuando se compone o se actualiza con el ojo cerrado para no guardar importes.
        /// Compatible con estados previos que lo guardaban como `Int`.
        var lastAmountCents: Int?
        var merchant: String?
        var kind: String
        var totalCents: Int?
        /// Título del aviso (ya redactado), para que el widget no reconstruya el texto.
        var title: String
        /// Titanio (añadido): dominio del logo del comercio si va dentro de la app. Opcional, así que un estado
        /// antiguo sin esta clave se sigue leyendo (nil = ficha del banco).
        var logoDomain: String? = nil
        /// I-2: el ojo de la app estaba cerrado: la Live Activity dibuja máscaras («•••,•• €») y VoiceOver dice
        /// «importe oculto». Opcional: un estado viejo sin esta clave se sigue leyendo (nil = abierto, como antes).
        var hidden: Bool? = nil
        /// SEC-06: indica si había saldo configurado cuando `balanceCents` se omite con el ojo cerrado.
        var hasBalance: Bool? = nil
    }
}
