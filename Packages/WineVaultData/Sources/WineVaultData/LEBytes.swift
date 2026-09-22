import Foundation

// Little-endian append/read helpers for the ZIP codec. Byte-wise reads keep
// behavior identical on big- and little-endian hosts.

extension Data {
    mutating func append(le16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(le32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    /// Unsigned little-endian integer at an absolute offset (relative to
    /// this Data's own startIndex — safe for subdata-derived views).
    private func readLEInteger(_ offset: Int, byteCount: Int) -> UInt64 {
        let absolute = startIndex + offset
        precondition(offset >= 0 && absolute + byteCount <= endIndex)
        var value: UInt64 = 0
        for shift in 0..<byteCount {
            value |= UInt64(self[absolute + shift]) << (8 * shift)
        }
        return value
    }

    func readLE16(_ offset: Int) -> UInt16 {
        UInt16(truncatingIfNeeded: readLEInteger(offset, byteCount: 2))
    }

    func readLE32(_ offset: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: readLEInteger(offset, byteCount: 4))
    }

    /// Slice with an absolute offset interpreted against this Data's own
    /// startIndex (safe even for subdata-derived views).
    func startOffset(_ offset: Int, length: Int) -> Data {
        let absolute = startIndex + offset
        return subdata(in: absolute..<absolute + length)
    }
}
