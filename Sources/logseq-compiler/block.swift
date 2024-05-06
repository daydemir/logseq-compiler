//
//  File.swift
//  
//
//  Created by Deniz Aydemir on 6/4/22.
//

import Foundation
import SwiftyJSON

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
        case collapsed = "block/collapsed?"
        
        case updatedAt = "block/updated-at"
        case createdAt = "block/created-at"
        
        case refs = "block/refs"
        case pathRefs = "block/path-refs"
        case alias = "block/alias"
    }
    
    let uuid: String
    let id: BlockID
    
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
    let collapsed: Bool
    
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
        
        self.name = json[Key.name.rawValue].string?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalName = json[Key.originalName.rawValue].string?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.content = json[Key.content.rawValue].string
        
        self.pageID = json[Key.pageID.rawValue][Key.id.rawValue].int
        self.parentID = json[Key.parentID.rawValue][Key.id.rawValue].int
        self.leftID = json[Key.leftID.rawValue][Key.id.rawValue].int
        self.namespaceID = json[Key.namespaceID.rawValue][Key.id.rawValue].int
        
        self.properties = json[Key.properties.rawValue]
        self.preblock = json[Key.preblock.rawValue].boolValue
        self.format = json[Key.format.rawValue].string
        self.collapsed = json[Key.collapsed.rawValue].boolValue
        
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
