import Foundation
import Testing
@testable import MiBancoCore

/// Construye un TLV DER (forma corta o larga).
private func der(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
    let n = content.count
    if n < 128 { return [tag, UInt8(n)] + content }
    if n < 256 { return [tag, 0x81, UInt8(n)] + content }
    return [tag, 0x82, UInt8(n >> 8), UInt8(n & 0xff)] + content
}

private let rsaOID: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]
private let ecOID: [UInt8] = [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]
private let inner: [UInt8] = [0x30, 0x03, 0x02, 0x01, 0x00]

private func pkcs8(oid: [UInt8] = rsaOID, key: [UInt8] = inner) -> [UInt8] {
    der(0x30, [0x02, 0x01, 0x00] + der(0x30, oid + [0x05, 0x00]) + der(0x04, key))
}

/// Las cabeceras se montan por concatenación: ningún bloque PEM literal en el repositorio.
private func pem(label: String, _ bytes: [UInt8], wrap: Int = 64, eol: String = "\n") -> String {
    let b64 = Array(Data(bytes).base64EncodedString())
    var lines: [String] = []
    var i = 0
    while i < b64.count {
        let j = min(i + wrap, b64.count)
        lines.append(String(b64[i..<j]))
        i = j
    }
    return (["-----BEGIN " + label + "-----"] + lines + ["-----END " + label + "-----"])
        .joined(separator: eol) + eol
}

@Suite struct PrivateKeyPEMTests {
    @Test func pkcs8GivesInnerPKCS1() throws {
        let text = pem(label: "PRIVATE KEY", pkcs8())
        #expect(try rsaPKCS1DER(fromPEM: text) == Data(inner))
    }

    @Test func rsaPrivateKeyHeaderIsReturnedUnchanged() throws {
        let text = pem(label: "RSA PRIVATE KEY", inner)
        #expect(try rsaPKCS1DER(fromPEM: text) == Data(inner))
    }

    @Test func longFormLengthsParse() throws {
        let big = der(0x30, [UInt8](repeating: 0, count: 300))
        let text = pem(label: "PRIVATE KEY", pkcs8(key: big))
        #expect(try rsaPKCS1DER(fromPEM: text) == Data(big))
    }

    @Test func publicKeyIsRejected() {
        let text = pem(label: "PUBLIC KEY", pkcs8())
        #expect(throws: PrivateKeyPEMError.publicKeyGiven) { try rsaPKCS1DER(fromPEM: text) }
    }

    @Test func encryptedKeyIsRejected() {
        let text = pem(label: "ENCRYPTED PRIVATE KEY", pkcs8())
        #expect(throws: PrivateKeyPEMError.encrypted) { try rsaPKCS1DER(fromPEM: text) }
    }

    @Test func ecKeyIsNotRSA() {
        let text = pem(label: "PRIVATE KEY", pkcs8(oid: ecOID))
        #expect(throws: PrivateKeyPEMError.notRSA) { try rsaPKCS1DER(fromPEM: text) }
    }

    @Test func plainTextIsNotPEM() {
        #expect(throws: PrivateKeyPEMError.notPEM) { try rsaPKCS1DER(fromPEM: "hola") }
        #expect(throws: PrivateKeyPEMError.notPEM) { try rsaPKCS1DER(fromPEM: "") }
    }

    @Test func truncatedDERIsMalformed() {
        let bytes = pkcs8()
        let text = pem(label: "PRIVATE KEY", Array(bytes.dropLast(3)))
        #expect(throws: PrivateKeyPEMError.malformedDER) { try rsaPKCS1DER(fromPEM: text) }
    }

    @Test func badBase64IsMalformed() {
        let text = "-----BEGIN " + "PRIVATE KEY-----\n@@@@\n-----END " + "PRIVATE KEY-----\n"
        #expect(throws: PrivateKeyPEMError.malformedDER) { try rsaPKCS1DER(fromPEM: text) }
    }

    @Test func missingEndLineIsNotPEM() {
        let text = "-----BEGIN " + "PRIVATE KEY-----\nAAAA\n"
        #expect(throws: PrivateKeyPEMError.notPEM) { try rsaPKCS1DER(fromPEM: text) }
    }

    @Test func wrapAndLineEndingsDoNotMatter() throws {
        let bytes = pkcs8(key: der(0x30, [UInt8](repeating: 7, count: 150)))
        let expected = try rsaPKCS1DER(fromPEM: pem(label: "PRIVATE KEY", bytes, wrap: 64))
        #expect(try rsaPKCS1DER(fromPEM: pem(label: "PRIVATE KEY", bytes, wrap: 64, eol: "\r\n")) == expected)
        #expect(try rsaPKCS1DER(fromPEM: pem(label: "PRIVATE KEY", bytes, wrap: 76)) == expected)
        #expect(try rsaPKCS1DER(fromPEM: "\n  " + pem(label: "PRIVATE KEY", bytes) + "\n\n") == expected)
    }

    @Test func applicationIDFromFileName() {
        #expect(applicationID(fromKeyFileName: "AA7C1F9E-1B2C-4D3E-8F90-0123456789AB.pem")
            == "aa7c1f9e-1b2c-4d3e-8f90-0123456789ab")
        #expect(applicationID(fromKeyFileName: "clave.pem") == nil)
        #expect(applicationID(fromKeyFileName: "aa7c1f9e-1b2c-4d3e-8f90-0123456789ab (1).pem")
            == "aa7c1f9e-1b2c-4d3e-8f90-0123456789ab")
        #expect(applicationID(fromKeyFileName: "") == nil)
    }

    @Test func applicationIDShape() {
        #expect(isValidApplicationID("aa7c1f9e-1b2c-4d3e-8f90-0123456789ab"))
        #expect(isValidApplicationID("AA7C1F9E-1B2C-4D3E-8F90-0123456789AB"))
        #expect(!isValidApplicationID("aa7c1f9e1b2c4d3e8f900123456789ab"))
        #expect(!isValidApplicationID("zz7c1f9e-1b2c-4d3e-8f90-0123456789ab"))
        #expect(!isValidApplicationID(""))
    }
}
