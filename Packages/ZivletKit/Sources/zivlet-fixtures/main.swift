import Foundation

/// `zivlet-fixtures --set small|full|hostile --out <absolute dir>`: writes the image fixtures of one set into
/// `<dir>` and lists them on stdout, one `<name> hash|probe` line each (Fixtures/generate.sh hashes the `hash`
/// ones). Not shipped; not a gated module.
enum FixtureTool {
    static let usage = "zivlet-fixtures --set small|full|hostile --out <absolute directory>"

    static func run(_ arguments: [String]) throws(FixtureError) -> [String] {
        let (set, out) = try parse(arguments)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        } catch {
            throw .writing(out.lastPathComponent)
        }
        let recipes = set.name == FixtureSet.hostile.name ? HostileImages.all : ImageRecipes.all
        for recipe in recipes {
            try recipe.make(set, out.appending(path: recipe.name))
        }
        return recipes.map { "\($0.name) \(ImageRecipes.unhashed.contains($0.name) ? "probe" : "hash")" }
    }

    static func parse(_ arguments: [String]) throws(FixtureError) -> (FixtureSet, URL) {
        var options: [String: String] = [:]
        var rest = arguments[...]
        while let flag = rest.popFirst() {
            guard ["--set", "--out"].contains(flag), let value = rest.popFirst() else { throw .usage(usage) }
            options[flag] = value
        }
        guard let set = FixtureSet.named(options["--set"] ?? "small"), let path = options["--out"],
            path.hasPrefix("/"), !path.split(separator: "/").contains("..")
        else { throw .usage(usage) }
        return (set, URL(fileURLWithPath: path, isDirectory: true))
    }
}

do {
    let names = try FixtureTool.run(Array(CommandLine.arguments.dropFirst()))
    FileHandle.standardOutput.write(Data((names.joined(separator: "\n") + "\n").utf8))
} catch {
    FileHandle.standardError.write(Data("zivlet-fixtures: \(error.description)\n".utf8))
    exit(1)
}
