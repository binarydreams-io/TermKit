import TermKit

enum PlayerStyles {
    static let steel = RGBA(redByte: 18, greenByte: 23, blueByte: 29)
    static let panel = RGBA(redByte: 15, greenByte: 39, blueByte: 61)
    static let panelRaised = RGBA(redByte: 20, greenByte: 55, blueByte: 80)
    static let amber = RGBA(redByte: 255, greenByte: 184, blueByte: 72)
    static let cyan = RGBA(redByte: 74, greenByte: 218, blueByte: 230)
    static let peak = RGBA(redByte: 244, greenByte: 75, blueByte: 77)
    static let light = RGBA(redByte: 223, greenByte: 231, blueByte: 236)
    static let muted = RGBA(redByte: 129, greenByte: 151, blueByte: 164)

    static let heading = CellStyle(foreground: .rgba(amber), background: .rgba(panel), attributes: .bold)
    static let data = CellStyle(foreground: .rgba(cyan), background: .rgba(panel))
    static let peakData = CellStyle(foreground: .rgba(peak), background: .rgba(panel), attributes: .bold)
    static let body = CellStyle(foreground: .rgba(light), background: .rgba(panel))
    static let quiet = CellStyle(foreground: .rgba(muted), background: .rgba(steel), attributes: .dim)
    static let transport = CellStyle(foreground: .rgba(light), background: .rgba(panelRaised), attributes: .bold)
    static let selected = CellStyle(foreground: .rgba(steel), background: .rgba(amber), attributes: .bold)
    static let current = CellStyle(foreground: .rgba(cyan), background: .rgba(panel), attributes: .bold)
}
