//
//  File.swift
//  
//
//  Created by Deniz Aydemir on 6/4/22.
//

import Foundation

enum LinkFinder {
    
    case pageEmbed(name: String, path: String)
    case pageAlias(name: String, path: String)
    case pageReference(name: String, path: String)
    
    case blockEmbed(uuid: String, content: String, path: String)
    case blockAlias(uuid: String, content: String, path: String)
    case blockReference(uuid: String, content: String, path: String)
    
    static func pageLinkChecks(name: String, path: String) -> [LinkFinder] {
        //order matters
        return [
            LinkFinder.pageEmbed(name: name, path: path),
            LinkFinder.pageAlias(name: name, path: path),
            LinkFinder.pageReference(name: name, path: path)
        ]
    }
    
    static func blockLinkChecks(uuid: String, content: String, path: String) -> [LinkFinder] {
        //order matters
        return [
            LinkFinder.blockEmbed(uuid: uuid, content: content, path: path),
            LinkFinder.blockAlias(uuid: uuid, content: content, path: path),
            LinkFinder.blockReference(uuid: uuid, content: content, path: path)
        ]
    }
    
    func pattern() -> String {
        switch self {
        case .pageEmbed(let name, _):
            return #"\{\{embed\s*\[\[\s*"# + name.escapeParentheses() + #"\s*\]\]\s*\}\}"#
        case .pageAlias(let name, _):
            return #"\]\(\s*\[\[\s*"# + name.escapeParentheses() + #"\s*\]\]s*\)"#
        case .pageReference(let name, _):
            return #"\[\[\s*"# + name.escapeParentheses() + #"\s*\]\]"#
            
        case .blockEmbed(let uuid, _, _):
            return #"\{\{embed\s*\(\(\s*"# + uuid + #"\s*\)\)\s*\}\}"#
        case .blockAlias(let uuid, _, _):
            return #"\]\(\s*\(\(\s*"# + uuid + #"\s*\)\)\s*\)"#
        case .blockReference(let uuid, _, _):
            return #"\(\(\s*"# + uuid + #"\s*\)\)"#
        }
    }
    
    func readable() -> String { //TODO: add a version that adds plain links
        switch self {
        case .pageEmbed(let name, _):
            return "[[\(name)]]"
        case .pageAlias:
            return "]"
        case .pageReference(let name, _):
            return "[[\(name)]]"
            
            
        case .blockEmbed(_, let content, _):
            return content
        case .blockAlias:
            return "]"
        case .blockReference(_, let content, _):
            return shortenedBlockContent(content: content)
        }
    }
    
    private func shortenedBlockContent(content: String) -> String {
        if let firstLine = content.split(separator: "\n").first {
            return String(firstLine)
        } else {
            return content
        }
    }
    
    func hugoFriendlyLink() -> String {
        switch self {
        case .pageEmbed(_, let path):
            return "{{< links/page-embed \"\(path)\" >}}"
        case .pageAlias(_, let path):
            return "](\(path))"
        case .pageReference(let name, let path):
            return "[\(name)](\(path))"
            
            
        case .blockEmbed(_, _, let path):
            return "{{< links/block-embed \"\(path)\" >}}"
        case .blockAlias(_, _, let path):
            return "](\(path))"
        case .blockReference(_, let content, let path):
            return "[\(shortenedBlockContent(content: content))](\(path))"
        }
    }
    
    func ranges(inContent content: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: self.pattern(), options: .caseInsensitive) else {
            print("Skipping finding links for bad regex: " + self.pattern())
            return []
        }
        return regex.matches(in: content, options: .reportCompletion, range: NSRange(content.startIndex..<content.endIndex, in: content)).map { (result: NSTextCheckingResult) in
            return result.range
        }
    }
    
    func makeContentHugoFriendly(_ content: String, noLinks: Bool) -> String {
        var updatedContent = content as NSString
        
        ranges(inContent: content).forEach { range in
            let replacement = noLinks ? readable() : hugoFriendlyLink()
            updatedContent = updatedContent.replacingCharacters(in: range, with: replacement) as NSString
        }
        
        return updatedContent as String
    }
}

extension String {
    func escapeParentheses() -> String {
        return replacingOccurrences(of: "(", with: #"\("#).replacingOccurrences(of: ")", with: #"\)"#)
    }
}
