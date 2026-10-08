import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum CodexHomeScope {
    public static func isAppServerProcess(_ pid: Int32) -> Bool {
        #if canImport(Darwin)
        guard pid > 0 else { return false }
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var byteCount = 0
        guard sysctl(&mib, u_int(mib.count), nil, &byteCount, nil, 0) == 0,
              byteCount >= MemoryLayout<Int32>.size, byteCount <= 1024 * 1024
        else { return false }
        var data = Data(count: byteCount)
        let result = data.withUnsafeMutableBytes { buffer in
            sysctl(&mib, u_int(mib.count), buffer.baseAddress, &byteCount, nil, 0)
        }
        guard result == 0, byteCount <= data.count else { return false }
        data = data.prefix(byteCount)
        guard let arguments = self.appServerArguments(from: data) else { return false }
        return self.isAppServer(arguments: arguments)
        #else
        return false
        #endif
    }

    static func isAppServer(arguments: [String]) -> Bool {
        guard let executable = arguments.first,
              URL(fileURLWithPath: executable).lastPathComponent == "codex",
              arguments.dropFirst().starts(with: ["app-server"]),
              let listenIndex = arguments.firstIndex(of: "--listen"),
              listenIndex + 1 < arguments.count
        else { return false }
        return arguments[listenIndex + 1] == "unix://"
    }

    /// Read only argv from Darwin's payload; never expose the following process environment.
    static func appServerArguments(from data: Data) -> [String]? {
        guard data.count >= MemoryLayout<Int32>.size else { return nil }
        let count = data.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard count > 0, count <= data.count else { return nil }
        let bytes = [UInt8](data)
        var offset = MemoryLayout<Int32>.size
        guard let executableEnd = bytes[offset...].firstIndex(of: 0) else { return nil }
        offset = executableEnd + 1
        while offset < bytes.count, bytes[offset] == 0 {
            offset += 1
        }
        var arguments: [String] = []
        for _ in 0..<count {
            guard offset < bytes.count,
                  let end = bytes[offset...].firstIndex(of: 0),
                  let argument = String(bytes: bytes[offset..<end], encoding: .utf8)
            else { return nil }
            arguments.append(argument)
            offset = end + 1
        }
        return arguments
    }

    public static func ambientHomeURL(
        env: [String: String],
        fileManager: FileManager = .default)
        -> URL
    {
        if let raw = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    public static func scopedEnvironment(base: [String: String], codexHome: String?) -> [String: String] {
        guard let codexHome, !codexHome.isEmpty else { return base }
        var env = base
        env["CODEX_HOME"] = codexHome
        return env
    }
}
