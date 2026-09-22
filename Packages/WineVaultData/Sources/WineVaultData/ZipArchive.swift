import Foundation

/// Minimal ZIP codec (store method only) for vault backups.
///
/// Emits only what Apple's Archive Utility, macOS Finder, and Python's
/// `zipfile` require: local file headers, a central directory, and an
/// EOCD record, with CRC-32 checksums and no zip64. Entry names must be
/// pre-validated relative POSIX paths. Extraction refuses absolute paths,
/// parent traversal, and symlinks (zip-slip defense).

enum ZipError: Error, Equatable, Sendable {
    case malformed
    case encryptedEntry(String)
    case unsupportedCompression(String)
    case checksumMismatch(String)
    case unsafeEntryPath(String)
    case entryTooLarge(String)
    case duplicateEntry(String)
}

struct ZipEntry: Equatable, Sendable {
    let name: String
    let data: Data
    let modificationDate: Date
}

enum ZipArchive {
    /// Total uncompressed size cap applied while reading an archive, so a
    /// hostile ZIP cannot exhaust device storage during extraction.
    static let maxTotalUncompressedBytes = 512 * 1024 * 1024

    // MARK: - Building

    static func build(entries: [ZipEntry]) -> Data {
        var archive = Data()
        var centralRecords: [Data] = []
        var offset: UInt32 = 0
        for entry in entries {
            let crc = CRC32.checksum(entry.data)
            let (dosTime, dosDate) = msDosTimestamp(for: entry.modificationDate)
            let local = localFileHeader(entry: entry, crc: crc, time: dosTime, date: dosDate)
            archive.append(local)
            centralRecords.append(
                centralFileHeader(
                    entry: entry, crc: crc, time: dosTime, date: dosDate, localOffset: offset
                )
            )
            offset += UInt32(local.count)
        }

        let centralStart = offset
        var centralSize: UInt32 = 0
        for record in centralRecords {
            archive.append(record)
            centralSize += UInt32(record.count)
        }
        archive.append(le32: 0x0605_4b50)
        archive.append(le16: 0) // disk
        archive.append(le16: 0) // disk with central directory
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: centralSize)
        archive.append(le32: centralStart)
        archive.append(le16: 0) // comment length
        return archive
    }

    private static func localFileHeader(
        entry: ZipEntry,
        crc: UInt32,
        time: UInt16,
        date: UInt16
    ) -> Data {
        let nameData = Data(entry.name.utf8)
        var local = Data()
        local.append(le32: 0x0403_4b50)
        local.append(le16: 20) // version needed
        local.append(le16: 0) // flags
        local.append(le16: 0) // method: store
        local.append(le16: time)
        local.append(le16: date)
        local.append(le32: crc)
        local.append(le32: UInt32(entry.data.count))
        local.append(le32: UInt32(entry.data.count))
        local.append(le16: UInt16(nameData.count))
        local.append(le16: 0) // extra length
        local.append(nameData)
        local.append(entry.data)
        return local
    }

    private static func centralFileHeader(
        entry: ZipEntry,
        crc: UInt32,
        time: UInt16,
        date: UInt16,
        localOffset: UInt32
    ) -> Data {
        let nameData = Data(entry.name.utf8)
        var central = Data()
        central.append(le32: 0x0201_4b50)
        central.append(le16: 20) // version made by
        central.append(le16: 20) // version needed
        central.append(le16: 0) // flags
        central.append(le16: 0) // method
        central.append(le16: time)
        central.append(le16: date)
        central.append(le32: crc)
        central.append(le32: UInt32(entry.data.count))
        central.append(le32: UInt32(entry.data.count))
        central.append(le16: UInt16(nameData.count))
        central.append(le16: 0) // extra
        central.append(le16: 0) // comment
        central.append(le16: 0) // disk number start
        central.append(le16: 0) // internal attributes
        central.append(le32: 0x81a4_0000) // external attributes: regular file, 0644
        central.append(le32: localOffset) // local header offset
        central.append(nameData)
        return central
    }

    // MARK: - Reading

    /// Parses every entry in a ZIP archive, verifying CRC-32 checksums.
    static func read(_ archive: Data) throws -> [ZipEntry] {
        let directory = try centralDirectorySummary(archive)
        var entries: [ZipEntry] = []
        var seenNames = Set<String>()
        var totalBytes = 0
        var cursor = directory.centralStart
        for _ in 0..<directory.entryCount {
            let record = try centralRecord(archive, cursor: cursor)
            cursor = record.nextCursor
            try validateEntryName(record.name)
            guard seenNames.insert(record.name).inserted else {
                throw ZipError.duplicateEntry(record.name)
            }
            guard record.flags & 0x1 == 0 else { throw ZipError.encryptedEntry(record.name) }
            guard record.method == 0, record.compressedSize == record.uncompressedSize else {
                throw ZipError.unsupportedCompression(record.name)
            }
            totalBytes += record.uncompressedSize
            guard totalBytes <= maxTotalUncompressedBytes else {
                throw ZipError.entryTooLarge(record.name)
            }
            let data = try localPayload(archive, record: record)
            let modification = date(fromMSDOS: record.time, date: record.date)
            entries.append(ZipEntry(name: record.name, data: data, modificationDate: modification))
        }
        guard cursor == directory.centralStart + directory.centralSize else {
            throw ZipError.malformed
        }
        return entries
    }

    struct CentralRecord: Sendable {
        var name: String = ""
        var flags: UInt16 = 0
        var method: UInt16 = 0
        var crc: UInt32 = 0
        var compressedSize = 0
        var uncompressedSize = 0
        var localOffset = 0
        var time: UInt16 = 0
        var date: UInt16 = 0
        var nextCursor = 0
    }

    private struct CentralDirectorySummary {
        var entryCount = 0
        var centralStart = 0
        var centralSize = 0
    }

    private static func centralDirectorySummary(_ archive: Data) throws
        -> CentralDirectorySummary {
        guard let eocdOffset = findEndOfCentralDirectory(archive) else {
            throw ZipError.malformed
        }
        let eocd = archive.startOffset(eocdOffset, length: 22)
        let summary = CentralDirectorySummary(
            entryCount: Int(eocd.readLE16(10)),
            centralStart: Int(eocd.readLE32(16)),
            centralSize: Int(eocd.readLE32(12))
        )
        guard summary.entryCount > 0,
              summary.centralStart + summary.centralSize <= archive.count,
              eocdOffset + 22 + Int(eocd.readLE16(20)) == archive.count else {
            throw ZipError.malformed
        }
        return summary
    }

    private static func centralRecord(_ archive: Data, cursor: Int) throws -> CentralRecord {
        guard cursor + 46 <= archive.count else { throw ZipError.malformed }
        let header = archive.startOffset(cursor, length: 46)
        guard header.readLE32(0) == 0x0201_4b50 else { throw ZipError.malformed }
        let nameLength = Int(header.readLE16(28))
        let extraLength = Int(header.readLE16(30))
        let commentLength = Int(header.readLE16(32))
        let nameStart = cursor + 46
        guard nameStart + nameLength <= archive.count,
              let name = String(
                  data: archive.startOffset(nameStart, length: nameLength),
                  encoding: .utf8
              ) else {
            throw ZipError.malformed
        }
        return CentralRecord(
            name: name,
            flags: header.readLE16(8),
            method: header.readLE16(10),
            crc: header.readLE32(16),
            compressedSize: Int(header.readLE32(20)),
            uncompressedSize: Int(header.readLE32(24)),
            localOffset: Int(header.readLE32(42)),
            time: header.readLE16(12),
            date: header.readLE16(14),
            nextCursor: nameStart + nameLength + extraLength + commentLength
        )
    }

    /// Payload read through the local header — what extractors actually use.
    private static func localPayload(_ archive: Data, record: CentralRecord) throws -> Data {
        guard record.localOffset + 30 <= archive.count else { throw ZipError.malformed }
        let localHeader = archive.startOffset(record.localOffset, length: 30)
        guard localHeader.readLE32(0) == 0x0403_4b50 else { throw ZipError.malformed }
        let localNameLength = Int(localHeader.readLE16(26))
        let localExtraLength = Int(localHeader.readLE16(28))
        let dataStart = record.localOffset + 30 + localNameLength + localExtraLength
        guard dataStart + record.uncompressedSize <= archive.count else {
            throw ZipError.malformed
        }
        let data = archive.startOffset(dataStart, length: record.uncompressedSize)
        guard CRC32.checksum(data) == record.crc else {
            throw ZipError.checksumMismatch(record.name)
        }
        return data
    }

    /// Extracts archive entries below `directory`, creating intermediate
    /// directories. Any unsafe path, checksum mismatch, or size overflow
    /// aborts before anything is written.
    static func extract(_ archive: Data, to directory: URL) throws {
        let entries = try read(archive)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in entries {
            let components = entry.name.split(separator: "/", omittingEmptySubsequences: false)
            guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !entry.name.hasPrefix("/") else {
                throw ZipError.unsafeEntryPath(entry.name)
            }
            let url = directory.appendingPathComponent(entry.name, isDirectory: false)
                .standardizedFileURL
            guard url.path.hasPrefix(directory.standardizedFileURL.path + "/") else {
                throw ZipError.unsafeEntryPath(entry.name)
            }
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try entry.data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Path and timestamp helpers

    static func validateEntryName(_ name: String) throws {
        guard !name.isEmpty,
              !name.hasPrefix("/"),
              !name.contains("\\") else {
            throw ZipError.unsafeEntryPath(name)
        }
        for scalar in name.unicodeScalars where CharacterSet.controlCharacters.contains(scalar) {
            _ = scalar
            throw ZipError.unsafeEntryPath(name)
        }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ZipError.unsafeEntryPath(name)
        }
    }

    private static func findEndOfCentralDirectory(_ data: Data) -> Int? {
        let minimum = max(0, data.count - 22 - Int(UInt16.max))
        var cursor = data.count - 22
        while cursor >= minimum {
            if data.readLE32(cursor) == 0x0605_4b50,
               cursor + 22 <= data.count,
               cursor + 22 + Int(data.readLE16(cursor + 20)) == data.count {
                return cursor
            }
            cursor -= 1
        }
        return nil
    }

    /// MS-DOS timestamps have 1980 as their epoch and two-second resolution.
    static func msDosTimestamp(for date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = (parts.year ?? 1980).clamp(1980, 2107)
        let packedDate = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        let packedTime = (UInt16(parts.hour ?? 0) << 11)
            | (UInt16(parts.minute ?? 0) << 5)
            | UInt16((parts.second ?? 0) / 2)
        return (packedTime, packedDate)
    }

    private static func date(fromMSDOS time: UInt16, date dateBits: UInt16) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let year = Int(dateBits >> 9) + 1980
        let components = DateComponents(
            year: year,
            month: Int((dateBits >> 5) & 0xF),
            day: Int(dateBits & 0x1F),
            hour: Int(time >> 11),
            minute: Int((time >> 5) & 0x3F),
            second: Int((time & 0x1F) * 2)
        )
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

private extension Int {
    func clamp(_ lower: Int, _ upper: Int) -> Int {
        Swift.min(Swift.max(self, lower), upper)
    }
}
