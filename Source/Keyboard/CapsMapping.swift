import Foundation

// hidutil has no persistent effect after reboot. Only this app's Caps entry is restored.
final class CapsMapping {
    let defaults = UserDefaults.standard
    let recoveryKey = DefaultsKey.capsMappingRecovery
    static let timeout: TimeInterval = 5

    // Waits without spinning the run loop, so no event-tap callback or queued UI
    // work can re-enter mapping changes while hidutil runs. Both pipes are drained
    // concurrently, so a full stderr pipe can never stall hidutil.
    func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let stdout = PipeContents(), stderr = PipeContents()
        let reads = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: reads) {
            stdout.data = output.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global(qos: .userInitiated).async(group: reads) {
            stderr.data = errors.fileHandleForReading.readDataToEndOfFile()
        }
        let deadline = DispatchTime.now() + Self.timeout
        guard reads.wait(timeout: deadline) == .success, exited.wait(timeout: deadline) == .success else {
            process.terminate()
            throw ToolError(message: "Keyboard mapping timed out: hidutil did not respond.")
        }
        guard process.terminationStatus == 0 else {
            throw ToolError(message: "Keyboard mapping failed: " + (String(data: stderr.data, encoding: .utf8) ?? "hidutil"))
        }
        return stdout.data
    }
    // Written by one reader thread; read only after the group has finished.
    private final class PipeContents { var data = Data() }
    func read() throws -> [[String: UInt64]] {
        let data = try run(["property", "--get", "UserKeyMapping"])
        return try MappingCodec.decode(data)
    }
    func write(_ entries: [[String: UInt64]]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": entries])
        _ = try run(["property", "--set", String(decoding: data, as: UTF8.self)])
        guard try read() == entries else { throw ToolError(message: "Keyboard mapping was not accepted. Check permissions or other keyboard tools.") }
    }
    func install() throws {
        try restore()
        let current = try read()
        defaults.set(try JSONEncoder().encode(current.filter { $0[MappingPolicy.src] == MappingPolicy.caps }), forKey: recoveryKey)
        try write(MappingPolicy.install(current))
    }
    func restore() throws {
        guard let data = defaults.data(forKey: recoveryKey) else { return }
        let previous = try JSONDecoder().decode([[String: UInt64]].self, from: data)
        let current = try read()
        // Unchanged when Clutch's Caps → F18 entry is already gone.
        let updated = MappingPolicy.restore(current, previous: previous)
        if updated != current { try write(updated) }
        defaults.removeObject(forKey: recoveryKey)
    }
}
