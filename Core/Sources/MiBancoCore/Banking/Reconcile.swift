import Foundation

public struct ReconcileReport: Equatable, Sendable {
    public var added: Int
    public var linked: Int
    public var updated: Int
    public var unchanged: Int
    public var removed: Int
    /// Filas que quien llama no pudo leer (la conciliación en sí no descarta ninguna: lo rellena el parser de extractos).
    public var ignoredRows: Int
    public var addedIDs: [UUID]
    /// De las filas añadidas (`added`), cuántas son operaciones de inversión (`excludedFromSpending`) — U46.
    public var addedInvestments: Int
    /// true si la importación añade un periodo nuevo de cobertura al libro — U47.
    public var addsPeriod: Bool
    /// true si la importación actualiza el saldo del banco con el del extracto — U47.
    public var adoptsBalance: Bool
    public var alreadyThere: Int { linked + unchanged }

    public init(added: Int = 0, linked: Int = 0, updated: Int = 0, unchanged: Int = 0, removed: Int = 0,
                ignoredRows: Int = 0, addedIDs: [UUID] = [], addedInvestments: Int = 0,
                addsPeriod: Bool = false, adoptsBalance: Bool = false) {
        self.added = added
        self.linked = linked
        self.updated = updated
        self.unchanged = unchanged
        self.removed = removed
        self.ignoredRows = ignoredRows
        self.addedIDs = addedIDs
        self.addedInvestments = addedInvestments
        self.addsPeriod = addsPeriod
        self.adoptsBalance = adoptsBalance
    }
}

private let hour: TimeInterval = 3600

extension Ledger {
    /// Mete en el libro los registros del banco (o de un extracto) sin duplicar lo que ya hay: ver la Tarea 5.
    /// Nunca toca alertas ni avisos. Enlazar NUNCA cambia el `merchant` de un movimiento existente: el nombre del
    /// banco va a `bankMerchant`.
    public mutating func reconcile(
        _ records: [BankRecord], bank: BankID, channel: RecordChannel, coverage: DateInterval?, now: Date,
        calendar: Calendar, holdPendingFlips: Bool = false
    ) -> ReconcileReport {
        var report = ReconcileReport()
        let channelSource: Movement.Source = channel == .bank ? .bank : .statement
        let batchRefs = Set(records.map(\.ref))

        func ref(of m: Movement) -> String? { channel == .bank ? m.bankRef : m.statementRef }
        func setRef(_ value: String?, on i: Int) {
            if channel == .bank { state.movements[i].bankRef = value } else { state.movements[i].statementRef = value }
        }
        /// Pone el nombre del banco donde corresponde; devuelve si algo cambió.
        func applyName(_ name: String?, to i: Int) -> Bool {
            guard let name, !name.isEmpty else { return false }
            if state.movements[i].source == channelSource {
                guard state.movements[i].merchant != name else { return false }
                setMerchantKeepingCategory(name, at: i)
            } else if state.movements[i].source.isBankSourced {
                return false
            } else {
                guard state.movements[i].bankMerchant != name else { return false }
                state.movements[i].bankMerchant = name
            }
            return true
        }

        for r in records where r.bank == bank {
            // 1. La misma clave ya está en un movimiento (o la que daba una versión anterior de la app a esta misma fila de
            // extracto: se pasa a la clave nueva y no se duplica).
            let sameKey = state.movements.firstIndex(where: { $0.bank == bank && ref(of: $0) == r.ref })
            let oldKey = r.legacyRefs.isEmpty ? nil : state.movements.firstIndex(where: {
                $0.bank == bank && ref(of: $0).map { r.legacyRefs.contains($0) } == true
            })
            if let i = sameKey ?? oldKey {
                if sameKey == nil { setRef(r.ref, on: i) }
                var changed = false
                // `holdPendingFlips`: sin una lectura de saldo nueva, un pendiente no pasa a apuntado (dejaría de sumar).
                let holdsFlip = holdPendingFlips && state.movements[i].bankStatus == .pending && r.status == .booked
                if channel == .bank, !holdsFlip, state.movements[i].bankStatus != r.status {
                    state.movements[i].bankStatus = r.status
                    changed = true
                }
                // El día en que se apuntó (R54), en cuanto el registro llega apuntado.
                if channel == .bank, !holdsFlip, let day = r.bookedDay, state.movements[i].bookedDay != day {
                    state.movements[i].bookedDay = day
                    changed = true
                }
                if applyName(r.merchant, to: i) { changed = true }
                // La señal de persona y el MCC solo se añaden/conservan (como `isShop`); no cuentan como cambio en el informe.
                if r.personPayment { state.movements[i].personPayment = true }
                if let mcc = r.merchantCategoryCode { state.movements[i].merchantCategoryCode = mcc }
                if changed { report.updated += 1 } else { report.unchanged += 1 }
                continue
            }

            // 2. Un pendiente que ahora llega apuntado con otra clave: se cambia en el sitio.
            if channel == .bank, r.status == .booked,
               let i = best(records: r, calendar: calendar, among: { m in
                   m.bankStatus == .pending && m.bankRef != nil && m.bankRef != r.ref && !batchRefs.contains(m.bankRef ?? "")
               }) {
                // Sin lectura nueva el apunte no se aplica (ni se cuenta como nada): lo hará la siguiente consulta.
                if holdPendingFlips { continue }
                state.movements[i].bankRef = r.ref
                state.movements[i].bankStatus = .booked
                state.movements[i].bookedDay = r.bookedDay
                _ = applyName(r.merchant, to: i)
                if r.personPayment { state.movements[i].personPayment = true }
                if let mcc = r.merchantCategoryCode { state.movements[i].merchantCategoryCode = mcc }
                report.updated += 1
                continue
            }

            // 3. Un movimiento de otra fuente sin clave de este canal, del mismo banco e importe y dentro de la ventana.
            if let i = best(records: r, calendar: calendar, among: { m in
                ref(of: m) == nil && m.source != channelSource
            }) {
                setRef(r.ref, on: i)
                if channel == .bank {
                    state.movements[i].bankStatus = r.status
                    state.movements[i].linkedAt = now
                    state.movements[i].bookedDay = r.bookedDay
                } else if state.movements[i].bankStatus == nil {
                    state.movements[i].bankStatus = .booked
                }
                // El nombre del banco va aparte: `merchant` alimenta categorías, silenciados y suscripciones.
                if state.movements[i].source.isBankSourced == false, let name = r.merchant, !name.isEmpty {
                    state.movements[i].bankMerchant = name
                }
                // Un nombre que solo se parece a una marca no le quita la señal a un aviso de Bizum (M-10).
                if !(r.shopFromName && state.movements[i].personPayment == true) {
                    state.movements[i].isShop = state.movements[i].isShop || r.isShop
                }
                if r.personPayment { state.movements[i].personPayment = true }
                if let mcc = r.merchantCategoryCode, state.movements[i].merchantCategoryCode == nil || channel == .bank {
                    state.movements[i].merchantCategoryCode = mcc
                }
                state.movements[i].excludedFromSpending = state.movements[i].excludedFromSpending || r.excludedFromSpending
                report.linked += 1
                continue
            }

            // 4. Nada que enlazar: movimiento nuevo.
            let movement = Movement(
                bank: bank, amountCents: r.amountCents, merchant: r.merchant, kind: r.amountCents < 0 ? .payment : .income,
                source: channelSource, date: r.timing.date, isShop: r.isShop,
                bankRef: channel == .bank ? r.ref : nil, statementRef: channel == .statement ? r.ref : nil,
                bankStatus: channel == .bank ? r.status : .booked, importedAt: now, dayOnly: !r.timing.isExact,
                excludedFromSpending: r.excludedFromSpending, firstSeenStatus: channel == .bank ? r.status : nil,
                bookedDay: channel == .bank ? r.bookedDay : nil, personPayment: r.personPayment ? true : nil,
                merchantCategoryCode: r.merchantCategoryCode)
            state.movements.append(movement)
            report.added += 1
            if r.excludedFromSpending { report.addedInvestments += 1 }
            report.addedIDs.append(movement.id)
        }

        // Pendientes que el banco ya no devuelve (solo con cobertura y solo del canal del banco): los de dentro de lo
        // consultado y los atascados (más de `SyncPolicy.pendingReachDays` días, R52), que la ventana ya no alcanza.
        if channel == .bank, let coverage {
            let vanished = state.movements.indices.filter { i in
                let m = state.movements[i]
                return m.bank == bank && m.bankStatus == .pending && m.bankRef != nil
                    && !batchRefs.contains(m.bankRef ?? "")
                    && (coverage.contains(m.date) || Ledger.isStuckPending(m.date, now: now, calendar: calendar))
            }
            var toDelete = Set<UUID>()
            for i in vanished {
                if state.movements[i].source == .bank {
                    toDelete.insert(state.movements[i].id)
                } else {
                    state.movements[i].bankRef = nil
                    state.movements[i].bankStatus = nil
                    state.movements[i].linkedAt = nil
                    state.movements[i].bookedDay = nil
                    // Si el mismo pago ya llegó apuntado como fila propia del banco, se funden en UN movimiento.
                    if let j = foldCandidate(for: state.movements[i], excluding: toDelete, batchRefs: batchRefs, calendar: calendar) {
                        let row = state.movements[j]
                        state.movements[i].bankRef = row.bankRef
                        state.movements[i].bankStatus = row.bankStatus
                        state.movements[i].linkedAt = now
                        state.movements[i].bookedDay = row.bookedDay
                        if state.movements[i].statementRef == nil { state.movements[i].statementRef = row.statementRef }
                        if let name = row.merchant, !name.isEmpty { state.movements[i].bankMerchant = name }
                        state.movements[i].isShop = state.movements[i].isShop || row.isShop
                        if row.personPayment == true { state.movements[i].personPayment = true }
                        if let mcc = row.merchantCategoryCode { state.movements[i].merchantCategoryCode = mcc }
                        state.movements[i].excludedFromSpending =
                            state.movements[i].excludedFromSpending || row.excludedFromSpending
                        toDelete.insert(row.id)
                    }
                }
            }
            if !toDelete.isEmpty {
                state.movements.removeAll { toDelete.contains($0.id) }
                report.removed = toDelete.count
            }
        }
        return report
    }

    /// Capturados (aviso o Cartera) que el banco debería haber confirmado ya y no lo han hecho. Dos fuentes de cobertura:
    /// - Banco conectado: más de 7 días antes de la última consulta con éxito, y no antes del primer movimiento con clave
    ///   del banco (ahí empieza lo que se ve).
    /// - Extractos importados (también de un banco sin conexión): los periodos guardados en `statementCoverage`, uno por
    ///   importación (R38); un día cuenta solo dentro de uno de ellos, así que el hueco entre dos extractos no está
    ///   cubierto, y el día en que se importó tampoco. Dentro de un periodo, más de 7 días antes de `now`.
    /// Comparación por día de Madrid (las filas de solo día se guardan a mediodía).
    public func unconfirmedCaptures(bank: BankID, now: Date) -> Set<UUID> {
        func unlinkedCapture(_ m: Movement) -> Bool {
            m.bank == bank && !m.source.isBankSourced && m.bankRef == nil && m.statementRef == nil
        }
        var ids = Set<UUID>()
        if let last = state.links[bank]?.lastSuccessAt {
            let cutoff = last.addingTimeInterval(-7 * 86_400)
            let linked = state.movements.filter { $0.bank == bank && $0.bankRef != nil }
            if let earliest = linked.map(\.date).min() {
                let firstDay = madridCalendar.startOfDay(for: earliest)
                ids.formUnion(state.movements.filter { m in
                    unlinkedCapture(m) && m.date <= cutoff && madridCalendar.startOfDay(for: m.date) >= firstDay
                }.map(\.id))
            }
        }
        if let intervals = state.statementCoverage[bank], !intervals.isEmpty {
            let cutoff = now.addingTimeInterval(-7 * 86_400)
            ids.formUnion(state.movements.filter { m in
                unlinkedCapture(m) && m.date <= cutoff && intervals.contains { m.date >= $0.start && m.date < $0.end }
            }.map(\.id))
        }
        return ids
    }

    /// Fila propia del banco (apuntada, sin enlazar a nada) que es el mismo pago que un capturado que acaba de perder
    /// su pendiente: mismo banco e importe, con el día del banco entre 1 día antes y 5 días después del capturado.
    /// Gana la de menor distancia en días y luego en tiempo. Solo vale una fila cuya clave viene en el lote que se está
    /// conciliando: un apuntado de otra consulta no es la pareja de este pendiente.
    private func foldCandidate(for capture: Movement, excluding deleted: Set<UUID>, batchRefs: Set<String>,
                               calendar: Calendar) -> Int? {
        let day = calendar.startOfDay(for: capture.date)
        var winner: (index: Int, days: Int, seconds: TimeInterval)?
        for (j, row) in state.movements.enumerated() {
            guard row.source == .bank, row.bankStatus == .booked, let rowRef = row.bankRef, batchRefs.contains(rowRef),
                  row.bank == capture.bank, row.amountCents == capture.amountCents, !deleted.contains(row.id) else { continue }
            let diff = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: row.date)).day ?? Int.max
            guard (-1...5).contains(diff) else { continue }
            let seconds = abs(row.date.timeIntervalSince(capture.date))
            if winner == nil || (abs(diff), seconds) < (winner!.days, winner!.seconds) { winner = (j, abs(diff), seconds) }
        }
        return winner?.index
    }

    /// El mejor movimiento para el registro: mismo banco e importe, dentro de la ventana, el de menor distancia en
    /// días, luego en tiempo, luego el más antiguo.
    private func best(records r: BankRecord, calendar: Calendar, among extra: (Movement) -> Bool) -> Int? {
        var winner: (index: Int, days: Int, seconds: TimeInterval, date: Date)?
        for (i, m) in state.movements.enumerated() {
            guard m.bank == r.bank, m.amountCents == r.amountCents, extra(m),
                  let d = windowDistance(m, r, calendar: calendar) else { continue }
            let better: Bool
            if let w = winner {
                better = (d.days, d.seconds, m.date) < (w.days, w.seconds, w.date)
            } else {
                better = true
            }
            if better { winner = (i, d.days, d.seconds, m.date) }
        }
        return winner?.index
    }

    /// nil si el movimiento queda fuera de la ventana del registro. Los días se miran por inicio de día de Madrid.
    private func windowDistance(_ m: Movement, _ r: BankRecord, calendar: Calendar) -> (days: Int, seconds: TimeInterval)? {
        let seconds = abs(m.date.timeIntervalSince(r.timing.date))
        let target = r.timing.date
        // Días de calendario desde el día del registro hasta el del movimiento.
        let diff = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: target), to: calendar.startOfDay(for: m.date)).day ?? Int.max
        switch r.timing {
        case .exact:
            guard seconds <= 36 * hour else { return nil }
            return (abs(diff), seconds)
        case .transactionDay:
            // Día del pago ± 1 (algunos bancos dan como `transaction_date` el día en que se liquida): gana el más cercano.
            guard abs(diff) <= 1 else { return nil }
            return (abs(diff), seconds)
        case .bookingDay:
            guard (-5...1).contains(diff) else { return nil }
            return (abs(diff), seconds)
        }
    }
}
