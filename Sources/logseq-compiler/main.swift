import ArgumentParser
import Foundation

struct LogseqCompiler: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "logseq-compiler takes a JSON export of Logseq blocks and compiles them into .md files suitable for publishing on Hugo")
    
    
    @Argument(help: "Path to Logseq graph JSON", completion: CompletionKind.directory)
    private var graphJSONPath: String
    
    @Argument(help: "Path to Logseq assets folder", completion: CompletionKind.directory)
    private var assetsFolderPath: String
    
    @Argument(help: "Hugo content folder", completion: CompletionKind.directory)
    private var destinationFolderPath: String
    
    enum Error: String, Swift.Error {
        case badPath
    }
    
    func run() throws {
        print("Beginning compilation...")

        let json = URL.init(fileURLWithPath: graphJSONPath, isDirectory: false)
        let assets = URL.init(fileURLWithPath: assetsFolderPath, isDirectory: true)
        let destination = URL.init(fileURLWithPath: destinationFolderPath, isDirectory: true)
        
        Graph(jsonPath: json, assetsFolder: assets, destinationFolder: destination)
            .exportForHugo()
        
        print("Done!")
    }
}


LogseqCompiler.main()
