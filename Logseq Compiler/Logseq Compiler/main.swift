//
//  main.swift
//  Logseq Compiler
//
//  Created by Deniz Aydemir on 5/30/22.
//

import Foundation
import SwiftyJSON

let graphString =
"""
{"version":1,"blocks":[{"id":"8d2ec83a-43d9-41a5-931d-fc5d0a229c9e","page-name":"Contents","children":[{"id":"62957c3c-3b58-41bf-a381-2cace1837b19","format":"markdown","children":[],"content":""}]},{"id":"62957c3c-df9c-4703-950a-a4f5837fe386","page-name":"May 30th, 2022","format":"markdown","children":[{"id":"62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860","properties":{},"format":"markdown","children":[],"content":"This can be a demo graph that I use to build out some publish functionality\nid:: 62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860"},{"id":"62957c4b-dded-4270-a87a-48f1c20c69a5","properties":{},"format":"markdown","children":[],"content":"[[A good idea]]"},{"id":"62957ca5-59ef-43cd-86c3-341e0a7f4d6b","properties":{},"format":"markdown","children":[],"content":"[[Another test area]]"}]},{"id":"62957c4e-2041-43f9-9668-7a175e04e93d","page-name":"A good idea","properties":{"public":true,"location":["Durham"]},"format":"markdown","children":[{"id":"62957c4f-27cf-435c-bf59-a3d6a38824b9","properties":{"public":true,"location":["Durham"]},"format":"markdown","children":[],"content":"public:: true\nlocation:: [[Durham]]"},{"id":"62957c5e-07aa-4a2d-a6bb-84f6dbfe34b2","properties":{"type":"claim"},"format":"markdown","children":[{"id":"62959447-676d-44ca-a6f6-45c5aaf7be43","properties":{},"format":"markdown","children":[],"content":"some"},{"id":"62959449-8764-4bd8-8b15-749d5931dee2","properties":{},"format":"markdown","children":[],"content":"children"},{"id":"6295944a-fdff-4f1b-8ab0-c2b711fa32fb","properties":{},"format":"markdown","children":[],"content":"here"},{"id":"6295944a-a16e-43bc-b343-95c69a21e320","properties":{},"format":"markdown","children":[{"id":"6295944f-ca22-4b2f-b3f1-dd90bd9cc198","properties":{},"format":"markdown","children":[{"id":"62959450-24a7-4f09-8de0-0983481f6029","properties":{},"format":"markdown","children":[{"id":"62959452-3414-489c-a24c-2144b22838ea","properties":{"testing":"some stuff"},"format":"markdown","children":[],"content":"look\ntesting:: some stuff"},{"id":"6295a5c1-73f9-482a-bed6-a621be5d9c41","properties":{},"format":"markdown","children":[],"content":"here's another block reference ((62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860))"}],"content":"this"}],"content":"does"}],"content":"how"}],"content":"point number one\nid:: 62957c5e-07aa-4a2d-a6bb-84f6dbfe34b2\ntype:: claim"},{"id":"62957cd4-338d-42ff-bb32-c3fa13fd661d","properties":{},"format":"markdown","children":[],"content":"Another block\nwith line breaks"}]},{"id":"62957c5b-0c33-444c-9e82-082fb1e6d19d","page-name":"new page: durham","format":"markdown","children":[{"id":"62957c5b-e5dc-46a9-ba83-8388cdcbb589","properties":{"title":"new page: durham"},"format":"markdown","children":[],"content":"title:: new page: durham"},{"id":"62957c5b-81c9-493e-a1cb-fba66c4db7d3","properties":{},"format":"markdown","children":[],"content":""}]},{"id":"62957cb3-ff2b-475a-bb9c-a2f1edfa821e","page-name":"Another test area","properties":{"public":true},"format":"markdown","children":[{"id":"62957cc9-d8ef-4fe2-90db-ef7e7328441d","properties":{"public":true},"format":"markdown","children":[],"content":"public:: true"},{"id":"62957cb5-ec21-41fb-a87d-fd81ef84541a","properties":{},"format":"markdown","children":[],"content":"((62957c5e-07aa-4a2d-a6bb-84f6dbfe34b2))"}]},{"id":"629592f4-17f5-43cf-b7d8-2ab65be0fcba","page-name":"May 31st, 2022","properties":{"public":true},"format":"markdown","children":[{"id":"62959500-086b-47e6-95db-d2bb7e03d24c","properties":{"public":true},"format":"markdown","children":[],"content":"public:: true"},{"id":"629592f4-58bf-4cfb-b59c-61791f87dca0","properties":{},"format":"markdown","children":[],"content":"a new day"},{"id":"629594ab-3205-4fb7-abd5-4e3e84b20a7a","properties":{},"format":"markdown","children":[],"content":"a new cat"}]}]}
"""

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
    
    private func replaceBlockReference(allBlocks: [Block]) -> String {
        guard content.contains("((") else { return content }
        
        print(content.contains("((62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860))"))
        print(allBlocks.map { $0.id })
        
        let referredBlocks = allBlocks.filter { content.contains("((\($0.id)))")}
        
        print("all block contains?")
        print(allBlocks.contains(where: { $0.id == "62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860"}))
        print(referredBlocks.map { $0.content })
        
        return referredBlocks.reduce(content) { content, referredBlock in
            print(content)
            return content.replacingOccurrences(of: "((\(referredBlock.id)))", with: "\(referredBlock.content) <- this is an embedded block", options: .literal, range: nil)
        }
    }
    
    private func indentLineBreaks(content: String, indent: String) -> String {
        content.replacingOccurrences(of: "\n", with: "\n" + indent, options: .regularExpression, range: nil)
    }
    
    func allContent(indent: String, allPages: [Page], allBlocks: [Block]) -> String {
        guard !isPageProperties(page: try! page(allPages: allPages)) else { return "" }
        
        let blockReferenceReplacedContent = indent + "- " + replaceBlockReference(allBlocks: allBlocks)
        let finalBlockContent = indentLineBreaks(content: blockReferenceReplacedContent, indent: indent)
        let childContent = children.map { "\n" + $0.allContent(indent: "     " + indent, allPages: allPages, allBlocks: allBlocks) }.joined(separator: "")
        
        return finalBlockContent + childContent
    }
    
    func isPageProperties(page: Page) -> Bool {
        guard page.children.first == self, let firstLine = self.content.split(separator: "\n").first else { return false }
        return firstLine.contains("::") || firstLine == "---"
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
        return "---\n" + "title: \(name)\n" + headerContent + "---"
    }
    
    func processedContent(allPages: [Page], allBlocks: [Block]) -> String {
        ([yamlHeader()] + children.map { $0.allContent(indent: "", allPages: allPages, allBlocks: allBlocks) })
            .joined(separator: "\n")
    }
}

func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
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

allPages.forEach { page in
    let filename = getDocumentsDirectory().appendingPathComponent("compiled-graph-test", isDirectory: true).appendingPathComponent("\(page.id).md")
    do {
        try page.processedContent(allPages: allPages, allBlocks: allBlocks)
            .write(to: filename, atomically: true, encoding: String.Encoding.utf8)
    } catch {
        print("error writing file \(page.name)")
        // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
    }
}


//filter for public last, in order to decide what types of links should be visible



