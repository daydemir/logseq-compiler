//
//  BlockExtensions.swift
//  
//
//  Created by Deniz Aydemir on 4/8/23.
//

import Foundation



extension Block {
    
    enum Relationship: Hashable {
        case text(_: String, direction: Direction)
        case link(_: BlockID, direction: Direction)
        
        enum Direction: String {
            case leftToRight = "->"
            case rightToLeft = "<-"
        }
        
        var direction: Direction {
            switch self {
            case .link(_, let direction):
                return direction
            case .text(_, let direction):
                return direction
            }
        }
    }
    
    func isHome() -> Bool {
        return self.properties["home"].boolValue
    }
    
    func extractRelationship() -> Relationship? {
        guard let direction = isRelationship() else { return nil }
        
        if let linkedID = linkedIDs.first, isContentOnlyOneLink(direction: direction) {
            return .link(linkedID, direction: direction)
        } else if let withoutIndicator = removeRelationshipIndicatorFromContent(direction: direction) {
            return .text(withoutIndicator, direction: direction)
        } else {
            //TODO: not sure how we'd get here, should change to throwing an error probably
            return nil
        }
    }
    
    func isRelationship() -> Relationship.Direction? {
        guard let content else { return nil }
        
        if content.hasSuffix(Relationship.Direction.leftToRight.rawValue) {
            return .leftToRight
        } else if content.hasPrefix(Relationship.Direction.rightToLeft.rawValue) {
            return .rightToLeft
        } else {
            return nil
        }
    }
    
    func removeRelationshipIndicatorFromContent(direction: Relationship.Direction) -> String? {
        guard var content else { return nil }
        
        switch direction {
        case .leftToRight:
            content.removeLast(Relationship.Direction.leftToRight.rawValue.count)
        case .rightToLeft:
            content.removeFirst(Relationship.Direction.rightToLeft.rawValue.count)
        }
        
        return content
    }
    
    func isContentOnlyOneLink(direction: Relationship.Direction) -> Bool {
        guard let content = removeRelationshipIndicatorFromContent(direction: direction),
                linkedIDs.count == 1
        else { return false }
        
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let isOnlyBlockLink = trimmed.hasPrefix("((") && trimmed.hasSuffix("))")
        let isOnlyPageLink = trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]")
        return isOnlyPageLink || isOnlyBlockLink
    }
}



extension Block {
    
    func isPublic(assumePublic: Bool) -> Bool {
        if assumePublic {
            if let valueExists = properties["public"].bool {
                return valueExists
            } else {
                return true //assuming public here
            }
        } else {
            return properties["public"].boolValue
        }
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

extension String {
    func escapedQuotes() -> String {
        return replacingOccurrences(of: #"""#, with: #"\""#)
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
    
    func siblingIndex(forBlock block: Block?) -> Int {
        if let leftID = block?.leftID {
            return siblingIndex(forBlock: self[leftID]) + 1
        } else {
            return 1
        }
    }
}
