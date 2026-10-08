import CodexBarCore
import Foundation

enum CodexCLIShellIntegrationInstaller {
    private enum InstallationError: Error {
        case unableToEncodeScript
    }

    @discardableResult
    static func installFromCurrentApp(
        bundle: Bundle = .main,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default) -> [String]?
    {
        let helperURL = bundle.bundleURL.appendingPathComponent("Contents/Helpers/CodexBarCLI")
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { return nil }
        return try? self.install(helperURL: helperURL, homeURL: homeURL, fileManager: fileManager)
    }

    static func install(
        helperURL: URL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default) throws -> [String]
    {
        let codexBarDirectory = homeURL.appendingPathComponent(".codexbar", isDirectory: true)
        try fileManager.createDirectory(at: codexBarDirectory, withIntermediateDirectories: true)

        let integrationURL = codexBarDirectory.appendingPathComponent(
            CodexCLIShellIntegration.fileName,
            isDirectory: false)
        guard let integrationData = CodexCLIShellIntegration.script(helperPath: helperURL.path).data(using: .utf8)
        else {
            throw InstallationError.unableToEncodeScript
        }
        try integrationData.write(to: integrationURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: integrationURL.path)

        let shellFiles = [
            homeURL.appendingPathComponent(".zshrc", isDirectory: false),
            homeURL.appendingPathComponent(".bashrc", isDirectory: false),
        ].filter { url in
            url.lastPathComponent == ".zshrc" || fileManager.fileExists(atPath: url.path)
        }

        var installedShells: [String] = []
        for shellURL in shellFiles {
            let existing = if fileManager.fileExists(atPath: shellURL.path) {
                try String(contentsOf: shellURL, encoding: .utf8)
            } else {
                ""
            }
            let updated = Self.upsertSourceBlock(in: existing)
            try Self.writePreservingPermissions(updated, to: shellURL, fileManager: fileManager)
            installedShells.append(shellURL.lastPathComponent)
        }

        return installedShells
    }

    private static func upsertSourceBlock(in contents: String) -> String {
        let block = CodexCLIShellIntegration.sourceBlock().trimmingCharacters(in: .newlines)
        let startMarker = CodexCLIShellIntegration.startMarker
        let endMarker = CodexCLIShellIntegration.endMarker

        if let startRange = contents.range(of: startMarker),
           let endRange = contents.range(
               of: endMarker,
               range: startRange.upperBound..<contents.endIndex)
        {
            let managedRange = startRange.lowerBound..<endRange.upperBound
            return contents.replacingCharacters(in: managedRange, with: block)
        }

        let separator = contents.isEmpty || contents.hasSuffix("\n") ? "" : "\n"
        return contents + separator + "\n" + block + "\n"
    }

    private static func writePreservingPermissions(
        _ contents: String,
        to url: URL,
        fileManager: FileManager) throws
    {
        let permissions = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]
        guard let data = contents.data(using: .utf8) else {
            throw InstallationError.unableToEncodeScript
        }
        try data.write(to: url, options: [.atomic])
        if let permissions {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }
}
