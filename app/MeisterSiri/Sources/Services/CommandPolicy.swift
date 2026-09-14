import Foundation

/// Only this policy can create a command that the GUI runner will execute.
enum CommandPolicy {
    struct PreparedCommand {
        let arguments: [String]
        let isPreview: Bool
        fileprivate init(arguments: [String], isPreview: Bool) {
            self.arguments = arguments
            self.isPreview = isPreview
        }
    }

    enum Decision {
        case allowed(PreparedCommand)
        case blocked(String)
    }

    private enum Capability {
        case inspection
        case preview(String)
        case changesSystem
    }

    static func prepare(arguments: [String], dryRun: Bool, supportsAIPreview: Bool = false, supportsProfilePreview: Bool = false) -> Decision {
        let requestedPreview = dryRun || arguments.contains("-n") || arguments.contains("--dry-run")
        let args = arguments.filter { $0 != "-n" && $0 != "--dry-run" }
        guard let capability = capability(for: args) else {
            return .blocked("Aktion nicht freigegeben: \(args.joined(separator: " ")). Es wurde nichts gestartet.")
        }
        if requestedPreview, args.count == 1, ["--quick", "--auto", "--deep"].contains(args[0]), !supportsProfilePreview {
            return .blocked("Dry-Run: Diese CLI unterstützt noch keine sichere Profilvorschau. Bitte meisterSiri aktualisieren.")
        }
        if args == ["ai"], requestedPreview, supportsAIPreview {
            return .allowed(PreparedCommand(arguments: ["ai", "--dry-run"], isPreview: true))
        }
        switch capability {
        case .inspection:
            return .allowed(PreparedCommand(arguments: args, isPreview: requestedPreview))
        case .preview(let flag):
            return .allowed(PreparedCommand(arguments: args + (requestedPreview ? [flag] : []), isPreview: requestedPreview))
        case .changesSystem:
            guard !requestedPreview else {
                return .blocked("Dry-Run: „\(args.joined(separator: " "))“ unterstützt keine sichere Vorschau und wurde gesperrt. Es wurde nichts geändert.")
            }
            return .allowed(PreparedCommand(arguments: args, isPreview: false))
        }
    }

    static func permitsProbe(arguments: [String]) -> Bool {
        if case .inspection = capability(for: arguments) { return true }
        return false
    }

    static func configurationCreation(dryRun: Bool) -> Decision {
        dryRun ? .blocked("Dry-Run: Die fehlende Konfigurationsdatei wird nicht angelegt. Es wurde nichts geändert.")
            : .allowed(PreparedCommand(arguments: [], isPreview: false))
    }

    private static func capability(for args: [String]) -> Capability? {
        if args.count == 1 {
            switch args[0] {
            case "doctor", "today", "score", "-H", "privacy", "startup", "tcc-clean", "appupdates", "disk", "--version":
                return .inspection
            case "--quick", "--auto", "--deep": return .preview("-n")
            case "autofix", "heal", "orphans", "simfix": return .preview("--dry-run")
            // Old installed CLIs ignore dry-run for ai/free and these setup commands.
            case "ai", "free", "sudo-setup", "touchid", "-I", "selftest": return .changesSystem
            default: break
            }
        }
        if args == ["bloatware", "scan"] || args == ["ai", "--diagnose-only"] || args == ["doctor", "--json"] || args == ["report", "--json"] {
            return .inspection
        }
        if args == ["bloatware", "kill", "--p0"] { return .preview("--dry-run") }
        if args == ["free", "--restart-ui"] { return .changesSystem }
        let tweaks = ["showhidden", "extensions", "pathbar", "keyrepeat", "savepanel", "dockfast", "screenshots-jpg"]
        if args.count == 3, args[0] == "tweaks", tweaks.contains(args[1]), ["on", "off"].contains(args[2]) {
            return .changesSystem
        }
        return nil
    }
}
