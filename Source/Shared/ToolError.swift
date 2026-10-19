import Foundation

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
