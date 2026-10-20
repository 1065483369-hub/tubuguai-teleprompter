import Foundation

/// 滚动方式。语音跟随是主打，但它有失效场景：
/// 环境太吵、需要念外语、或者干脆不想出声对稿。
/// 所以匀速和定时是必要的退路，不是可选的锦上添花。
enum ScrollMode: String, CaseIterable {
    case voice = "语音跟随"
    case manual = "匀速滚动"
    case timed = "定时读完"

    var hint: String {
        switch self {
        case .voice:  return "跟着你的声音走，停下就停"
        case .manual: return "固定速度，用滑块调快慢"
        case .timed:  return "按目标时长自动配速"
        }
    }
}
