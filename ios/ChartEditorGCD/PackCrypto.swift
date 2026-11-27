import Foundation
import CryptoKit

/// Pack cifrado GCDP2 (AES-GCM). Clave ofuscada (A XOR B), igual que el APK.
enum PackCrypto {
    private static let A: [UInt8] = [
        0x91, 0x22, 0x91, 0x7C, 0x24, 0xC6, 0xA8, 0x0D, 0xE5, 0x57, 0xE8, 0x31, 0xE1, 0x49, 0xAA, 0x46,
        0x53, 0x91, 0x80, 0x51, 0x06, 0xD6, 0xB8, 0xD7, 0xC6, 0x20, 0x79, 0x96, 0xB6, 0x38, 0x04, 0xC9
    ]
    private static let B: [UInt8] = [
        0x91, 0x5E, 0xD2, 0x18, 0xA7, 0x82, 0xE6, 0xEA, 0x4E, 0xCE, 0xFD, 0x63, 0x84, 0x81, 0xD7, 0x4F,
        0xF0, 0xB8, 0xD4, 0xE6, 0xFF, 0x5D, 0xF7, 0x48, 0xD3, 0xAA, 0x69, 0x91, 0x69, 0x2D, 0xE8, 0x39
    ]
    private static let magic: [UInt8] = [0x47, 0x43, 0x44, 0x50, 0x32, 0, 0, 0] // GCDP2

    private static let lock = NSLock()
    private static var index: Index?

    private static func key() -> SymmetricKey {
        var k = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { k[i] = A[i] ^ B[i] }
        return SymmetricKey(data: Data(k))
    }

    static func decrypt(_ blob: Data) throws -> Data {
        try decryptRange(blob, off: 0, len: blob.count)
    }

    static func decryptRange(_ buf: Data, off: Int, len: Int) throws -> Data {
        guard len >= 28, off >= 0, off &+ len <= buf.count else { throw PackError.badBlob }
        let iv = buf.subdata(in: off..<(off + 12))
        let tag = buf.subdata(in: (off + len - 16)..<(off + len))
        let ct = buf.subdata(in: (off + 12)..<(off + len - 16))
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ct, tag: tag)
        return try AES.GCM.open(box, using: key())
    }

    static func openPath(_ path: String) throws -> Data {
        let ix = try loadIndex()
        if let ol = ix.map[path] {
            return try decryptRange(ix.raw, off: ix.bodyOffset + ol.off, len: ol.len)
        }
        var alt = path.removingPercentEncoding ?? path
        while alt.hasPrefix("/") { alt = String(alt.dropFirst()) }
        if let q = alt.firstIndex(of: "?") { alt = String(alt[..<q]) }
        if let h = alt.firstIndex(of: "#") { alt = String(alt[..<h]) }
        if let ol = ix.map[alt] {
            return try decryptRange(ix.raw, off: ix.bodyOffset + ol.off, len: ol.len)
        }
        if let hit = ix.lower[alt.lowercased()], let ol = ix.map[hit] {
            return try decryptRange(ix.raw, off: ix.bodyOffset + ol.off, len: ol.len)
        }
        throw PackError.missing(path)
    }

    private static func loadIndex() throws -> Index {
        lock.lock(); defer { lock.unlock() }
        if let index { return index }
        guard let url = Bundle.main.url(forResource: "g", withExtension: "dat") else {
            throw PackError.missing("g.dat")
        }
        let raw = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard raw.count >= 12 else { throw PackError.badPack }
        for i in 0..<8 where raw[i] != magic[i] { throw PackError.badPack }
        let eln = Int(raw[8]) << 24 | Int(raw[9]) << 16 | Int(raw[10]) << 8 | Int(raw[11])
        guard eln >= 28, 12 + eln <= raw.count else { throw PackError.badPack }
        let hdr = try decryptRange(raw, off: 12, len: eln)
        let count = Int(hdr[0]) << 24 | Int(hdr[1]) << 16 | Int(hdr[2]) << 8 | Int(hdr[3])
        var map: [String: OffLen] = [:]
        var lower: [String: String] = [:]
        var pos = 4
        for _ in 0..<count {
            guard pos + 2 <= hdr.count else { throw PackError.badPack }
            let pl = Int(hdr[pos]) << 8 | Int(hdr[pos + 1]); pos += 2
            guard pos + pl + 8 <= hdr.count else { throw PackError.badPack }
            let path = String(data: hdr.subdata(in: pos..<(pos + pl)), encoding: .utf8) ?? ""
            pos += pl
            let off = Int(hdr[pos]) << 24 | Int(hdr[pos + 1]) << 16 | Int(hdr[pos + 2]) << 8 | Int(hdr[pos + 3])
            let ln = Int(hdr[pos + 4]) << 24 | Int(hdr[pos + 5]) << 16 | Int(hdr[pos + 6]) << 8 | Int(hdr[pos + 7])
            pos += 8
            map[path] = OffLen(off: off, len: ln)
            lower[path.lowercased()] = path
        }
        let built = Index(map: map, lower: lower, raw: raw, bodyOffset: 12 + eln)
        index = built
        return built
    }

    struct OffLen { let off: Int; let len: Int }
    struct Index {
        let map: [String: OffLen]
        let lower: [String: String]
        let raw: Data
        let bodyOffset: Int
    }

    enum PackError: Error {
        case badBlob, badPack, missing(String)
    }
}
