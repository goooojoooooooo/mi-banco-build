import Foundation

/// El ojo de la app (modo privado) compartido con la extensión de avisos y la Live Activity, que no ven las preferencias
/// de la app. La fuente de verdad sigue siendo la de la app (`AppPreferences`); esto es una copia en el `UserDefaults`
/// del grupo de apps que ya existe, con la misma clave `privateMode`.
public enum SharedPrivacy {
    /// La clave en la suite del grupo y en la carga de un aviso.
    public static let key = "privateMode"

    /// La suite del grupo de apps (la misma que resuelve el almacén compartido).
    public static func suite(infoDictionary: [String: Any]?) -> UserDefaults? {
        UserDefaults(suiteName: resolveAppGroupID(infoDictionary: infoDictionary ?? [:]))
    }

    /// Escribe el ojo en la suite compartida (al cambiar y al arrancar la app). Sin suite, no hace nada.
    public static func publish(_ hidden: Bool, to defaults: UserDefaults?) {
        defaults?.set(hidden, forKey: key)
    }

    /// Lo que dice la suite compartida; nil si no se puede leer o nunca se escribió.
    public static func read(from defaults: UserDefaults?) -> Bool? {
        guard let defaults, defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    /// Se dibujan máscaras si la carga del aviso trae el ojo cerrado O la suite compartida lo dice. Si la suite no se
    /// puede leer, manda la carga; si ninguna dice nada, cifras (como siempre).
    public static func masks(payload: Any?, shared: Bool?) -> Bool {
        (payload as? Bool ?? false) || (shared ?? false)
    }
}
