//
//  HugoBlock.swift
//  
//
//  Created by Deniz Aydemir on 4/8/23.
//

import Foundation
import SwiftyJSON
import Yams

struct HugoBlock: Hashable {
    
    let block: Block
    let path: BlockPath
    let siblingIndex: Int
    
    let parentPath: BlockReference?
    let children: [BlockReference]?
    let pagePath: BlockReference?
    let namespacePath: BlockReference?
    
    let linkPaths: [BlockReference]
    let backlinkPaths: [BlockReference]
    let typedRelationships: [Block.Relationship: [BlockReference]]
    let aliasPaths: [BlockReference]
    
    let assets: [String]
    
    let processedContent: String
    
    let graph: Graph
    
    func createSection(inDirectory directory: URL, superblocks: [HugoBlock], links: [LinkInfo], blockFolder: Bool = true) throws {
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
            files.createFile(atPath: indexFilePath.path, contents: file(links: links).data(using: .utf8))
        }
        
        try superblocks.children(forBlock: self)
            .forEach {
                try $0.createSection(inDirectory: blockDirectory, superblocks: superblocks, )
            }
        
    }
    
    func removePrivateLinks(publicRegistry: [BlockID: Bool]) -> HugoBlock {
        
        let cleanedLinkPaths = linkPaths.map { linkPath in
            let isPublic = publicRegistry[linkPath.id] ?? false
            let newPath: BlockPath
            if !isPublic {
                newPath = "-" //obfuscate destination name to maintain privacy
            } else {
                newPath = linkPath.path
            }
            return (id: linkPath.id, path: newPath)
        }
        
        let cleanedTypedRelationships = typedRelationships.mapValues {
            return $0.filter { publicRegistry[$0.id] ?? false }
        }
        
        return HugoBlock(block: block,
                         path: path,
                         siblingIndex: siblingIndex,
                         parentPath: parentPath,
                         children: children?.filter { publicRegistry[$0.id] ?? false },
                         pagePath: pagePath,
                         namespacePath: namespacePath,
                         linkPaths: cleanedLinkPaths,
                         backlinkPaths: backlinkPaths.filter { publicRegistry[$0.id] ?? false },
                         typedRelationships: cleanedTypedRelationships,
                         aliasPaths: aliasPaths,
                         assets: assets,
                         processedContent: processedContent,
                         graph: graph)
    }
    
    static func == (lhs: HugoBlock, rhs: HugoBlock) -> Bool {
        return lhs.block == rhs.block
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(block)
    }
}

extension HugoBlock {
    
    func hugoProperties() -> JSON {
        var dict: [String: Any] = [:]
        
        if typedRelationships.values.count > 0 {
            for relationship in typedRelationships.keys {
                let direction: Block.Relationship.Direction
                let relationshipLabel: String
                let endpoints = typedRelationships[relationship]?.map { $0.path }.convertToHugoYAMLList()
                
                switch relationship {
                case .text(let label, direction: let textDirection):
                    direction = textDirection
                    relationshipLabel = label
                case .link(let blockID, direction: let linkDirection):
                    direction = linkDirection
                    relationshipLabel = "\(blockID)" //TODO: fix relationship label for block link
                }
                
                switch direction {
                case .leftToRight:
                    dict[relationshipLabel + " " + direction.rawValue] = endpoints
                case .rightToLeft:
                    dict[direction.rawValue + " " + relationshipLabel] = endpoints
                }
            }
        }
        
        if backlinkPaths.count > 0 {
            dict["z"] = backlinkPaths.map { $0.path }.convertToHugoYAMLList()
        }
        
        if aliasPaths.count > 0 {
            dict["aliases"] = aliasPaths.map { $0.path }
        }
        
        if let namespacePath = namespacePath?.path {
            dict["namespace"] = namespacePath
        }
        
        if linkPaths.count > 0 {
            dict["links"] = linkPaths.map { $0.path }.convertToHugoYAMLList()
        }
        
        dict["collapsed"] = block.collapsed
        
        return JSON(dict)
    }
    
    private func file(links: [LinkInfo]) -> String {
        return hugoYAML() + HugoBlock.hugoModifiedContent(content: block.content, readable: false, links: links)
    }
    
    private func avoidHugoReservedKeys(_ properties: [String: JSON]) -> [String: JSON] {
        let keyReplacements = [
            "url": "external-url",
            "links": "external-links"
        ]
        
        return properties.reduce([String: JSON]()) { dict, property in
            var dict = dict
            dict[keyReplacements[property.key] ?? property.key] = property.value
            return dict
        }
    }
    
    private func hugoYAML() -> String {
        let yamlProperties: String
        if !block.properties.dictionaryValue.keys.isEmpty {
            yamlProperties = try! YAMLEncoder().encode(avoidHugoReservedKeys(block.properties.dictionaryValue))
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
    
    private static func updateAssetLinks(forContent content: String) -> String {
        return AssetFinder.assetUpdates().reduce(content) { updatedContent, assetCheck in
            return assetCheck.makeContentHugoFriendly(content: updatedContent)
        }
    }
    
    private static func updateShortcodes(forContent content: String) -> String {
        return Shortcodes.shortcodes().reduce(content) { updatedContent, shortcode in
            return shortcode.makeContentHugoFriendly(content: updatedContent)
        }
    }
    
    struct LinkInfo {
        let uuid: String
        let isPage: Bool
        let name: String
        let path: BlockPath
        let content: String?
    }
    
    private static func updateLinks(forContent content: String, links: [LinkInfo], readable: Bool) -> String {
        var updatedContent = content
        links.forEach { link in
            
            if link.isPage {
                LinkFinder.pageLinkChecks(name: link.name, path: link.path).forEach  { linkFinder in
                    updatedContent = linkFinder.makeContentHugoFriendly(updatedContent, noLinks: readable)
                }
            } else {
                //block
                //TODO: this is where we would need to deal with parsing nested block references
//                let blockContent = linkedBlock.linkedIDs.count > 0 ? hugoModifiedContent(content: linkedBlock.content, readable: readable) : (linkedBlock.content ?? "")
                let blockContent = link.content ?? ""
                LinkFinder.blockLinkChecks(uuid: link.uuid, content: blockContent, path: link.path).forEach { linkFinder in
                    updatedContent = linkFinder.makeContentHugoFriendly(updatedContent, noLinks: readable)
                }
            }
        }
        return updatedContent
    }
    
    private static func updateBlockProperties(forContent content: String) -> String {
        return BlockPropertyFinder().makeContentHugoFriendly(content: content)
    }
    
    static func hugoModifiedContent(content: String?, readable: Bool, links: [LinkInfo]) -> String {
        guard let content = content, content.count > 0 else { return "" }
        
        var updatedContent = updateAssetLinks(forContent: content)
        updatedContent = updateLinks(forContent: updatedContent, links: links, readable: readable)
        updatedContent = updateShortcodes(forContent: updatedContent)
        updatedContent = updateBlockProperties(forContent: updatedContent)
        
        return updatedContent
    }
    
    func readableName() -> String? {
        if block.isPage() {
            return (block.originalName ?? block.name)?.escapedQuotes()
        } else {
            let content = processedContent
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
            
            let escapedHash = "\\#"
            let unescapedHash = #"#"#

            return trimmedContent
                .escapedQuotes()
                .replacingOccurrences(of: escapedHash, with: unescapedHash)
        }
    }
}

extension Array where Element == String {
    func convertToHugoYAMLList() -> String {
        return "\n - " + self.map { "\"\($0)\"\n" }.joined(separator: " - ")
    }
}
