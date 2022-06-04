//
//  File.swift
//  
//
//  Created by Deniz Aydemir on 6/4/22.
//

import Foundation
import SwiftyJSON
import SwiftSlug
import Yams

enum CompilerError: Error {
    case parsingError
}

let indexFile = "_index.md"
typealias Properties = JSON

let notesFolder = "notes/"

struct Graph {
    
    var allContent: [HugoBlock] = []
    
    let assetsFolder: URL
    let destinationFolder: URL
    
    let blockPaths: [Int: String]
    let blocks: [Int: Block]
    
    init(jsonPath graphJSONPath: URL, assetsFolder: URL, destinationFolder: URL) throws {
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
        
        print("Loading blocks...")
        let blocks = try json.arrayValue.reduce([Int:Block]()) { dict, json in
            guard let blockID = json[Block.Key.id.rawValue].int else { return dict }
            
            var dict = dict
            dict[blockID] = try Block(json)
            return dict
        }
//            .map { try! Block($0) }
        print("Found \(blocks.count) blocks.")
        
        print("Calculating block hierarchies...")
        self.blockPaths = blocks.mapValues { block in
            return notesFolder + (blocks.allAncestors(forBlock: block).map({ $0.pathComponent() }).joined(separator: "/"))
        }
        print("Done calculating block hierarchies.")
        
        
        print("Building relationships for blocks...")
        self.blocks = blocks
        self.allContent = Graph.convertBlocks(blocks, blockPaths: self.blockPaths)
        print("Done building relationships.")
    }
    
    static func convertBlocks(_ blocks: [Int: Block], blockPaths: [Int: String]) -> [HugoBlock] {
        blocks.compactMap { pair in
            
            guard let path = blockPaths[pair.key] else { return nil }
            
            let pageTuple: (Block, String)?
            if let page = blocks.page(forBlock: pair.value), let pagePath = blockPaths[page.id] {
                pageTuple = (page, pagePath)
            } else {
                pageTuple = nil
            }
            
            let parentTuple: (Block, String)?
            if let parent = blocks.parent(forBlock: pair.value), let parentPath = blockPaths[parent.id] {
                parentTuple = (parent, parentPath)
            } else {
                parentTuple = nil
            }
            
            let namespaceTuple: (Block, String)?
            if let namespace = blocks.namespace(forBlock: pair.value), let namespacePath = blockPaths[namespace.id] {
                namespaceTuple = (namespace, namespacePath)
            } else {
                namespaceTuple = nil
            }
            
            let links = blocks.links(forBlock: pair.value).reduce([Block: String]()) { dict, block in
                var dict = dict
                dict[block] = blockPaths[block.id]
                return dict
            }
            
//            let backlinks = blocks.backlinks(forBlock: pair.value).reduce([Block: String]()) { dict, block in
//                var dict = dict
//                dict[block] = blockPaths[block.id]
//                return dict
//            }
            
            let aliases = blocks.aliases(forBlock: pair.value).reduce([Block: String]()) { dict, block in
                var dict = dict
                dict[block] = blockPaths[block.id]
                return dict
            }
            
            return HugoBlock(block: pair.value,
                             path: path,
                             siblingIndex: 1,// blocks.siblings(forBlock: pair.value).leftSiblings.count + 1,
                             parentPath: parentTuple,
                             pagePath: pageTuple,
                             namespacePath: namespaceTuple,
                             linkPaths: links,
                             backlinkPaths: [:],//backlinks,
                             aliasPaths: aliases)
        }
    }
    
    
    
    func exportForHugo() throws {
        //empty destination folder
        try emptyDirectory(destinationFolder)

        print("Filtering public content...")
        let publishableContent = allContent.filter { $0.isPublic() }
//            .compactMap { $0.cleanForPublic(all: blocks) }
        print("Found \(publishableContent.count) public blocks.")
        
        let publishablePages = publishableContent
            .filter { $0.block.isPage() }
        print("With \(publishablePages.count) public pages.")
        
        
        print("Exporting to files for Hugo...")
        //put home directly in content folder
        let homePage = publishablePages.first { $0.block.properties["home"].boolValue }
        if let homePage = homePage {
            try homePage.createSection(inDirectory: destinationFolder, superblocks: publishableContent, blockFolder: false)
        }
        print("Exported home page.")
        
        //create sections for blocks
        let notesDestination = destinationFolder.appendingPathComponent(notesFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: notesDestination, withIntermediateDirectories: false)
        try publishablePages
            .filter { $0 != homePage }
            .forEach { try $0.createSection(inDirectory: notesDestination, superblocks: publishableContent)}
        print("Done exporting files.")
        
        print("Exporting assets...")
        //move public assets
        let assetsDestination = destinationFolder.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDestination, withIntermediateDirectories: true)
        try FileManager.default.contentsOfDirectory(at: assetsFolder, includingPropertiesForKeys: nil)
            .filter { assetURL in
                publishableContent.first { $0.block.content?.contains(assetURL.lastPathComponent) ?? false } != nil
            }
            .forEach { url in
                try FileManager.default.copyItem(at: url, to: assetsDestination.appendingPathComponent(url.lastPathComponent))
            }
        print("Done exporting assets.")
    }
    
    private func emptyDirectory(_ directory: URL) throws {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).forEach { url in
            try FileManager.default.removeItem(at: url)
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
        let yamlProperties: String
        if !block.properties.dictionaryValue.keys.isEmpty {
            yamlProperties = try! YAMLEncoder().encode(block.properties.dictionaryValue)
        } else {
            yamlProperties = ""
        }
        
        if yamlProperties.split(separator: "\n").contains("null") {
            print("null found when converting properties to YAML")
        }
        
        let hugo = hugoProperties().map { "\($0.0): \($0.1)\n" }.joined(separator: "")
        let extras = "logseq-type: \(block.isPage() ? "page" : "block")\nweight: \(siblingIndex)\n"
        
        let headerContent = yamlProperties + "\n" + hugo + extras
        let readableName = readableName()
        
        return "---\n" + "title: \"\(readableName ?? "Untitled")\"\n" + headerContent + "---\n"
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
                //this is where we would need to deal with parsing nested block references
//                let blockContent = linkedBlock.linkedIDs.count > 0 ? hugoModifiedContent(content: linkedBlock.content, readable: readable) : (linkedBlock.content ?? "")
                let blockContent = linkedBlock.content ?? ""
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

extension Dictionary where Key == Int, Value == Block {
    
    func allAncestors(forBlock block: Block) -> [Block] {
        guard let parent = self.parent(forBlock: block) else { return [block] }
        return self.allAncestors(forBlock: parent) + [block]
    }
    
    func parent(forBlock block: Block) -> Block? {
        guard let parentID = block.parentID else { return nil }
        return self[parentID]
    }
    
    func page(forBlock block: Block) -> Block? {
        guard let pageID = block.pageID else { return nil }
        return self[pageID]
    }
    
    func namespace(forBlock block: Block) -> Block? {
        guard let namespaceID = block.namespaceID else { return nil }
        return self[namespaceID]
    }
    
    func backlinks(forBlock block: Block) -> [Block] {
        return filter { $0.value.linkedIDs.contains(block.id) }.map { $0.value }
    }
    
    func links(forBlock block: Block) -> [Block] {
        return block.linkedIDs.compactMap { self[$0] }
    }
    
    func aliases(forBlock block: Block) -> [Block] {
        return block.aliasIDs.compactMap { self[$0] }
    }
    
    func siblings(forBlock block: Block) -> (leftSiblings: [Block], rightSiblings: [Block]) {
        var leftSiblings: [Block] = []
        var leftmostSibling: Block = block
        
        while let nextLeftID = leftmostSibling.leftID, let nextLeft = self[nextLeftID] {
            leftSiblings.insert(nextLeft, at: 0)
            leftmostSibling = nextLeft
        }
        
        var rightSiblings: [Block] = []
        var rightmostSibling: Block = block
        
        while let nextRight = first(where: { $0.value.leftID == rightmostSibling.id }).map({ $0.value }) {
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
    let pagePath: (Block, String)?
    let namespacePath: (Block, String)?
    
    let linkPaths: [Block: String]
    let backlinkPaths: [Block: String]
    let aliasPaths: [Block: String]
    
    func createSection(inDirectory directory: URL, superblocks: [HugoBlock], blockFolder: Bool = true) throws {
        guard block.showable() else { return }
        
        let files = FileManager.default
        let blockDirectory = blockFolder ? directory.appendingPathComponent(block.pathComponent()) : directory
        let indexFilePath = blockDirectory.appendingPathComponent(indexFile)
        
        if files.fileExists(atPath: blockDirectory.path) {
            print("Avoiding creating duplicate directory at " + blockDirectory.absoluteString)
        } else {
            try files.createDirectory(at: blockDirectory, withIntermediateDirectories: true)
        }
        
        if files.fileExists(atPath: indexFilePath.path) {
            print("Avoiding creating duplicate index file at " + indexFilePath.absoluteString)
        } else {
            files.createFile(atPath: indexFilePath.path, contents: file().data(using: .utf8))
        }
        
        try superblocks.children(forBlock: self)
            .forEach {
                try $0.createSection(inDirectory: blockDirectory, superblocks: superblocks)
            }
        
    }
    
    func isPublic() -> Bool {
        return block.isPublic() || (pagePath?.0.isPublic() ?? false)
    }
    
    //unused currently
//    private func checkBlockIsPublic(block: Block, all: [Int: Block]) -> Bool {
//        return (block.isPage() && block.isPublic()) || (all.page(forBlock: block)?.isPublic() ?? false)
//    }
    
    //unused currently
//    func cleanForPublic(all: Set<Block>) -> HugoBlock? {
//        guard checkBlockIsPublic(block: block, all: all) else {
//            return nil
//        }
//
//        return HugoBlock(block: block,
//                         path: path,
//                         siblingIndex: siblingIndex,
//                         parentPath: parentPath,
//                         pagePath: pagePath,
//                         namespacePath: namespacePath,
//                         linkPaths: linkPaths.filter { checkBlockIsPublic(block: $0.key, all: all) },
//                         backlinkPaths: backlinkPaths.filter { checkBlockIsPublic(block: $0.key, all: all) },
//                         aliasPaths: aliasPaths)
//    }
    
    static func == (lhs: HugoBlock, rhs: HugoBlock) -> Bool {
        return lhs.block == rhs.block
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(block)
    }
}
