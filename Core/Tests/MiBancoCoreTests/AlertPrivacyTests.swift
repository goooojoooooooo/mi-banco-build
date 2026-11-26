import Foundation
import Testing
@testable import MiBancoCore

@Suite struct AlertPrivacyTests {
    private func sampleMovement(amountCents: Int = -1250, kind: MovementKind = .payment, merchant: String? = "Mercadona") -> Movement {
        Movement(
            bank: .rev,
            amountCents: amountCents,
            merchant: merchant,
            kind: kind,
            source: .notification,
            date: Date(timeIntervalSince1970: 1_795_000_000),
            isShop: kind == .payment
        )
    }

    // MARK: SEC-06(a) — userInfo sin cifras con el ojo cerrado

    @Test func movementUserInfoOmitsAllMoneyWhenEyeClosed() {
        let movement = sampleMovement(amountCents: -4590, kind: .payment, merchant: "Mercadona")
        let month = MerchantHistory(countThisMonth: 3, totalThisMonthCents: 12_345, lastVisit: nil)
        let info = movementNotificationUserInfo(
            movement: movement,
            balances: ["rev": 32_770, "ima": 100_000],
            previousBalance: 37_360,
            estimated: true,
            merchantMonth: month,
            todaySpentCents: 4590,
            hidden: true
        )

        #expect(info["amountCents"] == nil)
        #expect(info["balances"] == nil)
        #expect(info["previousBalance"] == nil)
        #expect(info["monthCents"] == nil)
        #expect(info["todaySpent"] == nil)

        #expect(info["bank"] as? String == "rev")
        #expect(info["merchant"] as? String == "Mercadona")
        #expect(info["isShop"] as? Bool == true)
        #expect(info["estimated"] as? Bool == true)
        #expect(info["isIncome"] as? Bool == false)
        #expect(info["isNegative"] as? Bool == true)
        #expect(info["hasBalance"] as? Bool == true)
        #expect(info["monthCount"] as? Int == 3)
        #expect(info["hasTodaySpent"] as? Bool == true)
        #expect(info[SharedPrivacy.key] as? Bool == true)
        #expect(info["route"] as? String == "movement")
        #expect(info["movementID"] as? String == movement.id.uuidString)
    }

    @Test func movementUserInfoKeepsExactMoneyWhenEyeOpen() {
        let movement = sampleMovement(amountCents: 3500, kind: .income, merchant: "Nómina")
        let month = MerchantHistory(countThisMonth: 2, totalThisMonthCents: 7000, lastVisit: nil)
        let info = movementNotificationUserInfo(
            movement: movement,
            balances: ["rev": 80_000],
            previousBalance: 76_500,
            estimated: false,
            merchantMonth: month,
            todaySpentCents: 0,
            hidden: false
        )

        #expect(info["amountCents"] as? Int == 3500)
        #expect(info["balances"] as? [String: Int] == ["rev": 80_000])
        #expect(info["previousBalance"] as? Int == 76_500)
        #expect(info["monthCount"] as? Int == 2)
        #expect(info["monthCents"] as? Int == 7000)
        #expect(info["todaySpent"] as? Int == 0)
        #expect(info[SharedPrivacy.key] as? Bool == false)
        #expect(info["hasBalance"] == nil)
        #expect(info["hasTodaySpent"] == nil)
        #expect(info["isIncome"] == nil)
        #expect(info["isNegative"] == nil)
    }

    @Test func movementUserInfoClosedEyeWithoutBalanceOrTodaySpent() {
        let movement = sampleMovement(amountCents: 2000, kind: .income, merchant: nil)
        let info = movementNotificationUserInfo(
            movement: movement,
            balances: [:],
            previousBalance: nil,
            estimated: false,
            merchantMonth: nil,
            todaySpentCents: nil,
            hidden: true
        )

        #expect(info["hasBalance"] as? Bool == false)
        #expect(info["hasTodaySpent"] as? Bool == false)
        #expect(info["isIncome"] as? Bool == true)
        #expect(info["isNegative"] as? Bool == false)
        #expect(info["monthCount"] == nil)
    }

    // MARK: SEC-06(a) — Live Activity sin cifras con el ojo cerrado

    @Test func liveActivityMoneyFieldsStrippedWhenHiddenAndPreservedWhenOpen() {
        let hidden = LiveActivityMoneyFields.composed(balance: 32_770, amountCents: -1250, total: 90_000, hidden: true)
        #expect(hidden.balanceCents == nil)
        #expect(hidden.lastAmountCents == nil)
        #expect(hidden.totalCents == nil)
        #expect(hidden.hasBalance == true)

        let hiddenNoBalance = LiveActivityMoneyFields.composed(balance: nil, amountCents: -1250, total: nil, hidden: true)
        #expect(hiddenNoBalance.hasBalance == false)

        let open = LiveActivityMoneyFields.composed(balance: 32_770, amountCents: -1250, total: 90_000, hidden: false)
        #expect(open.balanceCents == 32_770)
        #expect(open.lastAmountCents == -1250)
        #expect(open.totalCents == 90_000)
        #expect(open.hasBalance == nil)
    }

    @Test func liveActivityRedactionClearsExistingMoneyButPreservesBalancePresence() {
        let redacted = LiveActivityMoneyFields.redactedForClosedEye(balanceCents: 50_000, hasBalance: nil)
        #expect(redacted.balanceCents == nil)
        #expect(redacted.lastAmountCents == nil)
        #expect(redacted.totalCents == nil)
        #expect(redacted.hasBalance == true)

        let redactedEmpty = LiveActivityMoneyFields.redactedForClosedEye(balanceCents: nil, hasBalance: false)
        #expect(redactedEmpty.hasBalance == false)
    }

    // MARK: SEC-06(c) — Retirada de avisos entregados con cifras al cerrar el ojo

    @Test func removesOnlyDeliveredMovementAndInsightNotifications() {
        let delivered = [
            DeliveredAlertDescriptor(identifier: "mov-1", categoryIdentifier: "MOVEMENT"),
            DeliveredAlertDescriptor(identifier: "ins-1", categoryIdentifier: "INSIGHT"),
            DeliveredAlertDescriptor(identifier: "briefing-morning-0", categoryIdentifier: "BRIEFING"),
            DeliveredAlertDescriptor(identifier: "bank-consent-rev", categoryIdentifier: "BANK_CONSENT"),
            DeliveredAlertDescriptor(identifier: "unread-1", categoryIdentifier: ""),
            DeliveredAlertDescriptor(identifier: "mov-2", categoryIdentifier: "MOVEMENT"),
        ]

        let toRemove = deliveredAlertIdentifiersToRemoveForPrivacy(delivered)
        #expect(toRemove == ["mov-1", "ins-1", "mov-2"])
    }

    @Test func returnsEmptyWhenOnlyNonSensitiveNotificationsAreDelivered() {
        let delivered = [
            DeliveredAlertDescriptor(identifier: "briefing-morning-0", categoryIdentifier: "BRIEFING"),
            DeliveredAlertDescriptor(identifier: "bank-consent-ima", categoryIdentifier: "BANK_CONSENT"),
            DeliveredAlertDescriptor(identifier: "unread-2", categoryIdentifier: ""),
        ]
        #expect(deliveredAlertIdentifiersToRemoveForPrivacy(delivered).isEmpty)
    }
}
