import Foundation

/// Chinese names of places people travel to, with the English names the
/// index stores (place names come from Apple Maps in English). Without
/// this, "东京的照片" finds no place called 东京.
nonisolated enum PlaceNames {
    private static let english: [(chinese: String, english: String)] = [
        ("香港", "Hong Kong"), ("澳门", "Macau"), ("澳門", "Macau"), ("台北", "Taipei"), ("台湾", "Taiwan"), ("台灣", "Taiwan"),
        ("北京", "Beijing"), ("上海", "Shanghai"), ("广州", "Guangzhou"), ("廣州", "Guangzhou"), ("深圳", "Shenzhen"),
        ("杭州", "Hangzhou"), ("成都", "Chengdu"), ("重庆", "Chongqing"), ("重慶", "Chongqing"), ("西安", "Xi'an"),
        ("南京", "Nanjing"), ("苏州", "Suzhou"), ("蘇州", "Suzhou"), ("武汉", "Wuhan"), ("武漢", "Wuhan"),
        ("厦门", "Xiamen"), ("廈門", "Xiamen"), ("青岛", "Qingdao"), ("青島", "Qingdao"), ("三亚", "Sanya"), ("三亞", "Sanya"),
        ("东京", "Tokyo"), ("東京", "Tokyo"), ("大阪", "Osaka"), ("京都", "Kyoto"), ("北海道", "Hokkaido"), ("冲绳", "Okinawa"), ("沖繩", "Okinawa"),
        ("日本", "Japan"), ("首尔", "Seoul"), ("首爾", "Seoul"), ("韩国", "South Korea"), ("韓國", "South Korea"),
        ("新加坡", "Singapore"), ("曼谷", "Bangkok"), ("泰国", "Thailand"), ("泰國", "Thailand"), ("吉隆坡", "Kuala Lumpur"),
        ("巴厘岛", "Bali"), ("峇里島", "Bali"), ("悉尼", "Sydney"), ("墨尔本", "Melbourne"), ("墨爾本", "Melbourne"),
        ("伦敦", "London"), ("倫敦", "London"), ("巴黎", "Paris"), ("罗马", "Rome"), ("羅馬", "Rome"),
        ("柏林", "Berlin"), ("巴塞罗那", "Barcelona"), ("巴塞隆納", "Barcelona"), ("阿姆斯特丹", "Amsterdam"),
        ("苏黎世", "Zurich"), ("蘇黎世", "Zurich"), ("瑞士", "Switzerland"), ("采尔马特", "Zermatt"), ("策马特", "Zermatt"),
        ("纽约", "New York"), ("紐約", "New York"), ("洛杉矶", "Los Angeles"), ("洛杉磯", "Los Angeles"),
        ("旧金山", "San Francisco"), ("舊金山", "San Francisco"), ("西雅图", "Seattle"), ("西雅圖", "Seattle"),
        ("温哥华", "Vancouver"), ("溫哥華", "Vancouver"), ("多伦多", "Toronto"), ("多倫多", "Toronto"),
        ("迪拜", "Dubai"), ("杜拜", "Dubai"), ("旺角", "Mong Kok"), ("中环", "Central"), ("中環", "Central"),
        ("尖沙咀", "Tsim Sha Tsui"), ("铜锣湾", "Causeway Bay"), ("銅鑼灣", "Causeway Bay"), ("九龙", "Kowloon"), ("九龍", "Kowloon"),
    ]

    /// The text with every Chinese place name it contains written in English.
    static func inEnglish(_ text: String) -> String {
        guard TextNormalizer.containsCJK(text) else { return text }
        var result = text
        for (chinese, name) in english where result.contains(chinese) {
            result = result.replacingOccurrences(of: chinese, with: " \(name) ")
        }
        return result.replacing(/\s{2,}/, with: " ").trimmingCharacters(in: .whitespaces)
    }
}
