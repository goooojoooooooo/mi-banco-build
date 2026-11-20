import Foundation

public enum AuthCallbackResult: Equatable, Sendable {
    case code(String), denied, stateMismatch, malformed
}

/// Comprueba la vuelta del banco (`mibanco://cb?code=…&state=…`).
/// Esquema o host ajenos, una ruta distinta de vacía o "/", y usuario, contraseña o puerto son `.malformed`; un `state` ausente o distinto es `.stateMismatch`
/// y se mira antes que el resto, para no fiarse de nada que venga con un estado falso.
public func parseAuthCallback(_ url: URL, expectedState: String) -> AuthCallbackResult {
    guard url.scheme?.lowercased() == BankingConstants.callbackScheme,
          url.host?.lowercased() == "cb",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.path.isEmpty || components.path == "/",
          components.user == nil, components.password == nil, components.port == nil,
          let items = components.queryItems
    else { return .malformed }
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

    guard !expectedState.isEmpty, let state = value("state"),
          constantTimeEqual(state, expectedState)
    else { return .stateMismatch }
    if value("error") != nil { return .denied }
    guard let code = value("code"), !code.isEmpty else { return .malformed }
    return .code(code)
}

/// Comparación sin salida temprana por contenido.
func constantTimeEqual(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    var diff = x.count ^ y.count
    for i in 0..<max(x.count, y.count) {
        diff |= Int((i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0))
    }
    return diff == 0
}
