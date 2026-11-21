import Foundation

public enum PrivateKeyPEMError: Error, Equatable {
    case notPEM, publicKeyGiven, encrypted, notRSA, malformedDER
}

/// Extrae la clave RSA en PKCS#1 DER de un PEM (PKCS#8 "PRIVATE KEY" o PKCS#1 "RSA PRIVATE KEY").
public func rsaPKCS1DER(fromPEM pem: String) throws -> Data {
    let beginMark = "-----BEGIN "
    let endMark = "-----"
    let lines = pem.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    guard let beginIndex = lines.firstIndex(where: { $0.hasPrefix(beginMark) && $0.hasSuffix(endMark) && $0.count > beginMark.count + endMark.count })
    else { throw PrivateKeyPEMError.notPEM }
    let begin = lines[beginIndex]
    let label = String(begin.dropFirst(beginMark.count).dropLast(endMark.count))
    guard let endIndex = lines[(beginIndex + 1)...].firstIndex(where: { $0 == "-----END " + label + "-----" })
    else { throw PrivateKeyPEMError.notPEM }

    switch label {
    case "PUBLIC KEY", "RSA PUBLIC KEY": throw PrivateKeyPEMError.publicKeyGiven
    case "ENCRYPTED PRIVATE KEY": throw PrivateKeyPEMError.encrypted
    case "PRIVATE KEY", "RSA PRIVATE KEY": break
    default: throw PrivateKeyPEMError.notPEM
    }

    let bodyLines = lines[(beginIndex + 1)..<endIndex]
    // PKCS#1 cifrado a la antigua: cabeceras "Proc-Type: 4,ENCRYPTED" dentro del bloque.
    if bodyLines.contains(where: { $0.hasPrefix("Proc-Type:") && $0.contains("ENCRYPTED") }) {
        throw PrivateKeyPEMError.encrypted
    }
    let base64 = bodyLines.filter { !$0.contains(":") }.joined()
    guard !base64.isEmpty, let der = Data(base64Encoded: base64) else { throw PrivateKeyPEMError.malformedDER }
    let bytes = [UInt8](der)

    if label == "RSA PRIVATE KEY" {
        var reader = DERReader(bytes)
        _ = try reader.readExpecting(tag: 0x30)
        guard reader.isAtEnd else { throw PrivateKeyPEMError.malformedDER }
        return der
    }

    // PKCS#8: SEQUENCE { INTEGER version, SEQUENCE { OID, params }, OCTET STRING key }
    var outer = DERReader(bytes)
    var body = DERReader(try outer.readExpecting(tag: 0x30))
    guard outer.isAtEnd else { throw PrivateKeyPEMError.malformedDER }
    _ = try body.readExpecting(tag: 0x02)
    var algorithm = DERReader(try body.readExpecting(tag: 0x30))
    let oid = try algorithm.readExpecting(tag: 0x06)
    let rsaOID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]
    guard oid == rsaOID else { throw PrivateKeyPEMError.notRSA }
    let key = try body.readExpecting(tag: 0x04)
    var check = DERReader(key)
    _ = try check.readExpecting(tag: 0x30)
    guard check.isAtEnd else { throw PrivateKeyPEMError.malformedDER }
    return Data(key)
}

/// Lector DER mínimo: etiqueta de un byte y longitud corta o larga (hasta 4 bytes).
private struct DERReader {
    let bytes: [UInt8]
    var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { position == bytes.count }

    mutating func readExpecting(tag expected: UInt8) throws -> [UInt8] {
        guard position < bytes.count, bytes[position] == expected else { throw PrivateKeyPEMError.malformedDER }
        position += 1
        guard position < bytes.count else { throw PrivateKeyPEMError.malformedDER }
        let first = bytes[position]
        position += 1
        var length = 0
        if first < 0x80 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7f)
            guard count >= 1, count <= 4, position + count <= bytes.count else { throw PrivateKeyPEMError.malformedDER }
            for _ in 0..<count {
                length = length << 8 | Int(bytes[position])
                position += 1
            }
        }
        guard length <= bytes.count - position else { throw PrivateKeyPEMError.malformedDER }
        defer { position += length }
        return Array(bytes[position..<(position + length)])
    }
}

/// "AA7C...-....pem" (también "... (1).pem" de un navegador) -> id en minúsculas.
public func applicationID(fromKeyFileName name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 36 else { return nil }
    let candidate = String(trimmed.prefix(36))
    guard isValidApplicationID(candidate) else { return nil }
    return candidate.lowercased()
}

/// Forma de UUID, sin distinguir mayúsculas: 36 caracteres.
public func isValidApplicationID(_ s: String) -> Bool {
    let bytes = Array(s.utf8)
    guard bytes.count == 36 else { return false }
    for (i, b) in bytes.enumerated() {
        if [8, 13, 18, 23].contains(i) {
            if b != UInt8(ascii: "-") { return false }
        } else {
            let isHex = (b >= 48 && b <= 57) || (b >= 65 && b <= 70) || (b >= 97 && b <= 102)
            if !isHex { return false }
        }
    }
    return true
}
