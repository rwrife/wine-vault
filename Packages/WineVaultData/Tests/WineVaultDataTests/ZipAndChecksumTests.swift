import Foundation
import XCTest

@testable import WineVaultData
import WineVaultDomain

/// Checksum cross-validation: our SHA-256 must match published FIPS 180-4
/// test vectors, and CRC-32 must match known values, so backup digests are
/// independently verifiable by any standard tool.
final class ChecksumTests: XCTestCase {
    func testSHA256KnownVectors() {
        XCTAssertEqual(
            SHA256.hexDigest(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            SHA256.hexDigest(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        // 448-bit vector crossing the padding boundary.
        let message = Data(
            "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8
        )
        XCTAssertEqual(
            SHA256.hexDigest(message),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
        // 1,000,000 × 'a' (multi-block).
        let million = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
        XCTAssertEqual(
            SHA256.hexDigest(million),
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        )
    }

    func testCRC32KnownVectors() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }
}

/// Round-trip and hostile-archive tests for the store-method ZIP codec.
final class ZipArchiveTests: XCTestCase {
    private func sampleEntries() -> [ZipEntry] {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let binary = Data([0x62, 0x69, 0x6e, 0x61, 0x72, 0x79, 0x00, 0x01, 0x02, 0x66, 0x66])
        return [
            ZipEntry(name: "manifest.json", data: Data(#"{"ok":true}"#.utf8), modificationDate: date),
            ZipEntry(name: "vault.sqlite", data: binary, modificationDate: date),
            ZipEntry(name: "photos/abc.jpg", data: Data("jpegbytes".utf8), modificationDate: date),
        ]
    }

    func testBuildReadRoundTripPreservesBytesAndOrder() throws {
        let original = sampleEntries()
        let archive = ZipArchive.build(entries: original)
        let read = try ZipArchive.read(archive)
        XCTAssertEqual(read.map(\.name), original.map(\.name))
        XCTAssertEqual(read.map(\.data), original.map(\.data))
        // DOS timestamps have two-second resolution.
        for (lhs, rhs) in zip(read, original) {
            XCTAssertEqual(
                Int(lhs.modificationDate.timeIntervalSince1970 / 2),
                Int(rhs.modificationDate.timeIntervalSince1970 / 2)
            )
        }
    }

    func testCorruptedPayloadIsDetectedByChecksum() throws {
        var archive = ZipArchive.build(entries: sampleEntries())
        // Flip a byte inside the second local entry payload.
        let payloadStart = archive.firstRange(of: Data("binary".utf8))!.lowerBound
        let index = archive.index(payloadStart, offsetBy: 3)
        archive[index] ^= 0xFF
        XCTAssertThrowsError(try ZipArchive.read(archive)) { error in
            XCTAssertEqual(error as? ZipError, .checksumMismatch("vault.sqlite"))
        }
    }

    func testExtractRejectsTraversalAndAbsolutePaths() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for hostile in ["../escape.txt", "photos/../../escape.txt", "/etc/passwd"] {
            let archive = ZipArchive.build(
                entries: [ZipEntry(name: hostile, data: Data("x".utf8), modificationDate: date)]
            )
            XCTAssertThrowsError(try ZipArchive.read(archive)) { error in
                XCTAssertEqual(error as? ZipError, .unsafeEntryPath(hostile))
            }
        }
    }

    func testExtractWritesFilesBelowDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZipArchiveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try ZipArchive.extract(ZipArchive.build(entries: sampleEntries()), to: directory)
        let restored = try Data(
            contentsOf: directory.appendingPathComponent("photos/abc.jpg")
        )
        XCTAssertEqual(restored, Data("jpegbytes".utf8))
    }

    func testTruncatedAndForeignArchivesAreRejected() {
        let archive = ZipArchive.build(entries: sampleEntries())
        XCTAssertThrowsError(try ZipArchive.read(archive.dropFirst(10)))
        XCTAssertThrowsError(try ZipArchive.read(Data("not a zip".utf8)))
    }

    func testDuplicateEntryNamesAreRejected() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let archive = ZipArchive.build(entries: [
            ZipEntry(name: "a.txt", data: Data("1".utf8), modificationDate: date),
            ZipEntry(name: "a.txt", data: Data("2".utf8), modificationDate: date),
        ])
        // Duplicate names break the exact-set check during backup validation
        // and are rejected on read by the seen-name guard.
        XCTAssertThrowsError(try ZipArchive.read(archive)) { error in
            XCTAssertEqual(error as? ZipError, .duplicateEntry("a.txt"))
        }
    }
}
