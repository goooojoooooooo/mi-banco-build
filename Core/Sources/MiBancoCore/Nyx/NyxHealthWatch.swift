import Foundation

/// Señales de salud de la app que lee la capa de iOS y entrega al motor de Nyx (nunca se consultan desde Core).
public struct NyxAppHealth: Equatable, Sendable {
    public var notificationsAllowed: Bool?
    public var appExpiresAt: Date?

    public init(notificationsAllowed: Bool? = nil, appExpiresAt: Date? = nil) {
        self.notificationsAllowed = notificationsAllowed
        self.appExpiresAt = appExpiresAt
    }
}

private let nyxStaleBankSeconds: TimeInterval = 48 * 3_600
private let nyxAppExpiryWindowSeconds: TimeInterval = 48 * 3_600
private let nyxAppExpiryUrgentSeconds: TimeInterval = 24 * 3_600
private let nyxNeverArrivedMinUseSeconds: TimeInterval = 7 * 86_400

/// Observaciones sobre la salud de la app: conexiones bancarias caducadas, a punto de caducar o sin actualizar,
/// guías obligatorias en silencio o que nunca llegaron, avisos del sistema apagados y caducidad del perfil firmado.
public func nyxHealthObservations(state: LedgerState, health: NyxAppHealth, memory: NyxMemory,
                                  now: Date, calendar: Calendar) -> [NyxObservation] {
    let ledger = Ledger(state: state)
    let startOfToday = calendar.startOfDay(for: now)
    var out: [NyxObservation] = []

    // 1. Conexiones de bancos.
    for bank in BankID.allCases {
        guard let link = state.links[bank] else { continue }
        let expired = now >= link.consentValidUntil || link.problem == .consentExpired || link.problem == .keyRejected
        if expired {
            out.append(NyxObservation(
                situation: .bankExpired,
                subject: "\(bank.rawValue)|\(nyxDayKey(link.consentValidUntil, calendar))",
                priority: .urgent,
                observedAt: now,
                facts: NyxFacts(bank: bank, day: link.consentValidUntil)))
            continue
        }

        let expiryDay = calendar.startOfDay(for: link.consentValidUntil)
        let days = calendar.dateComponents([.day], from: startOfToday, to: expiryDay).day ?? 99
        if days >= 0, days <= 10 {
            let late = days <= 3
            out.append(NyxObservation(
                situation: .bankExpiring,
                subject: "\(bank.rawValue)|\(nyxDayKey(link.consentValidUntil, calendar))|\(late ? "tarde" : "pronto")",
                priority: late ? .normal : .quiet,
                observedAt: now,
                facts: NyxFacts(bank: bank, day: link.consentValidUntil, days: days)))
        }

        let reference = link.lastSuccessAt ?? link.connectedAt
        if now.timeIntervalSince(reference) > nyxStaleBankSeconds {
            out.append(NyxObservation(
                situation: .bankStale,
                subject: "\(bank.rawValue)|\(nyxDayKey(reference, calendar))",
                priority: .quiet,
                observedAt: now,
                facts: NyxFacts(bank: bank, day: reference)))
        }
    }

    // 2. Guías de avisos obligatorias (las opcionales nunca generan observaciones).
    for track in GuideTrack.allCases where !track.isOptional {
        switch guideStatus(track, in: state, now: now, calendar: calendar) {
        case .silent(let days, let last):
            out.append(NyxObservation(
                situation: .alertsSilent,
                subject: "\(track.rawValue)|\(nyxDayKey(last, calendar))",
                priority: .quiet,
                observedAt: now,
                facts: NyxFacts(bank: track.bank, day: last, days: days, track: track.rawValue)))

        case .notYet:
            let bankUsed = ledger.balance(track.bank) != nil || state.movements.contains { $0.bank == track.bank }
            if bankUsed, let firstUse = memory.firstUseAt, now.timeIntervalSince(firstUse) >= nyxNeverArrivedMinUseSeconds {
                out.append(NyxObservation(
                    situation: .alertsNeverArrived,
                    subject: track.rawValue,
                    priority: .quiet,
                    observedAt: now,
                    facts: NyxFacts(bank: track.bank, track: track.rawValue)))
            }

        case .working:
            break
        }
    }

    // 3. Permiso de avisos del sistema apagado (solo dentro de la app).
    if health.notificationsAllowed == false {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        out.append(NyxObservation(
            situation: .notificationsOff,
            subject: nyxDayKey(weekStart, calendar),
            priority: .normal,
            observedAt: now,
            facts: NyxFacts(day: weekStart)))
    }

    // 4. Caducidad del perfil firmado (SideStore: 7 días).
    if let expires = health.appExpiresAt {
        let remaining = expires.timeIntervalSince(now)
        if remaining > 0, remaining <= nyxAppExpiryWindowSeconds {
            let late = remaining <= nyxAppExpiryUrgentSeconds
            out.append(NyxObservation(
                situation: .appExpiring,
                subject: "\(nyxDayKey(expires, calendar))|\(late ? "tarde" : "pronto")",
                priority: late ? .urgent : .normal,
                observedAt: now,
                facts: NyxFacts(day: expires)))
        }
    }

    return out.sorted { a, b in
        if a.priority != b.priority { return a.priority < b.priority }
        if a.observedAt != b.observedAt { return a.observedAt < b.observedAt }
        return a.id < b.id
    }
}

/// Fecha `ExpirationDate` del plist incrustado en `embedded.mobileprovision`, o nil si falta o no se puede leer.
public func provisioningExpiry(fromEmbeddedProfile data: Data) -> Date? {
    guard let start = data.range(of: Data("<?xml".utf8)),
          let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
          let plist = try? PropertyListSerialization.propertyList(
              from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any] else {
        return nil
    }
    return plist["ExpirationDate"] as? Date
}
