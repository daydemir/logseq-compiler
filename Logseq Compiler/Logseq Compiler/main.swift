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
{"version":1,"blocks":[{"id":"62957c3c-1c56-4989-93f2-66a1aeb366f7","page-name":"Contents","children":[{"id":"62957c3c-3b58-41bf-a381-2cace1837b19","format":"markdown","children":[],"content":""}]},{"id":"62957c3c-df9c-4703-950a-a4f5837fe386","page-name":"May 30th, 2022","format":"markdown","children":[{"id":"62957c3c-6fd4-4ee2-bcf1-c0b4e62a2860","properties":{},"format":"markdown","children":[],"content":"This can be a demo graph that I use to build out some publish functionality"},{"id":"62957c4b-dded-4270-a87a-48f1c20c69a5","properties":{},"format":"markdown","children":[],"content":"[[A good idea]]"},{"id":"62957ca5-59ef-43cd-86c3-341e0a7f4d6b","properties":{},"format":"markdown","children":[],"content":"[[Another test area]]"}]},{"id":"62957c4e-2041-43f9-9668-7a175e04e93d","page-name":"A good idea","properties":{"public":true,"location":["Durham"]},"format":"markdown","children":[{"id":"62957c4f-27cf-435c-bf59-a3d6a38824b9","properties":{"public":true,"location":["Durham"]},"format":"markdown","children":[],"content":"public:: true\nlocation:: [[Durham]]"},{"id":"62957c5e-07aa-4a2d-a6bb-84f6dbfe34b2","properties":{"type":"claim"},"format":"markdown","children":[],"content":"point number one\nid:: 62957c5e-07aa-4a2d-a6bb-84f6dbfe34b2\ntype:: claim"},{"id":"62957cd4-338d-42ff-bb32-c3fa13fd661d","properties":{},"format":"markdown","children":[],"content":""}]},{"id":"62957c5b-0c33-444c-9e82-082fb1e6d19d","page-name":"new page: durham","format":"markdown","children":[{"id":"62957c5b-e5dc-46a9-ba83-8388cdcbb589","properties":{"title":"new page: durham"},"format":"markdown","children":[],"content":"title:: new page: durham"},{"id":"62957c5b-81c9-493e-a1cb-fba66c4db7d3","properties":{},"format":"markdown","children":[],"content":""}]},{"id":"62957cb3-ff2b-475a-bb9c-a2f1edfa821e","page-name":"Another test area","properties":{"public":true},"format":"markdown","children":[{"id":"62957cc9-d8ef-4fe2-90db-ef7e7328441d","properties":{"public":true},"format":"markdown","children":[],"content":"public:: true"},{"id":"62957cb5-ec21-41fb-a87d-fd81ef84541a","properties":{},"format":"markdown","children":[],"content":"((62957c5e-07aa-4a2d-a6bb-84f6dbfe34b2))"}]}]}
"""


let linebreak =
"""
"""

enum CompilerError: Error {
    case parsingError
}

let cleanedGraphString = graphString.replacingOccurrences(of: "\n", with: linebreak)

let graphJSON = try! JSON(data: cleanedGraphString.data(using: .utf8)!)
print(graphJSON.description)

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
        return self.children.flatMap { $0.allDescendents() }
    }
    
    func referrers(allBlocks: [String: Block]) -> [Block] {
        return allBlocks.values.filter { $0.content.contains("[[\(self.name)]]")}
    }
    
    func namespace(allPages: [Page]) -> Page? {
        let prefix = name.split(separator: "/").dropLast().joined(separator: "/")
        return allPages.filter { $0.name == prefix }.first
    }
}

//logic follows...

let pages = graphJSON["blocks"].map { try! Page($0.1) }.filter { $0.properties.dictionaryValue["public"]?.boolValue == true }
let allBlocks = pages
    .flatMap { $0.allDescendents() }
    .reduce([String: Block]()) {
        var dict = $0
        dict[$1.id] = $1
        return dict
    }



print(pages)




