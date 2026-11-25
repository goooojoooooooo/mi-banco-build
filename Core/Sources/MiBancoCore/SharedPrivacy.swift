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

    /// N-3: el ojo tal cual lo guarda la APP (su fuente de verdad, no la copia de la suite). Es lo que va en la carga
    /// del aviso y en la Live Activity: así carga y suite son dos señales independientes.
    public static func appEye(from truth: UserDefaults) -> Bool {
        truth.bool(forKey: key)
    }

    /// N-4: el valor nuevo de `hidden` para un estado que lleva `current`, si no coincide con el ojo de ahora; nil si
    /// ya coincide (un estado viejo sin el campo cuenta como abierto).
    public static func reconciled(current: Bool?, eyeNow: Bool) -> Bool? {
        (current ?? false) == eyeNow ? nil : eyeNow
    }

    /// Se dibujan máscaras si la carga del aviso trae el ojo cerrado O la suite compartida lo dice. Si la suite no se
    /// puede leer, manda la carga; si ninguna dice nada, cifras (como siempre).
    public static func masks(payload: Any?, shared: Bool?) -> Bool {
        (payload as? Bool ?? false) || (shared ?? false)
    }
}
