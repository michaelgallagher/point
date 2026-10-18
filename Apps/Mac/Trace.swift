import Foundation

/// Debug builds only: timestamped notes to a file named by `-ImprintTrace <path>`, for
/// finding out what happens when (and what's slow) without a debugger.
enum Trace {
    #if DEBUG
    private static let file: FileHandle? = {
        guard let path = UserDefaults.standard.string(forKey: "ImprintTrace") else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()
    private static let start = Date()
    #endif

    static func mark(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard let file else { return }
        let line = String(format: "%7.3f ", Date().timeIntervalSince(start)) + message() + "\n"
        file.write(Data(line.utf8))
        #endif
    }
}
