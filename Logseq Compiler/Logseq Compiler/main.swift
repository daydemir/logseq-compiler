//
//  main.swift
//  Logseq Compiler
//
//  Created by Deniz Aydemir on 5/30/22.
//

import Foundation
import SwiftyJSON


enum CompilerError: Error {
    case parsingError
}

let indexFile = "_index.md"
typealias Properties = JSON

struct Graph {
    
    enum Link {
        case link
        case alias
        case inlineAlias
    }
    
    let pages: [Page]
    let blocks: [Block]
    let allContent: [BlockType]
    let links: [Block: [BlockType]]
    
    init(_ json: JSON) {
        let pages = json["blocks"].map { try! Page($0.1) }
        //    .filter { $0.properties.dictionaryValue["public"]?.boolValue == true }
        let allBlocks = pages
            .flatMap { $0.allDescendents() }
        
        self.pages = pages
        self.blocks = allBlocks
        self.links = populateLinks(allBlocks: allBlocks)
    }
    
    private func populateLinks(allBlocks: [Block]) -> [Block: [BlockType]] {
        allBlocks.compactMap { block in
            //find page link
            
            //find page alias
            //find page inline alias
            //find page embed
            
            //find block link
            //find block inline alias
            //find block embed
        }
    }
    
    
    
    
}

protocol BlockType {
    var id: String { get }
    var children: [Block] { get }
}


class Block: BlockType, Equatable, Hashable {
    static func == (lhs: Block, rhs: Block) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    enum Key: String {
        case id
        case content
        case children
        case properties
    }
    
    let id: String
    let content: String
    private(set) var children: [Block] = []
    
    let index: Int
    let properties: Properties
    let parent: Block?
    let page: Page
    
    init(_ json: JSON, index: Int, page: Page, parent: Block?) throws {
        guard let id = json[Key.id.rawValue].string,
              let content = json[Key.content.rawValue].string
        else { throw CompilerError.parsingError }
        
        self.id = id
        self.content = content
        
        self.properties = json[Key.properties.rawValue]
        self.index = index
        
        self.parent = parent
        self.page = page
        
        self.children = json[Key.children.rawValue].enumerated().compactMap { try? Block($0.element.1, index: $0.offset + 1, page: page, parent: self) } //can't use zero for weight in hugo
    }
    
    func allDescendents() -> [Block] {
        return children + children.flatMap { $0.allDescendents() }
    }
    
    func referrers(allBlocks: [String: Block]) -> [Block] {
        return allBlocks.values.filter { $0.content.contains("((\(self.id)))") }
    }
    
//    private func replaceBlockReference(content: String, allPages: [Page], allBlocks: [Block]) -> String {
//        guard content.contains("((") else { return content }
//
//        print(content.contains("((62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860))"))
//        print(allBlocks.map { $0.id })
//
//        let referredBlocks = allBlocks.filter { content.contains("((\($0.id)))")}
//
//        print("all block contains?")
//        print(allBlocks.contains(where: { $0.id == "62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860"}))
//        print(referredBlocks.map { $0.content })
//
//        return referredBlocks.reduce(content) { content, referredBlock in
//            print(content)
//            return content.replacingOccurrences(of: "((\(referredBlock.id)))", with: "[\(referredBlock.content)]" + "({{< relref \"\(try! referredBlock.page(allPages: allPages).name).md#\(referredBlock.id)\" >}})", options: .literal, range: nil)
//        }
//    }
    
    private func getAncestors() -> [Block] {
        guard let parent = parent else { return [] }
        
        return parent.getAncestors() + [parent]
    }
    
    func isPageProperties() -> Bool {
        guard index == 1, let firstLine = self.content.split(separator: "\n").first else { return false }
        return firstLine.contains("::") || firstLine == "---"
    }
    
    private func hugoModifiedContent() -> String {
        return content
            .replacingOccurrences(of: "(../assets/", with: "(/assets/")
    }
    
    func file() -> String {
        let content = hugoModifiedContent()
        let headerContent = (self.properties.map { "\($0.0): \($0.1)\n"} + ["logseq-type: block\nweight: \(index)\n"]).joined(separator: "")
        
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
        
        return "---\n" + "title: \"\(trimmedContent)\"\n" + headerContent + "---\n" + content
    }
    
    func createSection(inDirectory directory: URL) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let blockDirectory = directory.appendingPathComponent(id)
        try! FileManager.default.createDirectory(at: blockDirectory, withIntermediateDirectories: true)
        try! file().write(to: blockDirectory.appendingPathComponent(indexFile), atomically: true, encoding: .utf8)
        children.forEach { $0.createSection(inDirectory: blockDirectory) }
    }
}

class Page: BlockType, Equatable {
    static func == (lhs: Page, rhs: Page) -> Bool {
        return lhs.id == rhs.id
    }
    
    
    enum Key: String {
        case id
        case pageName = "page-name"
        case children
        case properties
    }
    
    let id: String
    let name: String
    private(set) var children: [Block] = []
    
    let properties: Properties
    
    init(_ json: JSON) throws {
        guard let id = json[Key.id.rawValue].string,
              let name = json[Key.pageName.rawValue].string
        else { throw CompilerError.parsingError }
        
        self.id = id
        self.name = name
        self.properties = json[Key.properties.rawValue]
        
        self.children = json[Key.children.rawValue].enumerated().compactMap { try? Block($0.element.1, index: $0.offset + 1, page: self, parent: nil) } //can't use zero for weight in hugo
    }
    
    func allDescendents() -> [Block] {
        return children + self.children.flatMap { $0.allDescendents() }
    }
    
    func referrers(allBlocks: [String: Block]) -> [Block] {
        return allBlocks.values.filter { $0.content.contains("[[\(self.name)]]")}
    }
    
    func namespace() -> String? {
        let prefix = name.split(separator: "/").dropLast().joined(separator: "/")
        if prefix.count > 0 { return prefix } else { return nil }
    }
    
    func yamlHeader() -> String {
        let headerContent = (self.properties.map { "\($0.0): \($0.1)\n"} + ["logseq-type: page\n"]).joined(separator: "")
        return "---\n" + "title: \"\(name)\"\n" + headerContent + "---"
    }
    
    func sectionFile() -> String {
        return yamlHeader() + "\n" + name
    }
    
    func createSection(inDirectory directory: URL) {
        let pageDirectory = directory.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true, attributes: nil)
        try! sectionFile().write(to: pageDirectory.appendingPathComponent(indexFile), atomically: true, encoding: .utf8)
        
        children
            .filter { !$0.isPageProperties() }
            .forEach { $0.createSection(inDirectory: pageDirectory) }
    }
}

struct Relationship {
    
    let relation: Page
    let object: [Block]
}


extension Block {
    struct Links {
        let referrers: [Block]
        let relationships: [Relationship]
    }
    
}






//compiler stuff

func getDownloadsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    return paths[0]
}

func getTestDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0].appendingPathComponent("compiled-graph-test", isDirectory: true)
}

func emptyDirectory(_ directory: URL) throws {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).forEach { url in
        try FileManager.default.removeItem(at: url)
    }
}

func copyContents(from: URL, to: URL) throws {
    try FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil).forEach { url in
        try FileManager.default.copyItem(at: url, to: to.appendingPathComponent(url.lastPathComponent))
    }
}

let originDirectory = getDownloadsDirectory().appendingPathComponent("export", isDirectory: true)
let assetsOrigin = originDirectory.appendingPathComponent("assets", isDirectory: true)
let graphString = try! String(contentsOf: originDirectory.appendingPathComponent("graph.json"))

let cleanedGraphString = graphString.replacingOccurrences(of: "\n", with: "\\n")
let graphJSON = try! JSON(data: cleanedGraphString.data(using: .utf8)!)


let notesDestination = getTestDirectory().appendingPathComponent("notes", isDirectory: true)
let assetsDestination = getTestDirectory().appendingPathComponent("assets", isDirectory: true)




//logic follows...



//create a set of extra data to be included alongside blocks




try! emptyDirectory(getTestDirectory())

try! FileManager.default.createDirectory(at: notesDestination, withIntermediateDirectories: true)
allPages.forEach { $0.createSection(inDirectory: notesDestination) }

try! FileManager.default.createDirectory(at: assetsDestination, withIntermediateDirectories: true)
try! copyContents(from: assetsOrigin, to: assetsDestination)



//filter for public last, in order to decide what types of links should be visible



