//
//  File.swift
//  
//
//  Created by Misha Nya on 28.02.2023.
//

import SwiftSyntax

class OneDepthDeepVisitor: SyntaxVisitor {
	var depth = 0

	private func skipIfNested() -> SyntaxVisitorContinueKind {
		guard depth == 0 else { return .skipChildren }
		depth += 1
		return .visitChildren
	}

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		skipIfNested()
	}
	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		skipIfNested()
	}
	override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		skipIfNested()
	}
}
