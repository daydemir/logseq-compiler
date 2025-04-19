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
    
    @Option(name: .shortAndLong, parsing: .next, help: "Assume public unless block states otherwise (public:: false). By default this is off and blocks are required to have public:: true to be included in published content.", completion: nil)
    private var assumePublic: Bool
    
    enum Error: String, Swift.Error {
        case badPath
    }
    
    func run() throws {
        print("Beginning compilation...")

        let json = URL.init(fileURLWithPath: graphJSONPath, isDirectory: false)
        let assets = URL.init(fileURLWithPath: assetsFolderPath, isDirectory: true)
        let destination = URL.init(fileURLWithPath: destinationFolderPath, isDirectory: true)
        
        do {
            try Graph(jsonPath: json, assetsFolder: assets, destinationFolder: destination)
                .exportForHugo(assumePublic: assumePublic)
            
            print("Done!")
        } catch {
            print(error.localizedDescription)
        }
    }
    
    static func test() -> LogseqCompiler {
        //swift run logseq-compiler ~/Build/notes/life/.export/graph.json ~/Build/notes/life/assets ~/Build/graph/interface-web/content --assume-public=false
        
        var compiler = LogseqCompiler()
        compiler.graphJSONPath = "~/Build/notes/life/.export/graph.json"
        compiler.assetsFolderPath = "~/Build/notes/life/assets"
        compiler.destinationFolderPath = "~/Build/graph/interface-web/content"
        compiler.assumePublic = false
        return compiler
    }
}


LogseqCompiler.main()

//try LogseqCompiler.test().run()
