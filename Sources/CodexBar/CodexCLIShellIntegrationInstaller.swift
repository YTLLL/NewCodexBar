import CodexBarCore
import Foundation

enum CodexCLIShellIntegrationInstaller {
    enum InstallationError: Error, Equatable {
        case invalidMarkers(String)
        case unsupportedFile(String)
    }

    @discardableResult
    static func installFromCurrentApp(
        bundle: Bundle = .main,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default) -> [String]?
    {
        // Do not install from SwiftPM executables/test bundles. The script itself needs no helper.
        let helperURL = bundle.bundleURL.appendingPathComponent("Contents/Helpers/CodexBarCLI")
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { return nil }
        return try? self.install(homeURL: homeURL, fileManager: fileManager)
    }

    @discardableResult
    static func install(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default) throws -> [String]
    {
        let directory = homeURL.appendingPathComponent(".codexbar", isDirectory: true)
        let integrationURL = directory.appendingPathComponent(CodexCLIShellIntegration.fileName)
        try self.validateFileType(directory, expected: .typeDirectory, fileManager: fileManager)
        try self.validateFileType(integrationURL, expected: .typeRegular, fileManager: fileManager)
        let shellFiles = [".zshrc", ".bashrc"].map { homeURL.appendingPathComponent($0) }.filter {
            $0.lastPathComponent == ".zshrc" || fileManager.fileExists(atPath: $0.path) ||
                (try? fileManager.destinationOfSymbolicLink(atPath: $0.path)) != nil
        }

        // Preflight every file before replacing even the generated script. Broken/duplicate markers
        // must not leave an old routing function mixed with a partially installed new integration.
        let updates = try shellFiles.map { url -> (URL, String) in
            try self.validateFileType(url, expected: .typeRegular, fileManager: fileManager)
            let existing = if fileManager.fileExists(atPath: url.path) {
                try String(contentsOf: url, encoding: .utf8)
            } else {
                ""
            }
            return try (url, self.upsertSourceBlock(in: existing, fileName: url.lastPathComponent))
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try self.writeIfChanged(
            CodexCLIShellIntegration.script(), to: integrationURL, permissions: 0o644, fileManager: fileManager)
        for (url, updated) in updates {
            let permissions = if fileManager.fileExists(atPath: url.path) {
                try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            } else {
                nil as NSNumber?
            }
            try self.writeIfChanged(
                updated, to: url, permissions: permissions?.intValue ?? 0o600, fileManager: fileManager)
        }
        return shellFiles.map(\.lastPathComponent)
    }

    private static func upsertSourceBlock(in contents: String, fileName: String) throws -> String {
        let block = CodexCLIShellIntegration.sourceBlock()
        let start = CodexCLIShellIntegration.startMarker
        let end = CodexCLIShellIntegration.endMarker
        let startCount = contents.components(separatedBy: start).count - 1
        let endCount = contents.components(separatedBy: end).count - 1
        if startCount == 0, endCount == 0 {
            let separator = contents.isEmpty || contents.hasSuffix("\n") ? "" : "\n"
            return contents + separator + block + "\n"
        }
        let lines = contents.components(separatedBy: "\n")
        guard startCount == 1, endCount == 1, lines.contains(start), lines.contains(end),
              let startRange = contents.range(of: start), let endRange = contents.range(of: end),
              startRange.upperBound <= endRange.lowerBound
        else { throw InstallationError.invalidMarkers(fileName) }
        return contents.replacingCharacters(in: startRange.lowerBound..<endRange.upperBound, with: block)
    }

    private static func validateFileType(
        _ url: URL,
        expected: FileAttributeType,
        fileManager: FileManager) throws
    {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw InstallationError.unsupportedFile(url.lastPathComponent)
        }
        guard fileManager.fileExists(atPath: url.path) else { return }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == expected else {
            throw InstallationError.unsupportedFile(url.lastPathComponent)
        }
    }

    private static func writeIfChanged(
        _ contents: String,
        to url: URL,
        permissions: Int,
        fileManager: FileManager) throws
    {
        let data = Data(contents.utf8)
        if (try? Data(contentsOf: url)) == data { return }
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}
