import Foundation

exit(TracesTool.run(arguments: Array(CommandLine.arguments.dropFirst())) { TracesTool.write($0) })
