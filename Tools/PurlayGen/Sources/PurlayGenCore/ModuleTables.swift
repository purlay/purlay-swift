import Foundation

/// The server's module manifest and its owners by endpoint ID, client operation, and server event.
enum ModuleTables {
    static func generate(_ root: JSON, declarations: [Declaration], header: String) throws -> String? {
        let keys = ["modules", "frameOwners", "eventOwners"]
        guard keys.contains(where: { root[$0] != nil }) else { return nil }
        guard let modules = root["modules"] as? [JSON], let endpoints = root["endpoints"] as? [JSON],
            let frameOwners = root["frameOwners"] as? [String: String],
            let eventOwners = root["eventOwners"] as? [String: String]
        else { throw GenerationError("contract.json has incomplete module ownership") }

        let ids = Set(modules.compactMap { $0["id"] as? String })
        guard ids.count == modules.count, !ids.contains("core"), !ids.contains("") else {
            throw GenerationError("contract.json module IDs must be unique and cannot be empty or core")
        }
        var endpointOwners: [String: String] = [:]
        for endpoint in endpoints {
            guard let id = endpoint["id"] as? String, let owner = endpoint["module"] as? String else {
                throw GenerationError("a contract endpoint is missing its ID or module owner")
            }
            guard endpointOwners.updateValue(owner, forKey: id) == nil else {
                throw GenerationError("duplicate endpoint ID: \(id)")
            }
        }

        var out =
            header + """
                /// The owner of a route or frame. Core exists on every server and is not a module ID.
                public enum ModuleOwner: Sendable, Hashable {
                    case core
                    case module(ModuleId)
                }

                /// What the bundle says a server module owns. Its presence here does not say the connected server runs it.
                public struct ModuleSpec: Sendable, Hashable {
                    public let id: ModuleId
                    public let requires: [ModuleId]
                    public let optional: [ModuleId]
                    public let routes: [String]
                    public let frames: [String]
                    public let events: [String]
                    public let notificationTypes: [String]
                }

                public enum ModuleOwnership {

                """
        out += try moduleSpecs(modules)
        out += try owners(endpointOwners, name: "endpointOwners", modules: ids)
        out += try owners(frameOwners, name: "frameOwners", modules: ids)
        out += try owners(eventOwners, name: "eventOwners", modules: ids)
        out += "}\n"
        out += """

            public extension EndpointSpec {
                /// The owner recorded for this endpoint ID in the bundle.
                var moduleOwner: ModuleOwner? { ModuleOwnership.endpointOwners[id] }
            }

            """
        for declaration in declarations {
            guard case .tagged(let frame) = declaration else { continue }
            switch frame.name {
            case "ClientFrame": out += try frameExtension(frame, owners: frameOwners, table: "frameOwners")
            case "ServerFrame": out += try frameExtension(frame, owners: eventOwners, table: "eventOwners")
            default: break
            }
        }
        return out
    }

    private static func moduleSpecs(_ definitions: [JSON]) throws -> String {
        var out = "    public static let modules: [ModuleId: ModuleSpec] = "
        guard !definitions.isEmpty else { return out + "[:]\n\n" }
        out += "[\n"
        let names = ["requires", "optional", "routes", "frames", "events", "notificationTypes"]
        for definition in definitions {
            guard let id = definition["id"] as? String else { throw GenerationError("a module is missing its ID") }
            let reference = module(id)
            out += "        \(reference): ModuleSpec(\n            id: \(reference),\n"
            var fields: [String] = []
            for name in names {
                guard let entries = definition[name] as? [String] else {
                    throw GenerationError("module \(id) is missing its \(name) list")
                }
                let values = entries.map(name == "requires" || name == "optional" ? module : quoted)
                fields.append("            \(name): [\(values.joined(separator: ", "))]")
            }
            out += fields.joined(separator: ",\n") + "),\n"
        }
        return out + "    ]\n\n"
    }

    private static func owners(_ entries: [String: String], name: String, modules: Set<String>) throws -> String {
        var out = "    public static let \(name): [String: ModuleOwner] = "
        guard !entries.isEmpty else { return out + "[:]\n\n" }
        out += "[\n"
        for (key, owner) in entries.sorted(by: { $0.key < $1.key }) {
            guard owner == "core" || modules.contains(owner) else {
                throw GenerationError("\(name).\(key) refers to undeclared module \(owner)")
            }
            out += "        \(quoted(key)): \(owner == "core" ? ".core" : ".module(\(module(owner)))"),\n"
        }
        return out + "    ]\n\n"
    }

    private static func frameExtension(_ frame: TaggedUnion, owners: [String: String], table: String) throws -> String {
        if let missing = frame.cases.first(where: { owners[$0.literal] == nil }) {
            throw GenerationError("\(table) has no owner for \(missing.literal)")
        }
        var out = "\npublic extension \(frame.name) {\n"
        out +=
            "    /// The owner recorded for this known wire tag. A frame this client cannot interpret has no known owner.\n"
        out += "    var moduleOwner: ModuleOwner? {\n        switch self {\n"
        for item in frame.cases {
            out += "        case .\(item.name): ModuleOwnership.\(table)[\(quoted(item.literal))]\n"
        }
        out += "        case .\(frame.catchAll?.name ?? frame.fallbackName): nil\n"
        return out + "        }\n    }\n}\n"
    }

    private static func quoted(_ value: String) -> String { "\"\(Literal.escaped(value))\"" }

    private static func module(_ id: String) -> String { "ModuleId(rawValue: \(quoted(id)))" }
}
