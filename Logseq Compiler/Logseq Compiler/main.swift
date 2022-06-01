//
//  main.swift
//  Logseq Compiler
//
//  Created by Deniz Aydemir on 5/30/22.
//

import Foundation
import SwiftyJSON

let graphString = try! String(contentsOf: getDownloadsDirectory().appendingPathComponent("graph.json"))

func getDownloadsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    return paths[0]
}

enum CompilerError: Error {
    case parsingError
}

let cleanedGraphString = graphString.replacingOccurrences(of: "\n", with: "\\n  ")

let graphJSON = try! JSON(data: cleanedGraphString.data(using: .utf8)!)

typealias Properties = JSON

struct Block: Identifiable, Equatable {
    enum Key: String {
        case id
        case content
        case children
        case properties
    }
    
    let id: String
    let content: String
    let children: [Block]
    
    let properties: Properties
    
    init(_ json: JSON) throws {
        guard let id = json[Key.id.rawValue].string,
              let content = json[Key.content.rawValue].string
        else { throw CompilerError.parsingError }
        
        self.id = id
        self.content = content
        
        self.children = json[Key.children.rawValue].compactMap { try? Block($0.1) }
        self.properties = json[Key.properties.rawValue]
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
    
    private func indentLineBreaks(content: String, indent: String) -> String {
        content.replacingOccurrences(of: "\n", with: "\n" + indent, options: .regularExpression, range: nil)
    }
    
    private func wrapBlockShortcode(id: String, content: String) -> String {
        return "{{% block \(id) %}}" + content + "{{% /block %}}"
    }
    
    func allContent(indent: String, allPages: [Page], allBlocks: [Block]) -> String {
        guard !isPageProperties(page: try! page(allPages: allPages)) else { return "" }
        
        let blockReferenceReplacedContent = indent + replaceBlockReference(content: self.content, allPages: allPages, allBlocks: allBlocks) //dropped "- " for now
        let finalBlockContent = blockReferenceReplacedContent //indentLineBreaks(content: blockReferenceReplacedContent, indent: indent)
        let childContent = children.map { "\n" + $0.allContent(indent: "", allPages: allPages, allBlocks: allBlocks) }.joined(separator: "") //no indent for now
        
        return wrapBlockShortcode(id: id, content: finalBlockContent + childContent)
    }
    
    func isPageProperties(page: Page) -> Bool {
        guard page.children.first == self, let firstLine = self.content.split(separator: "\n").first else { return false }
        return firstLine.contains("::") || firstLine == "---"
    }
    
    func file() -> String {
        let headerContent = self.properties.map { "\($0.0): \($0.1)\n"}.joined(separator: "")
        return "---\n" + "title: \(id)\n" + headerContent + "---\n" + content
    }
    
    func createSection(inDirectory directory: URL) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let blockDirectory = directory.appendingPathComponent(id)
        try! FileManager.default.createDirectory(at: blockDirectory, withIntermediateDirectories: true)
        try! file().write(to: blockDirectory.appendingPathComponent("_index.md"), atomically: true, encoding: .utf8)
        children.forEach { $0.createSection(inDirectory: blockDirectory) }
    }
}


struct Page: Identifiable, Equatable {
    
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
        
        self.children = json[Key.children.rawValue].compactMap { try? Block($0.1) }
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
        let headerContent = self.properties.map { "\($0.0): \($0.1)\n"}.joined(separator: "")
        return "---\n" + "title: \"\(name)\"\n" + headerContent + "---"
    }
    
    func processedContent(allPages: [Page], allBlocks: [Block]) -> String {
        ([yamlHeader()] + children.map { $0.allContent(indent: "", allPages: allPages, allBlocks: allBlocks) })
            .joined(separator: "\n")
    }
    
    func sectionFile() -> String {
        return yamlHeader() + "\n" + name
    }
    
    func createSection(inDirectory directory: URL) {
        let pageDirectory = getTestDirectory().appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true, attributes: nil)
        try! sectionFile().write(to: pageDirectory.appendingPathComponent("_index.md"), atomically: true, encoding: .utf8)
        children.forEach { $0.createSection(inDirectory: pageDirectory) }
    }
}

func getTestDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0].appendingPathComponent("compiled-graph-test", isDirectory: true).appendingPathComponent("notes", isDirectory: true)
}

func emptyDirectory(_ directory: URL) throws {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).forEach { url in
        try FileManager.default.removeItem(at: url)
    }
}
 
//logic follows...

let allPages = graphJSON["blocks"].map { try! Page($0.1) }
//    .filter { $0.properties.dictionaryValue["public"]?.boolValue == true }
let allBlocks = allPages
    .flatMap { $0.allDescendents() }
//    .reduce([String: Block]()) {
//        var dict = $0
//        dict[$1.id] = $1
//        return dict
//    }

//allPages.forEach { page in
//    let filename = getDocumentsDirectory().appendingPathComponent("compiled-graph-test", isDirectory: true).appendingPathComponent("\(page.name).md")
//    do {
//        try page.processedContent(allPages: allPages, allBlocks: allBlocks)
//            .write(to: filename, atomically: true, encoding: String.Encoding.utf8)
//    } catch {
//        print("error writing file \(page.name)")
//        // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
//    }
//}

try! emptyDirectory(getTestDirectory())
allPages.forEach { $0.createSection(inDirectory: getTestDirectory()) }


//filter for public last, in order to decide what types of links should be visible



