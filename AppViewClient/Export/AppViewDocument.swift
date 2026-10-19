//
//  AppViewDocument.swift
//  AppView
//

import AppKit
import AppViewShared

class AppViewDocument: NSDocument {
    var hierarchyFile: AppViewHierarchyFile?

    override func makeWindowControllers() {
        guard let hierarchyFile else { return }
        let wc = AVReadWindowController(file: hierarchyFile)
        addWindowController(wc)
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let hierarchyFile else {
            assertionFailure()
            throw AVAppViewClientErrors.inner
        }

        if typeName == "com.appview.appview" || typeName == "appview" {
            return try AVWireCodec.archive(hierarchyFile: hierarchyFile)
        }

        throw AVAppViewClientErrors.inner
    }

    override func read(from data: Data, ofType typeName: String) throws {
        // typeName may be the declared UTI or a generic/dynamic type — magic is authoritative.
        let file = try AVWireCodec.loadHierarchyFile(from: data)

        if let verifyError = AppViewHierarchyFile.verify(file) {
            throw verifyError
        }

        self.hierarchyFile = file
    }
}
