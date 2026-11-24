import Foundation

/// 下载文件名清洗与防覆盖命名策略
public enum DownloadFilenamePolicy {
    private static let illegalCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|\0\n\r\t")

    /// 生成安全且带正确扩展名的建议文件名
    public static func sanitize(
        suggestedName: String?,
        fallbackTitle: String,
        author: String = "",
        fileExtension: String
    ) -> String {
        let cleanExt = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let finalExt = cleanExt.isEmpty ? "epub" : cleanExt

        let rawBase: String
        if let suggested = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines), !suggested.isEmpty {
            let stripped = stripExtension(suggested, matching: finalExt)
            rawBase = stripped
        } else {
            let cleanTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanAuthor.isEmpty {
                rawBase = "\(cleanTitle) - \(cleanAuthor)"
            } else {
                rawBase = cleanTitle
            }
        }

        let sanitizedBase = cleanComponent(rawBase)
        let stem = sanitizedBase.isEmpty ? "Untitled" : String(sanitizedBase.prefix(120))
        return "\(stem).\(finalExt)"
    }

    /// 在目标目录中计算不覆盖已有文件的最终路径（存在同名时自动追加 ` (1)`、` (2)`）
    public static func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        let fm = FileManager.default
        let initial = directory.appendingPathComponent(filename)
        if !fm.fileExists(atPath: initial.path) {
            return initial
        }

        let ext = initial.pathExtension
        let stem = initial.deletingPathExtension().lastPathComponent
        for index in 1...999 {
            let candidateName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let fallbackName = ext.isEmpty ? "\(stem)_\(timestamp)" : "\(stem)_\(timestamp).\(ext)"
        return directory.appendingPathComponent(fallbackName)
    }

    private static func stripExtension(_ name: String, matching ext: String) -> String {
        let suffix = ".\(ext)"
        if name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return (name as NSString).deletingPathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
    }

    private static func cleanComponent(_ text: String) -> String {
        let replaced = text.unicodeScalars.map { scalar -> String in
            if illegalCharacters.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) {
                return " "
            }
            return String(scalar)
        }.joined()

        return replaced
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}
