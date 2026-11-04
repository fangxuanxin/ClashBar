import Foundation

/// 从节点 / 分组名里认出所在国家或地区，返回两个字母的缩写（US、JP、HK……）
enum Region {
    /// 名称里直接写着的两字母缩写（必须是大写独立词，如 "Main US 01"、"JP-Tokyo"）
    static let codes: Set<String> = [
        "US", "JP", "HK", "TW", "SG", "KR", "UK", "GB", "DE", "FR", "NL", "CA", "AU", "RU", "IN", "TR",
        "MY", "TH", "VN", "PH", "ID", "AR", "BR", "CN", "MO", "IT", "ES", "CH", "SE", "IE", "PL", "UA",
        "IL", "AE", "ZA", "MX", "CL", "KZ", "PK", "EG", "NZ", "FI", "NO", "DK", "AT", "BE", "PT", "CZ",
        "RO", "HU", "GR", "SA", "MN", "KH", "LA", "MM", "BD", "NG", "CO", "PE", "EE", "LV", "LT", "IS",
        "LU", "BG", "RS", "HR", "SK", "SI", "MD", "GE", "AM", "AZ", "UZ", "KG", "NP", "LK", "QA", "KW",
        "BH", "OM", "JO", "IR", "IQ", "CY", "MT", "KE", "MA", "VE", "PA", "CR", "UY", "EC", "BO", "BN",
    ]

    /// 三字母写法到两字母的映射（同样要求大写独立词）
    static let alpha3: [String: String] = [
        "USA": "US", "JPN": "JP", "HKG": "HK", "TWN": "TW", "SGP": "SG", "KOR": "KR", "GBR": "UK",
        "DEU": "DE", "FRA": "FR", "NLD": "NL", "CAN": "CA", "AUS": "AU", "RUS": "RU", "IND": "IN",
        "TUR": "TR", "UAE": "AE", "ARE": "AE", "LAX": "US", "SJC": "US", "NRT": "JP", "HND": "JP", "KIX": "JP",
        "ICN": "KR", "TPE": "TW",
    ]

    /// 关键词表：越具体越靠前（「中国香港」要先命中 HK，「印度尼西亚」要先命中 ID）
    static let keywords: [(String, [String])] = [
        ("HK", ["香港", "hong kong", "hongkong"]),
        ("TW", ["台湾", "台灣", "台北", "新北", "彰化", "taiwan", "taipei"]),
        ("MO", ["澳门", "澳門", "macau", "macao"]),
        ("ID", ["印尼", "印度尼西亚", "雅加达", "indonesia", "jakarta"]),
        ("US", ["美国", "美國", "洛杉矶", "洛杉磯", "圣何塞", "硅谷", "西雅图", "纽约", "紐約", "芝加哥", "达拉斯",
                "凤凰城", "旧金山", "波特兰", "弗里蒙特", "加利福尼亚", "加州", "弗吉尼亚", "俄勒冈", "德克萨斯", "迈阿密", "亚特兰大", "california", "virginia", "oregon", "texas", "miami", "atlanta", "ashburn", "united states", "america", "los angeles", "san jose",
                "silicon valley", "seattle", "new york", "chicago", "dallas", "phoenix", "san francisco", "portland"]),
        ("JP", ["日本", "东京", "東京", "大阪", "埼玉", "japan", "tokyo", "osaka"]),
        ("SG", ["新加坡", "狮城", "獅城", "singapore"]),
        ("KR", ["韩国", "韓國", "首尔", "首爾", "春川", "korea", "seoul"]),
        ("UK", ["英国", "英國", "伦敦", "倫敦", "united kingdom", "britain", "england", "london"]),
        ("DE", ["德国", "德國", "法兰克福", "germany", "frankfurt"]),
        ("FR", ["法国", "法國", "巴黎", "france", "paris"]),
        ("NL", ["荷兰", "荷蘭", "阿姆斯特丹", "netherlands", "amsterdam"]),
        ("CA", ["加拿大", "多伦多", "温哥华", "canada", "toronto", "vancouver", "montreal"]),
        ("AU", ["澳大利亚", "澳洲", "悉尼", "墨尔本", "australia", "sydney", "melbourne"]),
        ("NZ", ["新西兰", "new zealand"]),
        ("RU", ["俄罗斯", "俄羅斯", "莫斯科", "伯力", "russia", "moscow"]),
        ("IN", ["印度", "孟买", "india", "mumbai"]),
        ("TR", ["土耳其", "伊斯坦布尔", "turkey", "türkiye", "istanbul"]),
        ("MY", ["马来西亚", "馬來西亞", "吉隆坡", "malaysia", "kuala lumpur"]),
        ("TH", ["泰国", "泰國", "曼谷", "thailand", "bangkok"]),
        ("VN", ["越南", "vietnam", "viet nam"]),
        ("PH", ["菲律宾", "菲律賓", "马尼拉", "philippines", "manila"]),
        ("AR", ["阿根廷", "argentina"]),
        ("BR", ["巴西", "brazil", "são paulo", "sao paulo"]),
        ("IT", ["意大利", "米兰", "italy", "milan"]),
        ("ES", ["西班牙", "马德里", "spain", "madrid"]),
        ("CH", ["瑞士", "苏黎世", "switzerland", "zurich"]),
        ("SE", ["瑞典", "sweden", "stockholm"]),
        ("IE", ["爱尔兰", "愛爾蘭", "ireland", "dublin"]),
        ("PL", ["波兰", "poland", "warsaw"]),
        ("UA", ["乌克兰", "ukraine", "kyiv"]),
        ("IL", ["以色列", "israel"]),
        ("AE", ["阿联酋", "迪拜", "dubai", "emirates"]),
        ("ZA", ["南非", "south africa", "johannesburg"]),
        ("MX", ["墨西哥", "mexico"]),
        ("CL", ["智利", "chile"]),
        ("KZ", ["哈萨克斯坦", "kazakhstan"]),
        ("PK", ["巴基斯坦", "pakistan"]),
        ("EG", ["埃及", "egypt"]),
        ("MN", ["蒙古", "mongolia"]),
        ("KH", ["柬埔寨", "cambodia"]),
        ("FI", ["芬兰", "finland"]),
        ("NO", ["挪威", "norway"]),
        ("DK", ["丹麦", "denmark", "copenhagen"]),
        ("AT", ["奥地利", "austria", "vienna"]),
        ("BE", ["比利时", "belgium", "brussels"]),
        ("PT", ["葡萄牙", "portugal", "lisbon"]),
        ("CZ", ["捷克", "czech", "prague"]),
        ("RO", ["罗马尼亚", "romania", "bucharest"]),
        ("HU", ["匈牙利", "hungary", "budapest"]),
        ("GR", ["希腊", "greece", "athens"]),
        ("EE", ["爱沙尼亚", "愛沙尼亞", "estonia", "tallinn", "harjumaa"]),
        ("LV", ["拉脱维亚", "latvia", "riga"]),
        ("LT", ["立陶宛", "lithuania", "vilnius"]),
        ("IS", ["冰岛", "iceland", "reykjavik"]),
        ("LU", ["卢森堡", "luxembourg"]),
        ("BG", ["保加利亚", "bulgaria", "sofia"]),
        ("RS", ["塞尔维亚", "serbia", "belgrade"]),
        ("HR", ["克罗地亚", "croatia", "zagreb"]),
        ("SK", ["斯洛伐克", "slovakia"]),
        ("SI", ["斯洛文尼亚", "slovenia"]),
        ("MD", ["摩尔多瓦", "moldova"]),
        ("GE", ["格鲁吉亚", "tbilisi"]),
        ("AM", ["亚美尼亚", "armenia", "yerevan"]),
        ("AZ", ["阿塞拜疆", "azerbaijan", "baku"]),
        ("UZ", ["乌兹别克", "uzbekistan", "tashkent"]),
        ("KG", ["吉尔吉斯", "kyrgyzstan"]),
        ("NP", ["尼泊尔", "nepal"]),
        ("LK", ["斯里兰卡", "sri lanka"]),
        ("BD", ["孟加拉", "bangladesh", "dhaka"]),
        ("MM", ["缅甸", "myanmar"]),
        ("LA", ["老挝", "laos"]),
        ("BN", ["文莱", "brunei"]),
        ("SA", ["沙特", "saudi", "riyadh"]),
        ("QA", ["卡塔尔", "qatar", "doha"]),
        ("KW", ["科威特", "kuwait"]),
        ("BH", ["巴林", "bahrain"]),
        ("OM", ["阿曼", "muscat"]),
        ("JO", ["约旦", "jordan", "amman"]),
        ("IR", ["伊朗", "tehran"]),
        ("IQ", ["伊拉克", "iraq", "baghdad"]),
        ("CY", ["塞浦路斯", "cyprus", "nicosia"]),
        ("MT", ["马耳他", "malta"]),
        ("NG", ["尼日利亚", "nigeria", "lagos"]),
        ("KE", ["肯尼亚", "kenya", "nairobi"]),
        ("MA", ["摩洛哥", "morocco"]),
        ("CO", ["哥伦比亚", "colombia", "bogota"]),
        ("PE", ["秘鲁", "lima"]),
        ("VE", ["委内瑞拉", "venezuela"]),
        ("PA", ["巴拿马", "panama"]),
        ("CR", ["哥斯达黎加", "costa rica"]),
        ("UY", ["乌拉圭", "uruguay"]),
        ("EC", ["厄瓜多尔", "ecuador"]),
        ("BO", ["玻利维亚", "bolivia"]),
        ("CN", ["中国", "中國", "回国", "上海", "北京", "深圳", "广州", "广东", "杭州", "china", "guangdong", "shanghai", "beijing"]),
    ]

    /// 识别单个名称；认不出返回 nil。顺序：国旗 emoji → 大写缩写 → 中英文关键词
    static func code(of name: String) -> String? {
        if let flag = flagCode(name) { return flag }
        if let token = tokenCode(name) { return token }
        let lower = name.lowercased()
        for (code, words) in keywords where words.contains(where: { lower.contains($0) }) {
            return code
        }
        return nil
    }

    /// 当前出口的地区：先看最终节点，再沿路径由深到浅看分组名
    static func code(of exit: ExitInfo) -> String? {
        switch exit.family {
        case .direct, .reject: return nil
        default: break
        }
        var names: [String] = []
        if let node = exit.node { names.append(node) }
        names += exit.chain.reversed()
        if let group = exit.group { names.append(group) }
        return names.lazy.compactMap { code(of: $0) }.first
    }

    /// 国旗 emoji 由两个区域指示符组成，直接换成字母
    static func flagCode(_ name: String) -> String? {
        let base: UInt32 = 0x1F1E6
        let scalars = Array(name.unicodeScalars)
        for i in scalars.indices.dropLast() {
            let a = scalars[i].value, b = scalars[i + 1].value
            guard (base...base + 25).contains(a), (base...base + 25).contains(b) else { continue }
            let letters = [a, b].compactMap { UnicodeScalar($0 - base + 65) }.map(Character.init)
            let code = String(letters)
            return code == "GB" ? "UK" : code
        }
        return nil
    }

    /// 按非字母切词，找大写的两字母 / 三字母缩写
    static func tokenCode(_ name: String) -> String? {
        let tokens = name.split { !($0.isASCII && $0.isLetter) }.map(String.init)
        for token in tokens where token == token.uppercased() {
            if token.count == 2, codes.contains(token) { return token == "GB" ? "UK" : token }
            if token.count == 3, let code = alpha3[token] { return code }
        }
        return nil
    }
}
