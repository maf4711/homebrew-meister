import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case maintenance = "Wartung"
    case cleaning = "Reinigung"
    case parameters = "Parameter"
    case security = "Sicherheit"
    case automation = "Automation"
    case log = "Protokoll"
    case info = "Info"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .cleaning: return "trash.fill"
        case .parameters: return "slider.horizontal.3"
        case .security: return "lock.shield.fill"
        case .automation: return "clock.arrow.2.circlepath"
        case .log: return "doc.text.fill"
        case .info: return "info.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .maintenance: return "Quick / Deep / Profile"
        case .cleaning: return "Caches, Trash, RAM"
        case .parameters: return "OnyX-Style Tweaks"
        case .security: return "SIP, Firewall, Privacy"
        case .automation: return "LaunchAgent, Schedule"
        case .log: return "Live-Ausgabe & history"
        case .info: return "Status & Versionen"
        }
    }
}

enum MaintenanceProfile: String, CaseIterable, Identifiable {
    case quick, auto, deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "Quick"
        case .auto: return "Auto (Daily)"
        case .deep: return "Deep (Weekly)"
        }
    }

    var detail: String {
        switch self {
        case .quick: return "Healer + Brew + Cleanup + Security · ~1–2 min"
        case .auto: return "Daily-fast Defaults · ~2–4 min"
        case .deep: return "Alles inkl. iCloud, Dev-Caches, Audits · 5–15 min"
        }
    }

    var flag: String { "--\(rawValue)" }
}
