import Foundation

/// CRC-32 (IEEE 802.3 polynomial) used by ZIP local/central headers.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var entry = UInt32(value)
        for _ in 0..<8 {
            entry = (entry & 1) != 0 ? 0xEDB8_8320 ^ (entry >> 1) : entry >> 1
        }
        return entry
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Pure-Swift SHA-256 (FIPS 180-4) used for backup manifest checksums.
enum SHA256 {
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hexDigest(_ data: Data) -> String {
        digest(data).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ data: Data) -> [UInt8] {
        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        for chunk in paddedChunks(of: data) {
            hash = compress(chunk: chunk, into: hash)
        }
        return hash.flatMap { value in
            [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF),
            ]
        }
    }

    /// FIPS padding: 0x80, zero-fill to 56 mod 64, then 64-bit big-endian
    /// bit length; split into 64-byte blocks.
    private static func paddedChunks(of data: Data) -> [[UInt8]] {
        var bytes = [UInt8](data)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }
        return stride(from: 0, to: bytes.count, by: 64).map { start in
            Array(bytes[start..<start + 64])
        }
    }

    private static func messageSchedule(_ chunk: [UInt8]) -> [UInt32] {
        var schedule = [UInt32](repeating: 0, count: 64)
        for index in 0..<16 {
            let offset = index * 4
            schedule[index] = (UInt32(chunk[offset]) << 24)
                | (UInt32(chunk[offset + 1]) << 16)
                | (UInt32(chunk[offset + 2]) << 8)
                | UInt32(chunk[offset + 3])
        }
        for index in 16..<64 {
            let previous15 = schedule[index - 15]
            let previous2 = schedule[index - 2]
            let sigma0 = rotateRight(previous15, 7) ^ rotateRight(previous15, 18)
                ^ (previous15 >> 3)
            let sigma1 = rotateRight(previous2, 17) ^ rotateRight(previous2, 19)
                ^ (previous2 >> 10)
            schedule[index] = schedule[index - 16] &+ sigma0 &+ schedule[index - 7] &+ sigma1
        }
        return schedule
    }

    private static func compress(chunk: [UInt8], into hash: [UInt32]) -> [UInt32] {
        let schedule = messageSchedule(chunk)
        var w0 = hash[0]
        var w1 = hash[1]
        var w2 = hash[2]
        var w3 = hash[3]
        var w4 = hash[4]
        var w5 = hash[5]
        var w6 = hash[6]
        var w7 = hash[7]

        for round in 0..<64 {
            let bigSigma1 = rotateRight(w4, 6) ^ rotateRight(w4, 11) ^ rotateRight(w4, 25)
            let choice = (w4 & w5) ^ (~w4 & w6)
            let temp1 = w7 &+ bigSigma1 &+ choice &+ constants[round] &+ schedule[round]
            let bigSigma0 = rotateRight(w0, 2) ^ rotateRight(w0, 13) ^ rotateRight(w0, 22)
            let majority = (w0 & w1) ^ (w0 & w2) ^ (w1 & w2)
            let temp2 = bigSigma0 &+ majority
            w7 = w6
            w6 = w5
            w5 = w4
            w4 = w3 &+ temp1
            w3 = w2
            w2 = w1
            w1 = w0
            w0 = temp1 &+ temp2
        }

        return [
            hash[0] &+ w0, hash[1] &+ w1, hash[2] &+ w2, hash[3] &+ w3,
            hash[4] &+ w4, hash[5] &+ w5, hash[6] &+ w6, hash[7] &+ w7,
        ]
    }

    private static func rotateRight(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
