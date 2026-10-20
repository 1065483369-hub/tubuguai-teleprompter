import UIKit
import UniformTypeIdentifiers
import PDFKit

/// 讲稿导入。用户手里的稿子往往已经写好在别处 ——
/// 微信收的 txt、Word 导出的 rtf、网页复制的 html、甲方给的 pdf。
/// 让人重新粘一遍是没必要的摩擦。
enum ScriptImporter {

    /// 支持的类型。docx 不在其中：它是 zip 容器，
    /// NSAttributedString 读不了，需要额外解析，先不做半成品。
    static let types: [UTType] = [
        .plainText, .rtf, .html, .pdf, .text,
    ]

    /// 从文件读出纯文本。失败返回 nil 而不是空串 ——
    /// 调用方要能区分"读失败"和"文件是空的"。
    static func read(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()

        // PDF 走 PDFKit：按页取文本，比 NSAttributedString 可靠
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { return nil }
            var out = ""
            for i in 0..<doc.pageCount {
                if let t = doc.page(at: i)?.string { out += t + "\n" }
            }
            return clean(out)
        }

        // rtf / html 交给 NSAttributedString，它会剥掉格式只留文字
        if ext == "rtf" || ext == "rtfd" || ext == "html" || ext == "htm" {
            let opt: [NSAttributedString.DocumentReadingOptionKey: Any] =
                (ext.hasPrefix("rtf"))
                ? [.documentType: NSAttributedString.DocumentType.rtf]
                : [.documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue]
            if let data = try? Data(contentsOf: url),
               let attr = try? NSAttributedString(data: data, options: opt,
                                                 documentAttributes: nil) {
                return clean(attr.string)
            }
            return nil
        }

        // 纯文本：先试 UTF-8，失败再试 GB18030 —— 中文 txt 常是 GBK 系编码
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            return clean(s)
        }
        if let data = try? Data(contentsOf: url) {
            let gb = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let s = String(data: data, encoding: .init(rawValue: gb)) {
                return clean(s)
            }
        }
        return nil
    }

    /// 归一化：统一换行、压掉多余空行、去掉行首尾空白。
    /// 导入的稿子常带 Word 的软回车和一堆空行，直接用会让气口分段乱。
    private static func clean(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: "\r", with: "\n")
        t = t.replacingOccurrences(of: "\u{2028}", with: "\n")   // Word 软回车
        t = t.replacingOccurrences(of: "\u{00A0}", with: " ")    // 不换行空格
        let lines = t.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // 连续空行压成一个
        var out: [String] = []
        for l in lines {
            if l.isEmpty, out.last?.isEmpty == true { continue }
            out.append(l)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
