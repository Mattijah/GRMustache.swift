//
//  TemplateCompiler.swift
//  GRMustache
//
//  Created by Gwendal Roué on 25/10/2014.
//  Copyright (c) 2014 Gwendal Roué. All rights reserved.
//

import Foundation

class TemplateCompiler: TemplateTokenConsumer {
    private var state: CompilerState
    let repository: MustacheTemplateRepository
    let templateID: TemplateID?
    
    init(contentType: ContentType, repository: MustacheTemplateRepository, templateID: TemplateID?) {
        self.state = .Compiling(CompilationState(contentType: contentType))
        self.repository = repository
        self.templateID = templateID
    }
    
    func templateAST(error outError: NSErrorPointer) -> TemplateAST? {
        switch(state) {
        case .Compiling(let compilationState):
            switch compilationState.currentScope.type {
            case .Root:
                return TemplateAST(nodes: compilationState.currentScope.templateASTNodes, contentType: compilationState.contentType)
            case .Section(openingToken: let openingToken, expression: _):
                if outError != nil {
                    outError.memory = parseErrorAtToken(openingToken, description: "Unclosed Mustache tag")
                }
                return nil
            case .InvertedSection(openingToken: let openingToken, expression: _):
                if outError != nil {
                    outError.memory = parseErrorAtToken(openingToken, description: "Unclosed Mustache tag")
                }
                return nil
            case .InheritablePartial(openingToken: let openingToken, partialName: _):
                if outError != nil {
                    outError.memory = parseErrorAtToken(openingToken, description: "Unclosed Mustache tag")
                }
                return nil
            case .InheritableSection(openingToken: let openingToken, inheritableSectionName: _):
                if outError != nil {
                    outError.memory = parseErrorAtToken(openingToken, description: "Unclosed Mustache tag")
                }
                return nil
            }
        case .Error(let error):
            if outError != nil {
                outError.memory = error
            }
            return nil
        }
    }
    
    
    // MARK: - TemplateTokenConsumer
    
    func parser(parser: TemplateParser, didFailWithError error: NSError) {
        state = .Error(error)
    }
    
    func parser(parser: TemplateParser, shouldContinueAfterParsingToken token: TemplateToken) -> Bool {
        switch(state) {
        case .Error:
            return false
        case .Compiling(let compilationState):
            switch(token.type) {
                
            case .SetDelimiters:
                // noop
                return true
                
            case .Comment:
                // noop
                return true
                
            case .Pragma(content: let content):
                let pragma = content.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
                if NSRegularExpression(pattern: "^CONTENT_TYPE\\s*:\\s*TEXT$", options: NSRegularExpressionOptions(0), error: nil)!.firstMatchInString(pragma, options: NSMatchingOptions(0), range: NSMakeRange(0, (pragma as NSString).length)) != nil {
                    switch compilationState.compilerContentType {
                    case .Unlocked:
                        compilationState.compilerContentType = .Unlocked(.Text)
                    case .Locked(let contentType):
                        state = .Error(parseErrorAtToken(token, description: "CONTENT_TYPE:TEXT pragma tag must prepend any Mustache variable, section, or partial tag."))
                        return false
                    }
                } else if NSRegularExpression(pattern: "^CONTENT_TYPE\\s*:\\s*HTML$", options: NSRegularExpressionOptions(0), error: nil)!.firstMatchInString(pragma, options: NSMatchingOptions(0), range: NSMakeRange(0, (pragma as NSString).length)) != nil {
                    switch compilationState.compilerContentType {
                    case .Unlocked:
                        compilationState.compilerContentType = .Unlocked(.HTML)
                    case .Locked(let contentType):
                        state = .Error(parseErrorAtToken(token, description: "CONTENT_TYPE:HTML pragma tag must prepend any Mustache variable, section, or partial tag."))
                        return false
                    }
                }
                return true
                
            case .Text(text: let text):
                compilationState.currentScope.appendNode(TextNode(text: text))
                return true
                
            case .EscapedVariable(content: let content):
                var error: NSError?
                var empty = false
                if let expression = ExpressionParser().parse(content, empty: &empty, error: &error) {
                    compilationState.currentScope.appendNode(VariableTag(expression: expression, contentType: compilationState.contentType, escapesHTML: true))
                    compilationState.compilerContentType = .Locked(compilationState.contentType)
                    return true
                } else {
                    state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
            case .UnescapedVariable(content: let content):
                var error: NSError?
                var empty = false
                if let expression = ExpressionParser().parse(content, empty: &empty, error: &error) {
                    compilationState.currentScope.appendNode(VariableTag(expression: expression, contentType: compilationState.contentType, escapesHTML: false))
                    compilationState.compilerContentType = .Locked(compilationState.contentType)
                    return true
                } else {
                    state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
            case .Section(content: let content):
                var error: NSError?
                var empty = false
                let expression = ExpressionParser().parse(content, empty: &empty, error: &error)
                
                if expression == nil && !empty {
                    state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
                var extended: (Expression, TemplateToken)?
                switch compilationState.currentScope.type {
                case .InvertedSection(openingToken: let openingToken, expression: let openingExpression):
                    if (expression == nil && empty) || (openingExpression == expression) {
                        extended = (openingExpression, openingToken)
                    }
                default:
                    break
                }

                if let (extendedExpression, extentedToken) = extended {
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    
//                    // TODO: uncomment and make it compile
//                    if token.templateString !== extentedToken.templateString {
//                        fatalError("Not implemented")
//                    }
                    let templateString = token.templateString
                    let innerContentRange = extentedToken.range.endIndex..<token.range.startIndex
                    let sectionTag = SectionTag(expression: extendedExpression, inverted: true, templateAST: templateAST, innerTemplateString: templateString[innerContentRange])
                    
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(sectionTag)
                    compilationState.pushScope(Scope(type: .Section(openingToken: token, expression: extendedExpression)))
                    return true
                } else if let expression = expression {
                    compilationState.pushScope(Scope(type: .Section(openingToken: token, expression: expression)))
                    compilationState.compilerContentType = .Locked(compilationState.contentType)
                    return true
                } else {
                    state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
            case .InvertedSection(content: let content):
                var error: NSError?
                var empty = false
                let expression = ExpressionParser().parse(content, empty: &empty, error: &error)
                
                if expression == nil && !empty {
                    state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
                var extended: (Expression, TemplateToken)?
                switch compilationState.currentScope.type {
                case .Section(openingToken: let openingToken, expression: let openingExpression):
                    if (expression == nil && empty) || (openingExpression == expression) {
                        extended = (openingExpression, openingToken)
                    }
                default:
                    break
                }
                
                if let (extendedExpression, extentedToken) = extended {
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    
//                    // TODO: uncomment and make it compile
//                    if token.templateString !== extentedToken.templateString {
//                        fatalError("Not implemented")
//                    }
                    let templateString = token.templateString
                    let innerContentRange = extentedToken.range.endIndex..<token.range.startIndex
                    let sectionTag = SectionTag(expression: extendedExpression, inverted: false, templateAST: templateAST, innerTemplateString: templateString[innerContentRange])
                    
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(sectionTag)
                    compilationState.pushScope(Scope(type: .InvertedSection(openingToken: token, expression: extendedExpression)))
                    return true
                } else if let expression = expression {
                    compilationState.pushScope(Scope(type: .InvertedSection(openingToken: token, expression: expression)))
                    compilationState.compilerContentType = .Locked(compilationState.contentType)
                    return true
                } else {
                    state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
            case .InheritableSection(content: let content):
                var error: NSError?
                var empty: Bool = false
                if let inheritableSectionName = inheritableSectionNameFromString(content, inToken: token, empty: &empty, error: &error) {
                    compilationState.pushScope(Scope(type: .InheritableSection(openingToken: token, inheritableSectionName: inheritableSectionName)))
                    compilationState.compilerContentType = .Locked(compilationState.contentType)
                    return true
                } else {
                    state = .Error(error!)
                    return false
                }
                
            case .InheritablePartial(content: let content):
                var error: NSError?
                var empty: Bool = false
                if let partialName = partialNameFromString(content, inToken: token, empty: &empty, error: &error) {
                    compilationState.pushScope(Scope(type: .InheritablePartial(openingToken: token, partialName: partialName)))
                    compilationState.compilerContentType = .Locked(compilationState.contentType)
                    return true
                } else {
                    state = .Error(error!)
                    return false
                }
                
            case .Close(content: let content):
                switch compilationState.currentScope.type {
                case .Root:
                    state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                    return false
                    
                case .Section(openingToken: let openingToken, expression: let closedExpression):
                    var error: NSError?
                    var empty: Bool = false
                    let expression = ExpressionParser().parse(content, empty: &empty, error: &error)
                    switch (expression, empty) {
                    case (nil, true):
                        break
                    case (nil, false):
                        state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                        return false
                    default:
                        if expression != closedExpression {
                            state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                            return false
                        }
                    }
                    
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)

//                    // TODO: uncomment and make it compile
//                    if token.templateString !== openingToken.templateString {
//                        fatalError("Not implemented")
//                    }
                    let templateString = token.templateString
                    let innerContentRange = openingToken.range.endIndex..<token.range.startIndex
                    let sectionTag = SectionTag(expression: closedExpression, inverted: false, templateAST: templateAST, innerTemplateString: templateString[innerContentRange])

                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(sectionTag)
                    return true
                    
                case .InvertedSection(openingToken: let openingToken, expression: let closedExpression):
                    var error: NSError?
                    var empty: Bool = false
                    let expression = ExpressionParser().parse(content, empty: &empty, error: &error)
                    switch (expression, empty) {
                    case (nil, true):
                        break
                    case (nil, false):
                        state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                        return false
                    default:
                        if expression != closedExpression {
                            state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                            return false
                        }
                    }
                    
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    
//                    // TODO: uncomment and make it compile
//                    if token.templateString !== openingToken.templateString {
//                        fatalError("Not implemented")
//                    }
                    let templateString = token.templateString
                    let innerContentRange = openingToken.range.endIndex..<token.range.startIndex
                    let sectionTag = SectionTag(expression: closedExpression, inverted: true, templateAST: templateAST, innerTemplateString: templateString[innerContentRange])
                    
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(sectionTag)
                    return true
                    
                case .InheritablePartial(openingToken: let openingToken, partialName: let closedPartialName):
                    var error: NSError?
                    var empty: Bool = false
                    let partialName = partialNameFromString(content, inToken: token, empty: &empty, error: &error)
                    switch (partialName, empty) {
                    case (nil, true):
                        break
                    case (nil, false):
                        state = .Error(error!)
                        return false
                    default:
                        if (partialName != closedPartialName) {
                            state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                            return false
                        }
                    }
                    
                    if let partialTemplateAST = repository.templateASTNamed(closedPartialName, relativeToTemplateID:templateID, error: &error) {
                        
                        switch partialTemplateAST.type {
                        case .Undefined:
                            break
                        case .Defined(nodes: _, contentType: let partialContentType):
                            if partialContentType != compilationState.contentType {
                                state = .Error(parseErrorAtToken(token, description: "Content type mismatch"))
                                return false
                            }
                        }
                        
                        let partialNode = PartialNode(partialName: closedPartialName, templateAST: partialTemplateAST)
                        let templateASTNodes = compilationState.currentScope.templateASTNodes
                        let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                        let inheritablePartialNode = InheritablePartialNode(partialNode: partialNode, templateAST: templateAST)
                        compilationState.popCurrentScope()
                        compilationState.currentScope.appendNode(inheritablePartialNode)
                        return true
                    } else {
                        state = .Error(error!)
                        return false
                    }
                    
                case .InheritableSection(openingToken: let openingToken, inheritableSectionName: let closedInheritableSectionName):
                    var error: NSError?
                    var empty: Bool = false
                    let inheritableSectionName = inheritableSectionNameFromString(content, inToken: token, empty: &empty, error: &error)
                    switch (inheritableSectionName, empty) {
                    case (nil, true):
                        break
                    case (nil, false):
                        state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                        return false
                    default:
                        if inheritableSectionName != closedInheritableSectionName {
                            state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                            return false
                        }
                    }
                    
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    let inheritableSectionTag = InheritableSectionNode(name: closedInheritableSectionName, templateAST: templateAST)
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(inheritableSectionTag)
                    return true
                }
                
            case .Partial(content: let content):
                var error: NSError?
                var empty: Bool = false
                if let partialName = partialNameFromString(content, inToken: token, empty: &empty, error: &error) {
                    if let partialTemplateAST = repository.templateASTNamed(partialName, relativeToTemplateID: templateID, error: &error) {
                        let partialNode = PartialNode(partialName: partialName, templateAST: partialTemplateAST)
                        compilationState.currentScope.appendNode(partialNode)
                        compilationState.compilerContentType = .Locked(compilationState.contentType)
                        return true
                    } else {
                        state = .Error(error!)
                        return false
                    }
                } else {
                    state = .Error(error!)
                    return false
                }
            }
        }
    }
    
    
    // MARK: - Private
    
    class CompilationState {
        var currentScope: Scope {
            return scopeStack[scopeStack.endIndex - 1]
        }
        var contentType: ContentType {
            switch compilerContentType {
            case .Unlocked(let contentType):
                return contentType
            case .Locked(let contentType):
                return contentType
            }
        }
        
        init(contentType: ContentType) {
            self.compilerContentType = .Unlocked(contentType)
            self.scopeStack = [Scope(type: .Root)]
        }
        
        func popCurrentScope() {
            scopeStack.removeLast()
        }
        
        func pushScope(scope: Scope) {
            scopeStack.append(scope)
        }
        
        enum CompilerContentType {
            case Unlocked(ContentType)
            case Locked(ContentType)
        }
        
        var compilerContentType: CompilerContentType
        private var scopeStack: [Scope]
    }
    
    enum CompilerState {
        case Compiling(CompilationState)
        case Error(NSError)
    }
    
    class Scope {
        let type: Type
        var templateASTNodes: [TemplateASTNode]
        
        init(type:Type) {
            self.type = type
            self.templateASTNodes = []
        }
        
        func appendNode(node: TemplateASTNode) {
            templateASTNodes.append(node)
        }
        
        enum Type {
            case Root
            case Section(openingToken: TemplateToken, expression: Expression)
            case InvertedSection(openingToken: TemplateToken, expression: Expression)
            case InheritablePartial(openingToken: TemplateToken, partialName: String)
            case InheritableSection(openingToken: TemplateToken, inheritableSectionName: String)
        }
    }
    
    func inheritableSectionNameFromString(string: String, inToken token: TemplateToken, inout empty outEmpty: Bool, error outError: NSErrorPointer) -> String? {
        let whiteSpace = NSCharacterSet.whitespaceAndNewlineCharacterSet()
        let inheritableSectionName = string.stringByTrimmingCharactersInSet(whiteSpace)
        if countElements(inheritableSectionName) == 0 {
            if outError != nil {
                outError.memory = parseErrorAtToken(token, description: "Missing inheritable section name")
            }
            outEmpty = true
            return nil
        } else if (inheritableSectionName.rangeOfCharacterFromSet(whiteSpace) != nil) {
            if outError != nil {
                outError.memory = parseErrorAtToken(token, description: "Invalid inheritable section name")
            }
            outEmpty = false
            return nil
        }
        return inheritableSectionName
    }
    
    func partialNameFromString(string: String, inToken token: TemplateToken, inout empty outEmpty: Bool, error outError: NSErrorPointer) -> String? {
        let whiteSpace = NSCharacterSet.whitespaceAndNewlineCharacterSet()
        let partialName = string.stringByTrimmingCharactersInSet(whiteSpace)
        if countElements(partialName) == 0 {
            if outError != nil {
                outError.memory = parseErrorAtToken(token, description: "Missing template name")
            }
            outEmpty = true
            return nil
        } else if (partialName.rangeOfCharacterFromSet(whiteSpace) != nil) {
            if outError != nil {
                outError.memory = parseErrorAtToken(token, description: "Invalid template name")
            }
            outEmpty = false
            return nil
        }
        return partialName
    }
    
    func parseErrorAtToken(token: TemplateToken, description: String) -> NSError {
        let userInfo = [NSLocalizedDescriptionKey: "Parse error at line \(token.lineNumber): \(description)"]
        return NSError(domain: GRMustacheErrorDomain, code: GRMustacheErrorCodeParseError, userInfo: userInfo)
    }
}
