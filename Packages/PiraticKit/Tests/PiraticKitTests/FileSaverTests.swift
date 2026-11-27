//
//  FileSaverTests.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import XCTest
@testable import PiraticKit

class FileSaverTests: XCTestCase {

    // MARK: - Test Variables

    private let attempts = FileManagerMock.Attempts()

    // MARK: - Test Methods

    func testSaveFile_Success() {
        // Arrange
        let fileSaver = FileSaver(fileManager: FileManagerMock(attempts: attempts))
        let sourceURL = URL(string: "http://example.com/sourcefile.txt")!
        let destinationURL = URL(string: "file:///path/to/destinationfile.txt")!

        // Act & Assert
        XCTAssertNoThrow(try fileSaver.saveFile(from: sourceURL, to: destinationURL))
        XCTAssertTrue(attempts.didAttemptRemoveItem)
        XCTAssertTrue(attempts.didAttemptMoveItem)
    }

    func testSaveFile_ThrowsError() {
        // Arrange
        let fileSaver = FileSaver(fileManager: FileManagerMock(attempts: attempts, shouldThrowError: true))
        let sourceURL = URL(string: "http://example.com/sourcefile.txt")!
        let destinationURL = URL(string: "file:///path/to/destinationfile.txt")!

        // Act & Assert
        // The pre-emptive removeItem is wrapped in `try?`, so its failure is swallowed
        // and the move is still attempted — it is the move's error that propagates.
        XCTAssertThrowsError(try fileSaver.saveFile(from: sourceURL, to: destinationURL))
        XCTAssertTrue(attempts.didAttemptRemoveItem)
        XCTAssertTrue(attempts.didAttemptMoveItem)
    }

    func testGetDocumentsDirectoryURL() {
        // Arrange
        let fileSaver = FileSaver(fileManager: FileManagerMock(attempts: attempts))
        let filename = "testfile.txt"

        // Act
        let documentsDirectoryURL = fileSaver.getDocumentsDirectoryURL(forFilename: filename)

        // Assert
        XCTAssertEqual(documentsDirectoryURL.lastPathComponent, filename)
        XCTAssertEqual(documentsDirectoryURL.pathExtension, "txt")
    }
}
