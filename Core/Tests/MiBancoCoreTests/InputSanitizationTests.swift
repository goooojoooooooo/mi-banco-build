import Foundation
import Testing
@testable import MiBancoCore

@Suite struct InputSanitizationTests {
    @Test func noticeFieldStripsControlAndFormatCharsAndCapsLength() {
        let dirty = "Has pagado\u{0000} 12,50\u{00A0}€\u{202E} en Mercadona\u{0007}\r\nSaldo: 300,00\u{202F}€\u{200B}"
        let clean = sanitizeNoticeField(dirty)
        #expect(clean == "Has pagado 12,50\u{00A0}€ en Mercadona\nSaldo: 300,00\u{202F}€")

        let huge = String(repeating: "a", count: InputLimits.noticeFieldMaxLength + 500)
        let capped = sanitizeNoticeField(huge)
        #expect(capped?.count == InputLimits.noticeFieldMaxLength)
        #expect(sanitizeNoticeField(nil) == nil)
    }

    @Test func walletAmountStripsControlsAndCapsLength() {
        let dirty = " \u{200B}12,50\u{00A0}€\u{0000}\n\u{202E} "
        #expect(sanitizeWalletAmount(dirty) == "12,50\u{00A0}€")

        let huge = String(repeating: "9", count: InputLimits.walletAmountMaxLength + 40)
        #expect(sanitizeWalletAmount(huge).count == InputLimits.walletAmountMaxLength)
    }

    @Test func merchantStripsControlsConvertsNewlinesAndCapsLength() {
        let dirty = " \u{FEFF}Café\u{0000}\nCentral\tMadrid\u{202E} "
        #expect(sanitizeMerchant(dirty) == "Café Central Madrid")

        let onlyControls = "\u{0000}\u{0007}\u{200B}\u{202E}   "
        #expect(sanitizeMerchant(onlyControls) == nil)

        let huge = String(repeating: "M", count: InputLimits.merchantMaxLength + 80)
        #expect(sanitizeMerchant(huge)?.count == InputLimits.merchantMaxLength)
        #expect(sanitizeMerchant(nil) == nil)
    }

    @Test func ledgerIngestCapsAndSanitizesWalletAndNotificationMerchants() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        var ledger = Ledger()

        let longShop = "Tienda\u{0000}\u{202E}\n" + String(repeating: "X", count: 250)
        let walletOutcome = ledger.ingest(.wallet(bank: .rev, amount: "12,50\u{00A0}€\u{0007}", merchant: longShop), now: now)
        if case .stored(let m) = walletOutcome {
            #expect((m.merchant?.count ?? 0) == InputLimits.merchantMaxLength)
            #expect(m.merchant?.contains("\u{0000}") == false)
            #expect(m.merchant?.contains("\u{202E}") == false)
            #expect(m.merchant?.contains("\n") == false)
            #expect(m.isShop == true)
        } else {
            Issue.record("Expected wallet movement to be stored")
        }

        let controlOnlyWallet = ledger.ingest(
            .wallet(bank: .ima, amount: "5,00 €", merchant: "\u{0000}\u{200B}  "),
            now: now.addingTimeInterval(300)
        )
        if case .stored(let m) = controlOnlyWallet {
            #expect(m.merchant == nil)
            #expect(m.isShop == false)
        } else {
            Issue.record("Expected second wallet movement to be stored")
        }

        let longNoticeMerchant = "Super\u{202E}" + String(repeating: "Z", count: 200)
        let noticeOutcome = ledger.ingest(
            .notification(
                bank: .tr,
                title: "Pago con tarjeta",
                subtitle: nil,
                body: "Has pagado 19,99 € en \(longNoticeMerchant)"
            ),
            now: now.addingTimeInterval(600)
        )
        if case .stored(let m) = noticeOutcome {
            #expect((m.merchant?.count ?? 0) == InputLimits.merchantMaxLength)
            #expect(m.merchant?.contains("\u{202E}") == false)
        } else {
            Issue.record("Expected notification movement to be stored")
        }
    }

    @Test func ledgerStoreUnreadStripsControlCharacters() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        var ledger = Ledger()
        let outcome = ledger.ingest(
            .notification(bank: .rev, title: "Aviso\u{0000}\u{202E}", subtitle: nil, body: "100 USD\u{0007}"),
            now: now
        )
        #expect(outcome == .unread)
        let saved = ledger.state.unread.first?.text ?? ""
        #expect(!saved.contains("\u{0000}"))
        #expect(!saved.contains("\u{202E}"))
        #expect(!saved.contains("\u{0007}"))
    }

    @Test func preservesCompoundEmojiWithZWJWhileStrippingControlsAndBidi() {
        let chef = "Café \u{1F9D1}\u{200D}\u{1F373} \u{202E}\u{FEFF}\u{200B}Madrid\u{0000}"
        #expect(sanitizeMerchant(chef) == "Café \u{1F9D1}\u{200D}\u{1F373} Madrid")

        let familyNotice = "Pago en \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} Tienda\u{202E} 12,50\u{00A0}€\u{200B}"
        #expect(sanitizeNoticeField(familyNotice) == "Pago en \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} Tienda 12,50\u{00A0}€")
    }
}
