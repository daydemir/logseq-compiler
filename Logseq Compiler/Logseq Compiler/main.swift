//
//  main.swift
//  Logseq Compiler
//
//  Created by Deniz Aydemir on 5/30/22.
//

import Foundation
import SwiftyJSON

func getDownloadsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    return paths[0]
}

enum CompilerError: Error {
    case parsingError
}

typealias Properties = JSON

class Block: Identifiable, Equatable {
    static func == (lhs: Block, rhs: Block) -> Bool {
        return lhs.id = rhs.id
    }
    
    enum Key: String {
        case id
        case content
        case children
        case properties
    }
    
    let id: String
    let content: String
    let children: [Block]
    
    let index: Int
    let properties: Properties
    
    init(_ json: JSON, index: Int, page: Page, parent: Block?) throws {
        guard let id = json[Key.id.rawValue].string,
              let content = json[Key.content.rawValue].string
        else { throw CompilerError.parsingError }
        
        self.id = id
        self.content = content
        
        self.properties = json[Key.properties.rawValue]
        self.index = index
        
        self.children = json[Key.children.rawValue].enumerated().compactMap { try? Block($0.element.1, index: $0.offset + 1, page: page, parent: self) } //can't use zero for weight in hugo

    }
    
    func allDescendents() -> [Block] {
        return children + children.flatMap { $0.allDescendents() }
    }
    
    func referrers(allBlocks: [String: Block]) -> [Block] {
        return allBlocks.values.filter { $0.content.contains("((\(self.id)))") }
    }
    
    func parent(allBlocks: [String: Block]) -> Block? {
        return allBlocks.values.filter { $0.children.contains(where: { $0 == self } ) }.first
    }
    
    func page(allPages: [Page]) throws -> Page {
        let page = allPages.filter { $0.allDescendents().contains { $0 == self } }.first
        if let page = page {
            return page
        } else {
            throw CompilerError.parsingError
        }
    }
    
    private func replaceBlockReference(content: String, allPages: [Page], allBlocks: [Block]) -> String {
        guard content.contains("((") else { return content }
        
        print(content.contains("((62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860))"))
        print(allBlocks.map { $0.id })
        
        let referredBlocks = allBlocks.filter { content.contains("((\($0.id)))")}
        
        print("all block contains?")
        print(allBlocks.contains(where: { $0.id == "62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860"}))
        print(referredBlocks.map { $0.content })
        
        return referredBlocks.reduce(content) { content, referredBlock in
            print(content)
            return content.replacingOccurrences(of: "((\(referredBlock.id)))", with: "[\(referredBlock.content)]" + "({{< relref \"\(try! referredBlock.page(allPages: allPages).name).md#\(referredBlock.id)\" >}})", options: .literal, range: nil)
        }
    }
    
    func isPageProperties() -> Bool {
        guard index == 1, let firstLine = self.content.split(separator: "\n").first else { return false }
        return firstLine.contains("::") || firstLine == "---"
    }
    
    private func hugoModifiedContent() -> String {
        return content.replacingOccurrences(of: "(../assets/", with: "(/assets/")
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
        try! file().write(to: blockDirectory.appendingPathComponent("_index.md"), atomically: true, encoding: .utf8)
        children.forEach { $0.createSection(inDirectory: blockDirectory) }
    }
}


class Page: Identifiable, Equatable {
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
    let children: [Block]
    
    let properties: Properties
    
    init(_ json: JSON) throws {
        guard let id = json[Key.id.rawValue].string,
              let name = json[Key.pageName.rawValue].string
        else { throw CompilerError.parsingError }
        
        self.id = id
        self.name = name
        
        self.children = json[Key.children.rawValue].enumerated().compactMap { try? Block($0.element.1, index: $0.offset + 1, page: self, parent: nil) } //can't use zero for weight in hugo
        self.properties = json[Key.properties.rawValue]
    }
    
    func allDescendents() -> [Block] {
        return children + self.children.flatMap { $0.allDescendents() }
    }
    
    func referrers(allBlocks: [String: Block]) -> [Block] {
        return allBlocks.values.filter { $0.content.contains("[[\(self.name)]]")}
    }
    
    func namespace(allPages: [Page]) -> Page? {
        let prefix = name.split(separator: "/").dropLast().joined(separator: "/")
        return allPages.filter { $0.name == prefix }.first
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
        try! sectionFile().write(to: pageDirectory.appendingPathComponent("_index.md"), atomically: true, encoding: .utf8)
        
        children
            .filter { !$0.isPageProperties() }
            .forEach { $0.createSection(inDirectory: pageDirectory) }
    }
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

let allPages = graphJSON["blocks"].map { try! Page($0.1) }
//    .filter { $0.properties.dictionaryValue["public"]?.boolValue == true }
let allBlocks = allPages
    .flatMap { $0.allDescendents() }




try! emptyDirectory(getTestDirectory())

try! FileManager.default.createDirectory(at: notesDestination, withIntermediateDirectories: true)
allPages.forEach { $0.createSection(inDirectory: notesDestination) }

try! FileManager.default.createDirectory(at: assetsDestination, withIntermediateDirectories: true)
try! copyContents(from: assetsOrigin, to: assetsDestination)



//filter for public last, in order to decide what types of links should be visible



