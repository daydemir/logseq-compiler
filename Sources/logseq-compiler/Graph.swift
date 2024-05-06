//
//  Graph.swift
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

let notesFolder = "graph/"

typealias BlockID = Int
typealias BlockPath = String


struct ProcessedBlock {
    let block: Block
    let isPublic: Bool
    let children: [BlockID]
    let parent: [BlockID]
    let page: BlockID
    let hugoAdjustedContent: String
    let relationships: [Block.Relationship: [BlockID]]
    let backlinks: [BlockID]
}


struct Graph {
    
    var allContent: [HugoBlock] = []
    
    let assetsFolder: URL
    let destinationFolder: URL
    
    private let blocks: [BlockID: Block]
    private let blockPaths: [BlockID: BlockPath] = [:]
    private let children: [BlockID: [BlockID]] = [:]
    
    
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
        
        self.blocks = try json.arrayValue.reduce([BlockID: Block]()) { dict, json in
            guard let blockID = json[Block.Key.id.rawValue].int else { return dict }
            
            var dict = dict
            dict[blockID] = try Block(json)
            return dict
        }
        print("Found \(blocks.count) blocks.")
        
        print("Calculating block hierarchies...")
        self.blockPaths = blocks.mapValues { block in
            return notesFolder + (blocks.allAncestors(forBlock: block).map({ $0.pathComponent() }).joined(separator: "/"))
        }
        self.children = blocks.reduce([:]) { (result, block) in
            guard let parentID = block.value.parentID else { return result }
            var result = result
            result[parentID] = (result[parentID] ?? []) + [block.value.id]
            return result
        }
        print("Done calculating block hierarchies.")
        
        print("Calculating backlinks...")
        var backlinkIDs = [BlockID: [BlockID]]()
        blocks.forEach { blockPair in
                let parentInheritedLinkedIDs: [BlockID]
                if let parentID = blockPair.value.parentID, let parent = blocks[parentID] {
                    parentInheritedLinkedIDs = parent.inheritedLinkedIDs
                } else {
                    parentInheritedLinkedIDs = []
                }
                
                blockPair.value.linkedIDs
                    .filter { !parentInheritedLinkedIDs.contains($0) } //if parent links or inherits a link to this, no need to include this block as a backlink
                    .forEach { linkedID in
                        if let list = backlinkIDs[linkedID] {
                            backlinkIDs[linkedID] = list + [blockPair.value.id]
                        } else {
                            backlinkIDs[linkedID] = [blockPair.value.id]
                        }
                }
            }
        
        let backlinkPaths: [BlockID: [Block: BlockPath]] = backlinkIDs.mapValues { pair in
            pair.reduce([Block: BlockPath]()) { dict, id -> [Block: String] in
                guard let block = blocks[id] else { return dict }
                var dict = dict
                dict[block] = self.blockPaths[id]
                return dict
            }
        }
        print("Done calculating backlinks.")
        
        print("Calculating typed relationships...")
        let relationships: [BlockID: [Block.Relationship : [BlockID]]] =
            blocks
            .compactMap { block in
                if let relationship = block.value.extractRelationship() {
                    return (block.value, relationship)
                } else {
                    return nil
                }
            }.reduce([:]) { (result: [BlockID: [Block.Relationship : [BlockID]]], element: (Block, Block.Relationship)) in
                let block = element.0
                guard let parentID = block.parentID, let childrenIDs = children[block.id] else { return result}
                
                let relationship = element.1
                
                
                var result = result
                
                switch relationship.direction {
                case .leftToRight:
                    let existingValues = result[parentID]?[relationship]
                    result[parentID] = [relationship : (existingValues ?? []) + childrenIDs]
                case .rightToLeft:
                    for childrenID in childrenIDs {
                        let existingValues = result[childrenID]?[relationship]
                        result[childrenID] = [relationship : (existingValues ?? []) + [parentID]]
                    }
                }
                return result
            }
    
        print("Done calculating typed relationships.")
        
        
        print("Building relationships for blocks...")
        self.allContent = Graph.convertBlocks(blocks, blockPaths: self.blockPaths, backlinkPaths: backlinkPaths, typedRelationships: relationships, children: children)
        print("Done building relationships.")
    }
    
    static func convertBlocks(_ blocks: [BlockID: Block], blockPaths: [BlockID: BlockPath], backlinkPaths: [BlockID: [Block: BlockPath]], typedRelationships: [BlockID: [Block.Relationship : [BlockID]]], children: [BlockID: [BlockID]]) -> [HugoBlock] {
        blocks.compactMap { pair in
            
            guard let path = blockPaths[pair.key] else { return nil }
            
            let pageTuple: (Block, String)?
            if let page = blocks.page(forBlock: pair.value), let pagePath = blockPaths[page.id] {
                pageTuple = (page, pagePath)
            } else {
                pageTuple = nil
            }
            
            let parentTuple: BlockReference?
            if let parentID = pair.value.parentID, let parentPath = blockPaths[parentID.id] {
                parentTuple = (id: parentID, path: parentPath)
            } else {
                parentTuple = nil
            }
            
            let namespaceTuple: (Block, String)?
            if let namespace = blocks.namespace(forBlock: pair.value), let namespacePath = blockPaths[namespace.id] {
                namespaceTuple = (namespace, namespacePath)
            } else {
                namespaceTuple = nil
            }
            
            let links = blocks.links(forBlock: pair.value).reduce([Block: BlockPath]()) { dict, block in
                var dict = dict
                dict[block] = blockPaths[block.id]
                return dict
            }
            
            let aliases = blocks.aliases(forBlock: pair.value).reduce([Block: String]()) { dict, block in
                var dict = dict
                dict[block] = blockPaths[block.id]
                return dict
            }
            
            return HugoBlock(block: pair.value,
                             path: path,
                             siblingIndex: blocks.siblingIndex(forBlock: pair.value),
                             parentPath: parentTuple,
                             children: children[pair.key],
                             pagePath: pageTuple,
                             namespacePath: namespaceTuple,
                             linkPaths: links,
                             backlinkPaths: backlinkPaths[pair.key] ?? [:],
                             typedRelationships: typedRelationships[pair.key] ?? [:],
                             aliasPaths: aliases,
                             assets: AssetFinder.extractAssetNames(fromContent: pair.value.content ?? ""))
        }
    }
    
    
    
    func exportForHugo(assumePublic: Bool) throws {
        //empty destination folder
        try emptyDirectory(destinationFolder, except: [destinationFolder.appendingPathComponent("files", isDirectory: true)])
        
        print("Filtering public content...")
        
        if assumePublic {
            print("Assuming pages are public unless stated otherwise..")
        } else {
            print("Will only choose pages with public:: true")
        }
        let publicRegistry: [BlockID: Bool]
        let publicPages = allContent
            .filter { $0.block.isPage() && $0.isPublic(assumePublic: assumePublic) }.map { $0.block.id }
        
        publicRegistry = allContent.reduce([Int: Bool]()) { dict, superblock in
            var dict = dict
            if let explicitlyPublic = superblock.block.properties["public"].bool {
                dict[superblock.block.id] = explicitlyPublic
            } else if let pageID = superblock.block.pageID {
                dict[superblock.block.id] = publicPages.contains(pageID)
            } else {
                dict[superblock.block.id] = publicPages.contains(superblock.block.id)
            }
            return dict
        }
        

        let publishableContent = allContent.filter { publicRegistry[$0.block.id] ?? false }
            .map { $0.removePrivateLinks(publicRegistry: publicRegistry) }
        print("Found \(publishableContent.count) public blocks.")
        
        let publishablePages = publishableContent
            .filter { $0.block.isPage() }
        print("With \(publishablePages.count) public pages.")
        
        
        print("Exporting to files for Hugo...")
        //put home directly in content folder
        let homePage = publishablePages.first { $0.block.isHome() }
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
        let publishableAssets = publishableContent.flatMap { $0.assets }
        try FileManager.default.contentsOfDirectory(at: assetsFolder, includingPropertiesForKeys: nil)
            .filter { publishableAssets.contains($0.lastPathComponent) }
            .forEach { url in
                try FileManager.default.copyItem(at: url, to: assetsDestination.appendingPathComponent(url.lastPathComponent))
            }
        print("Done exporting assets.")
    }
    
    private func emptyDirectory(_ directory: URL, except: [URL]) throws {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).forEach { url in
            if !except.contains(url) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
    
    func getPath(forBlockID blockID: BlockID) -> BlockPath? {
        return self.blockPaths[blockID]
    }
    
    func getParentPath(forBlockID blockID: BlockID) -> BlockPath? {
        guard let parentID = self.blocks[blockID]?.parentID else { return nil }
        return self.blockPaths[parentID]
    }
    
    func getChildrenPaths(forBlockID blockID: BlockID) -> [BlockPath]? {
        return self.children[blockID]?
            .compactMap { $0 }
            .map { self.getPath(forBlockID: $0) }
            .compactMap { $0 }
    }
}

extension Array where Element == HugoBlock {
    
    func children(forBlock superblock: HugoBlock) -> [HugoBlock] {
        return filter { $0.parentPath?.id == superblock.block.id }
    }
}


typealias BlockReference = (id: BlockID, path: BlockPath)
