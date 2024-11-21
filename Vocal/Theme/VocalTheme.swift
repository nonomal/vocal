import SwiftUI

enum VocalTheme {
    static let padding = EdgeInsets(top: 20, leading: 24, bottom: 20, trailing: 24)
    
    struct Colors {
        static let background = Color("Background")
        static let foreground = Color("Foreground")
        static let accent = Color("Accent")
        static let surface = Color("Surface")
        static let divider = Color("Divider")
        
        static let success = Color("Success")
        static let warning = Color("Warning")
        static let error = Color("Error")
    }
    
    struct Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold)
        static let title = Font.system(size: 20, weight: .semibold)
        static let headline = Font.system(size: 16, weight: .semibold)
        static let body = Font.system(size: 14, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
    }
}