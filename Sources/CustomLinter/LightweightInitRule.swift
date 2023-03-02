//
//  File.swift
//  
//
//  Created by Misha Nya on 28.02.2023.
//

import SwiftSyntax

private var verboseVars = true
private var verboseInit = false
private var verboseStruct = false

class LightweightInitRule: SyntaxVisitor {

	/*
	 TODO: #member-check
	 Реализовать проход по вложенным enum-ам/struct-ам, собрать скалярные переменные,
	 скалярные переменные можно разрешить для использования в инициализируемых переменных

	 enum Hardcoded {
		 static let shadowRadius = 1
	 }
	 // это ок
	 var shadowRadius = Hardcoded.shadowRadius

	 */
	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		if verboseInit { print("-----------LightweightInitRule StructVisitor-----------") }
		defer {
			if verboseInit { print("-----------LightweightInitRule StructVisitor-----------") }
		}

		if verboseInit {
			print("Struct Identifier: ", node.identifier)
		}

		let isView = node.inheritanceClause?.inheritedTypeCollection.contains {
			print("inheritanceClause typeName kind: ", $0.typeName.kind)
			let simpleType = $0.typeName.as(SimpleTypeIdentifierSyntax.self)

			// Если в вашем проекте используется кастомный протокол для View
			// то нужно кастомизировать нейминг
			return simpleType?.name.text == "View"
		}

		/*
		 Идея в том чтобы сначала найти класс/структуру которая нас интересует
		 а в body этого класса запустить внутренний visitor для поиска переменных и инициализатора
		 */
		if (isView == true) {
			let varsChecker = VarsChecker(viewMode: .all)
			varsChecker.walk(node)
			let initChecker = InitChecker(viewMode: .all)
			initChecker.walk(node)

			if (initChecker.initializedMembers.count > varsChecker.declarations.count) {
				// присваивается что-то лишнее
				// можно дописать эту проверку если реализовать учет нескольких инициализаторов
			}
		}

		return .visitChildren // struct can contain another struct
	}
}

private class InitChecker: OneDepthDeepVisitor {

	var initializedMembers = Set<String>()

	private let reason = "Не делай лишнего в init"

	override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		// todo: find all expressions

		if verboseInit { print("-----------InitChecker-----------") }
		defer {
			if verboseInit { print("-----------InitChecker-----------") }
		}

		guard let body = node.body else {
			return .skipChildren
		}

		var probablyBadCode: [SyntaxProtocol] = []

		for statement in body.statements {
			switch statement.item {
			case .decl(let decl):
				if verboseInit { print("decl: ", decl) }
				/*
				 пример с decl:
				 init() {
					 let radius = 1 // эта строчка содержит decl
					 self.shadowRadius = foo
				 }
				 */
				probablyBadCode.append(decl)
			case .stmt(let stmt):
				if verboseInit { print("stmt: ", stmt) }
				/*
				 пример stmt:
				 init() {
					for _ in 0...100 { ... } // эта строчка содержит stmt (forInStmt)
				 }
				 */
				probablyBadCode.append(stmt)
			case .expr(let expressionSyntax):
				if verboseInit { print("expr: ", expressionSyntax) }
				guard let seqExpression = expressionSyntax.as(SequenceExprSyntax.self) else {
					probablyBadCode.append(expressionSyntax)
					break
				}

				var expectedSyntax: [SwiftSyntax.SyntaxKind] = [
					.memberAccessExpr, .assignmentExpr, .identifierExpr
				]

				if verboseInit { print("expr elements kind: ", seqExpression.elements.map{$0.kind}) }
				// TODO: сделать исключение для StateObject
				/*
				 init(config: Config) {
				    memberAccessExpr     assignmentExpr    memberAccessExpr
					self.shadowRadius          =           config.shadowRadius
				}
				 не позволяем такой код потому что shadowRadius у config может содержать логику
				 которая не анализируется на сложность исполнения
				 */

				for expr in seqExpression.elements.reversed() {
					guard expectedSyntax.last != nil else {
						probablyBadCode.append(expressionSyntax)
						break
					}
					guard expectedSyntax.removeLast() == expr.kind else {
						probablyBadCode.append(expressionSyntax)
						break
					}
				}
				guard expectedSyntax.isEmpty else {
					probablyBadCode.append(expressionSyntax)
					break
				}
				// типы валидируются сверху, force unwrap не упадет
				let memberAccess = seqExpression.elements.first!.as(MemberAccessExprSyntax.self)!
				initializedMembers.insert(memberAccess.name.text)
			case .tokenList(let tokenList):
				probablyBadCode.append(tokenList)
			case .nonEmptyTokenList(let tokenList):
				probablyBadCode.append(tokenList)
			}
		}
		probablyBadCode.forEach {
			if verboseInit {
				print($0.description)
			}
			markBadCode(at: $0, reason)
		}
		return .skipChildren
	}
}

/// Сбор неинициализированных переменных для дальнейшего сопоставления
/// с теми что присваиваются в init-е.
///
/// Также проверяем что в рамках тела структуры не инициализируются
/// классы (StateObject – исключение)
private class VarsChecker: OneDepthDeepVisitor {
	/// Объявленные переменные нуждающиеся в инициализации в рамках init
	var declarations: Set<String> = []

	private func tooComplex(code: CodeBlockItemListSyntax) -> Bool {
		if code.count > 1 { return true }
		guard let item = code.first?.item else { return false }
		// TODO: дополнить другими кейсами по мере срабатывания
		return !(item.kind == .integerLiteralExpr
				 || item.kind == .stringLiteralExpr
				 || item.kind == .floatLiteralExpr)
	}

	override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		if (verboseVars) {
			print("-----------VarsChecker-----------")
			print(node.description)
		}

		defer {
			if (verboseVars) { print("-----------VarsChecker-----------") }
		}

		/*
		 пример когда bindings.count > 1 –– let a: Int, b: Int, c = 1
		 */
		node.bindings.forEach {
			if (verboseVars) {
				print("binding pattern: ", $0.pattern)
				print("binding type annotation: ", $0.typeAnnotation ?? "-")
				print("binding initializer kind: ", $0.initializer?.value.kind ?? "-")
				print("binding initializer value: ", $0.initializer?.value ?? "-")
				print("binding accesor: ", $0.accessor ?? "-")
			}

			if $0.initializer?.value.is(FunctionCallExprSyntax.self) == true {
				/*
				 Примеры FunctionCallExprSyntax
				 var foo = Foo()
				 var foo = makeFoo()
				 var foo: Foo = { return Foo() }()
				 */
				// TODO: сделать исключение для StateObject
				markBadCode(at: $0.initializer!, "Выноси все инициализируемые объекты в ViewModel")
			}

			// TODO: #member-check регистрация memberAccessExpr в initializer.value

			if let accessor = $0.accessor {
				func check(getter body: CodeBlockSyntax?) {
					guard let body else { return }
					/*
					 В теории в декларации переменной можно уместить хоть целый класс

					 var foo: Int {
						 class Bar { var foo = 1 } // это ок, скомпилируется
						 return Bar().foo
					 }
					 */
					if tooComplex(code: body.statements) {
						markBadCode(at: body, "Упрости инициализатор. Используй только присваивание передаваемых переменных")
					}
				}
				switch accessor {
				case .accessors(let block):
					block.accessors.forEach {
						if $0.accessorKind.text != "get" {
							// setter и прочие в View не имеет смысла
							markBadCode(at: $0, "асесоры помимо get нет смысла добавлять в View")
						} else {
							check(getter: $0.body)
						}
					}
				case .getter:
					// тут можно реализовать проверку на тип и разрешать использование getter-а только View типов
					break
				}
			}
			/*
			 accessor не nil –– var a: Int { 1 }
			 initializer не nil –– var a = 1
			 */

			guard $0.initializer == nil, $0.accessor == nil else { return }
			/*
			 Валидный синтаксис binding-pattern в структурах:

			 pattern → tuple-pattern type-annotation?
			 pattern → identifier-pattern type-annotation?
			 pattern → wildcard-pattern type-annotation?

			 пример с wildcard –– let _ = 0
			 пример с tuple –– let (x,y) = (1,2)
			 */
			// TODO: обработка wildcard и tuple
			guard let identifierPattern = $0.pattern.as(IdentifierPatternSyntax.self) else { return }
			let name = identifierPattern.identifier.text
			declarations.insert(name)
		} // end node.bindings.forEach

		return .skipChildren
	}
}
