//
//  File.swift
//  
//
//  Created by Deniz Aydemir on 6/4/22.
//

import Foundation
import SwiftyJSON
import SwiftSlug

enum CompilerError: Error {
    case parsingError
}

let indexFile = "_index.md"
typealias Properties = JSON

let notesFolder = "notes"

struct Graph {
    
    var allContent: [HugoBlock] = []
    
    let assetsFolder: URL
    let destinationFolder: URL
    
    let blockPaths: [Block? : String]
    let blocks: Set<Block>
    
    init(jsonPath graphJSONPath: URL, assetsFolder: URL, destinationFolder: URL) {
        //https://github.com/logseq/logseq/blob/master/deps/graph-parser/src/logseq/graph_parser/db/schema.cljs
        
        //get all content
        // lq sq --graph demo '[:find (pull ?p [*]) :where (?p :block/uuid ?id)]' | pbcopy
        
        //use edn to json converter
        //https://github.com/borkdude/jet
        //populate data
        
        //convert all block references (and backlinks) to permalinks to block page
        //create a partial for showing a block, which includes hierarchy, content, and collapsible children
        
        
        //create all the blocks, map to [Block: [BlockWithExtraData]]
        // blocks.filter { isPage } .create section...
        
        //filter for public
        //    .filter { $0.properties.dictionaryValue["public"]?.boolValue == true }
        
        //this is the command
        //lq sq --graph demo '[:find (pull ?p [*]) :where (?p :block/uuid ?id)]' | jet --to json > ./export/graph.json

        self.assetsFolder = assetsFolder
        self.destinationFolder = destinationFolder
        
        //let cleanedGraphString = graphString.replacingOccurrences(of: "\n", with: "\\n")
        //let graphJSON = try! JSON(data: cleanedGraphString.data(using: .utf8)!)

        let json = try! JSON(data: String(contentsOf: graphJSONPath).data(using: .utf8)!)
        
        let blocks = Set(json.arrayValue.map { try! Block($0) })
        self.blockPaths = blocks.reduce([Block: String]()) {
            paths, block -> [Block: String] in
            
            var paths = paths
            paths[block] = ([notesFolder] + blocks.allAncestors(forBlock: block).map { $0.pathComponent() }).joined(separator: "/")
            return paths
        }
        
        self.blocks = blocks
        self.allContent = Graph.convertBlocks(blocks, blockPaths: self.blockPaths)
    }
    
    static func convertBlocks(_ blocks: Set<Block>, blockPaths: [Block?: String]) -> [HugoBlock] {
        blocks.compactMap { block in
            
            guard let path = blockPaths[block] else { return nil }
            
            let parentTuple: (Block, String)?
            if let parent = blocks.parent(forBlock: block), let parentPath = blockPaths[parent] {
                parentTuple = (parent, parentPath)
            } else {
                parentTuple = nil
            }
            
            let namespaceTuple: (Block, String)?
            if let namespace = blocks.namespace(forBlock: block), let namespacePath = blockPaths[namespace] {
                namespaceTuple = (namespace, namespacePath)
            } else {
                namespaceTuple = nil
            }
            
            
            let links = blocks.links(forBlock: block).reduce([Block: String]()) { dict, block in
                var dict = dict
                dict[block] = blockPaths[block]
                return dict
            }
            
            let backlinks = blocks.backlinks(forBlock: block).reduce([Block: String]()) { dict, block in
                var dict = dict
                dict[block] = blockPaths[block]
                return dict
            }
            
            let aliases = blocks.aliases(forBlock: block).reduce([Block: String]()) { dict, block in
                var dict = dict
                dict[block] = blockPaths[block]
                return dict
            }
            
            return HugoBlock(block: block,
                             path: path,
                             siblingIndex: blocks.siblings(forBlock: block).leftSiblings.count + 1,
                             parentPath: parentTuple,
                             namespacePath: namespaceTuple,
                             linkPaths: links,
                             backlinkPaths: backlinks,
                             aliasPaths: aliases)
        }
    }
    
    
    
    func exportForHugo() {
        //empty destination folder
        try! emptyDirectory(destinationFolder)
        
        let publishableContent = allContent
            .compactMap { $0.cleanForPublic(all: blocks) }
        
        let publishablePages = publishableContent
            .filter { $0.block.isPage() }
        
        //put home directly in content folder
        let homePage = publishablePages.first { $0.block.properties["home"].boolValue }
        if let homePage = homePage {
            homePage.createSection(inDirectory: destinationFolder, superblocks: publishableContent, blockFolder: false)
        }
        
        //create sections for blocks
        let notesDestination = destinationFolder.appendingPathComponent(notesFolder, isDirectory: true)
        try! FileManager.default.createDirectory(at: notesDestination, withIntermediateDirectories: true)
        publishablePages.filter { $0 != homePage }
            .forEach { $0.createSection(inDirectory: notesDestination, superblocks: publishableContent)}
        
        //move assets
        let assetsDestination = destinationFolder.appendingPathComponent("assets", isDirectory: true)
        try! FileManager.default.createDirectory(at: assetsDestination, withIntermediateDirectories: true)
        try! copyContents(from: assetsFolder, to: assetsDestination)
    }
    
    private func emptyDirectory(_ directory: URL) throws {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).forEach { url in
            try FileManager.default.removeItem(at: url)
        }
    }

    private func copyContents(from: URL, to: URL) throws {
        try FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil).forEach { url in
            try FileManager.default.copyItem(at: url, to: to.appendingPathComponent(url.lastPathComponent))
        }
    }
}

extension HugoBlock {
    
    func hugoProperties() -> JSON {
        var dict: [String: Any] = [:]
        
        if backlinkPaths.values.count > 0 {
            dict["backlinks"] = "\n - " + backlinkPaths.values.map {  "\"\($0)\"\n" }.joined(separator:" - ")
        }
        
        if aliasPaths.values.count > 0 {
            dict["aliases"] = aliasPaths.values
        }
        
        if let namespacePath = namespacePath?.1 {
            dict["namespace"] = namespacePath
        }
        
        if linkPaths.values.count > 0 {
            dict["links"] = "\n - " + linkPaths.values.map {  "\"\($0)\"\n" }.joined(separator:" - ")
        }
        
        return JSON(dict)
    }
    
    private func file() -> String {
        return hugoYAML() + hugoModifiedContent(content: block.content, readable: false)
    }
    
    private func hugoYAML() -> String {
        let headerContent = (block.properties.map { "\($0.0): \($0.1)\n"} + hugoProperties().map { "\($0.0): \($0.1)\n" } + ["logseq-type: \(block.isPage() ? "page" : "block")\nweight: \(siblingIndex)\n"]).joined(separator: "")
        return "---\n" + "title: \"\(readableName() ?? "Untitled")\"\n" + headerContent + "---\n"
    }
    
    //TODO: youtube, twitter
    func hugoModifiedContent(content: String?, readable: Bool) -> String {
        guard let content = content, content.count > 0 else { return "" }
        
        var updatedContent = content.replacingOccurrences(of: "(../assets/", with: "(/assets/")
        
        linkPaths.forEach { (linkedBlock, path) in
            if linkedBlock.isPage(), let name = linkedBlock.originalName ?? linkedBlock.name {
                LinkFinder.pageLinkChecks(name: name, path: path).forEach  { linkFinder in
                    updatedContent = linkFinder.makeContentHugoFriendly(updatedContent, noLinks: readable)
                }
            } else {
                //block
                let blockContent = linkedBlock.linkedIDs.count > 0 ? hugoModifiedContent(content: linkedBlock.content, readable: readable) : (linkedBlock.content ?? "")
                LinkFinder.blockLinkChecks(uuid: linkedBlock.uuid, content: blockContent, path: path).forEach { linkFinder in
                    updatedContent = linkFinder.makeContentHugoFriendly(updatedContent, noLinks: readable)
                }
            }
            
        }
        return updatedContent
    }
    
    func readableName() -> String? {
        if block.isPage() {
            return block.originalName ?? block.name
        } else {
            let content = hugoModifiedContent(content: block.content, readable: true)
            //use trimmed content since blocks don't have titles
            let trimmedContent: String
            let maxCharacterCount = 100
            
            if !content.contains("\n") && content.count < maxCharacterCount {
                trimmedContent = content
            } else {
                let firstLine = content.prefix(while: { $0 != "\n" })
                if firstLine.count > maxCharacterCount {
                    trimmedContent = firstLine.prefix(maxCharacterCount-3).split(separator: " ").dropLast().joined(separator: " ") + "..."
                } else {
                    trimmedContent = String(firstLine)
                }
            }
            
            return trimmedContent
        }
    }
}


extension Block {
    
    func isPublic() -> Bool {
        return properties["public"].boolValue
    }
    
    func showable() -> Bool {
        let isNotPagePropertiesAndHasContent = !preblock && (content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").count > 0
        return isPage() || isNotPagePropertiesAndHasContent
    }
    
    func isPage() -> Bool {
        return pageID == nil && parentID == nil
    }
    
    func pathComponent() -> String {
        let component: String
        if isPage() {
            component = (name ?? originalName ?? "\(id)")
        } else {
            component = uuid
        }
        
        do {
            return try component.convertedToSlug()
        } catch {
            return component.addingPercentEncoding(withAllowedCharacters: []) ?? component
        }
    }
    
}

extension Set where Element == Block {
    
    func allAncestors(forBlock block: Block) -> [Block] {
        guard let parent = self.parent(forBlock: block) else { return [block] }
        return self.allAncestors(forBlock: parent) + [block]
    }
    
    func parent(forBlock block: Block) -> Block? {
        guard let parentID = block.parentID else { return nil }
        return first { $0.id == parentID }
    }
    
    func page(forBlock block: Block) -> Block? {
        guard let pageID = block.pageID else { return nil }
        return first { $0.id == pageID }
    }
    
    func children(forBlock block: Block) -> [Block] {
        return filter { $0.parentID == block.id }
    }
    
    func namespace(forBlock block: Block) -> Block? {
        guard let namespaceID = block.namespaceID else { return nil }
        return first { $0.id == namespaceID }
    }
    
    func backlinks(forBlock block: Block) -> [Block] {
        return filter { $0.linkedIDs.contains(block.id) }
    }
    
    func links(forBlock block: Block) -> [Block] {
        return filter { block.linkedIDs.contains($0.id) }
    }
    
    func aliases(forBlock block: Block) -> [Block] {
        return filter { block.aliasIDs.contains($0.id) }
    }
    
    func siblings(forBlock block: Block) -> (leftSiblings: [Block], rightSiblings: [Block]) {
        var leftSiblings: [Block] = []
        var leftmostSibling: Block = block
        
        while let nextLeftID = leftmostSibling.leftID, let nextLeft = first(where: { $0.id == nextLeftID }) {
            leftSiblings.insert(nextLeft, at: 0)
            leftmostSibling = nextLeft
        }
        
        var rightSiblings: [Block] = []
        var rightmostSibling: Block = block
        
        while let nextRight = first(where: { $0.leftID == rightmostSibling.id }) {
            rightSiblings.append(nextRight)
            rightmostSibling = nextRight
        }
        
        return (leftSiblings: leftSiblings, rightSiblings: rightSiblings)
    }
}
extension Array where Element == HugoBlock {
    
    func children(forBlock superblock: HugoBlock) -> [HugoBlock] {
        return filter { $0.parentPath?.0 == superblock.block }
    }
}


struct HugoBlock: Hashable {
    
    let block: Block
    let path: String
    let siblingIndex: Int
    
    let parentPath: (Block, String)?
    let namespacePath: (Block, String)?
    
    let linkPaths: [Block: String]
    let backlinkPaths: [Block: String]
    let aliasPaths: [Block: String]
    
    func createSection(inDirectory directory: URL, superblocks: [HugoBlock], blockFolder: Bool = true) {
        guard block.showable() else { return }

        let blockDirectory = blockFolder ? directory.appendingPathComponent(block.pathComponent()) : directory
        try! FileManager.default.createDirectory(at: blockDirectory, withIntermediateDirectories: true)
        try! file().write(to: blockDirectory.appendingPathComponent(indexFile), atomically: true, encoding: .utf8)
        superblocks.children(forBlock: self).forEach { $0.createSection(inDirectory: blockDirectory, superblocks: superblocks) }
    }
    
    private func checkBlockIsPublic(block: Block, all: Set<Block>) -> Bool {
        return (block.isPage() && block.isPublic()) || (all.page(forBlock: block)?.isPublic() ?? false)
    }
    
    func cleanForPublic(all: Set<Block>) -> HugoBlock? {
        guard checkBlockIsPublic(block: block, all: all) else {
            return nil
        }
        
        
        return HugoBlock(block: block,
                         path: path,
                         siblingIndex: siblingIndex,
                         parentPath: parentPath,
                         namespacePath: namespacePath,
                         linkPaths: linkPaths.filter { checkBlockIsPublic(block: $0.key, all: all) },
                         backlinkPaths: backlinkPaths.filter { checkBlockIsPublic(block: $0.key, all: all) },
                         aliasPaths: aliasPaths)
    }
    
    static func == (lhs: HugoBlock, rhs: HugoBlock) -> Bool {
        return lhs.block == rhs.block
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(block)
    }
}

enum LinkFinder {
    
    case pageEmbed(name: String, path: String)
    case pageAlias(name: String, path: String)
    case pageReference(name: String, path: String)
    
    case blockEmbed(uuid: String, content: String, path: String)
    case blockAlias(uuid: String, content: String, path: String)
    case blockReference(uuid: String, content: String, path: String)
    
    static func pageLinkChecks(name: String, path: String) -> [LinkFinder] {
        //order matters
        return [
            LinkFinder.pageEmbed(name: name, path: path),
            LinkFinder.pageAlias(name: name, path: path),
            LinkFinder.pageReference(name: name, path: path)
        ]
    }
    
    static func blockLinkChecks(uuid: String, content: String, path: String) -> [LinkFinder] {
        //order matters
        return [
            LinkFinder.blockEmbed(uuid: uuid, content: content, path: path),
            LinkFinder.blockAlias(uuid: uuid, content: content, path: path),
            LinkFinder.blockReference(uuid: uuid, content: content, path: path)
        ]
    }
    
    func pattern() -> String {
        switch self {
        case .pageEmbed(let name, _):
            return #"\{\{embed\s*\[\[\s*"# + name + #"\s*\]\]\s*\}\}"#
        case .pageAlias(let name, _):
            return #"\]\(\s*\[\[\s*"# + name + #"\s*\]\]s*\)"#
        case .pageReference(let name, _):
            return #"\[\[\s*"# + name + #"\s*\]\]"#
            
        case .blockEmbed(let uuid, _, _):
            return #"\{\{embed\s*\(\(\s*"# + uuid + #"\s*\)\)\s*\}\}"#
        case .blockAlias(let uuid, _, _):
            return #"\]\(\s*\(\(\s*"# + uuid + #"\s*\)\)\s*\)"#
        case .blockReference(let uuid, _, _):
            return #"\(\(\s*"# + uuid + #"\s*\)\)"#
        }
    }
    
    func readable() -> String { //TODO: add a version that adds plain links
        switch self {
        case .pageEmbed(let name, _):
            return "[[\(name)]]"
        case .pageAlias:
            return "]"
        case .pageReference(let name, _):
            return "[[\(name)]]"
            
            
        case .blockEmbed(_, let content, _):
            return content
        case .blockAlias:
            return "]"
        case .blockReference(_, let content, _):
            return shortenedBlockContent(content: content)
        }
    }
    
    private func shortenedBlockContent(content: String) -> String {
        if let firstLine = content.split(separator: "\n").first {
            return String(firstLine)
        } else {
            return content
        }
    }
    
    func hugoFriendlyLink() -> String {
        switch self {
        case .pageEmbed(_, let path):
            return "{{< links/page-embed \"\(path)\" >}}"
        case .pageAlias(_, let path):
            return "](\(path))"
        case .pageReference(let name, let path):
            return "[\(name)](\(path))"
            
            
        case .blockEmbed(_, _, let path):
            return "{{< links/block-embed \"\(path)\" >}}"
        case .blockAlias(_, _, let path):
            return "](\(path))"
        case .blockReference(_, let content, let path):
            return "[\(shortenedBlockContent(content: content))](\(path))"
        }
    }
    
    func ranges(inContent content: String) -> [NSRange] {
        let regex = try! NSRegularExpression(pattern: self.pattern(), options: .caseInsensitive)
        return regex.matches(in: content, options: .reportCompletion, range: NSRange(content.startIndex..<content.endIndex, in: content)).map { (result: NSTextCheckingResult) in
            return result.range
        }
    }
    
    func makeContentHugoFriendly(_ content: String, noLinks: Bool) -> String {
        var updatedContent = content as NSString
        
        ranges(inContent: content).forEach { range in
            let replacement = noLinks ? readable() : hugoFriendlyLink()
            updatedContent = updatedContent.replacingCharacters(in: range, with: replacement) as NSString
        }
        
        return updatedContent as String
    }
}

struct Block: Hashable {
    
    enum Key: String {
        case uuid = "block/uuid"
        case id = "db/id"
        
        case name = "block/name"
        case originalName = "block/original-name"
        case content = "block/content"
        
        
        case pageID = "block/page"
        case parentID = "block/parent"
        case leftID = "block/left"
        case namespaceID = "block/namespace"
        
        case properties = "block/properties"
        case preblock = "block/pre-block?"
        case format = "block/format"
        
        case updatedAt = "block/updated-at"
        case createdAt = "block/created-at"
        
        case refs = "block/refs"
        case pathRefs = "block/path-refs"
        case alias = "block"
    }
    
    let uuid: String
    let id: Int
    
    let name: String?
    let originalName: String?
    let content: String?
    
    let pageID: Int?
    let parentID: Int?
    let leftID: Int?
    let namespaceID: Int?
    
    let properties: Properties
    let preblock: Bool
    let format: String?
    
    let updatedAt: TimeInterval?
    let createdAt: TimeInterval?
    
    let linkedIDs: [Int]
    let inheritedLinkedIDs: [Int]
    let aliasIDs: [Int]
    
    init(_ json: JSON) throws {
        guard let id = json[Key.id.rawValue].int,
              let uuid = json[Key.uuid.rawValue].string
        else { throw CompilerError.parsingError }
        
        self.uuid = uuid
        self.id = id
        
        
        self.name = json[Key.name.rawValue].string
        self.originalName = json[Key.originalName.rawValue].string
        self.content = json[Key.content.rawValue].string
        
        self.pageID = json[Key.pageID.rawValue][Key.id.rawValue].int
        self.parentID = json[Key.parentID.rawValue][Key.id.rawValue].int
        self.leftID = json[Key.leftID.rawValue][Key.id.rawValue].int
        self.namespaceID = json[Key.namespaceID.rawValue][Key.id.rawValue].int
        
        self.properties = json[Key.properties.rawValue]
        self.preblock = json[Key.preblock.rawValue].boolValue
        self.format = json[Key.format.rawValue].string
        
        self.updatedAt = json[Key.updatedAt.rawValue].double
        self.createdAt = json[Key.createdAt.rawValue].double
        
        self.linkedIDs = json[Key.refs.rawValue].arrayValue.compactMap { $0[Key.id.rawValue].int }
        self.inheritedLinkedIDs = json[Key.pathRefs.rawValue].arrayValue.compactMap { $0[Key.id.rawValue].int }
        self.aliasIDs = json[Key.alias.rawValue].arrayValue.compactMap { $0[Key.id.rawValue].int }
    }
    
    static func == (lhs: Block, rhs: Block) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}
