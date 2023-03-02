import Foundation

import SwiftLintFramework

import SwiftSyntax

import IDEUtils
import SwiftParser

import SourceKittenFramework

private var locationConverter: SourceLocationConverter!
private var filePath: String!

func markBadCode(at node: SyntaxProtocol, _ message: String, error: Bool = true) {
	let loc = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
	
	print(
		[filePath,
		 ":\(String(loc.line ?? 0)):\(String(loc.column ?? 0)): ",
		 "\(error ? "error" : "warning"): ",
		 message].joined()
	)
}

let ruleList = [LightweightInitRule(viewMode: .all)]

@main
public struct CustomLinter {
    public static func main() throws {
		let files = CommandLine.arguments
			.dropFirst() // первый аргумент – это путь до executable
			.filter(FileManager.default.fileExists(atPath:))
			.compactMap(URL.init(string:))

		guard !files.isEmpty else {
			fatalError("invalid files input")
		}

		let sources = files.lazy
			.compactMap { (url: URL) -> (url: URL, content: String)? in
				guard let fileContent = FileManager.default.contents(atPath: url.absoluteString) else { return nil }
				guard let stringContent = String(data: fileContent, encoding: .utf8) else { return nil }
				return (url: url, content: stringContent)
			}

		sources.forEach {
			let syntax = Parser.parse(source: $0.content)
			locationConverter = .init(file: $0.content, tree: syntax)
			filePath = $0.url.absoluteString
			ruleList.forEach { $0.walk(syntax) }
		}
	}
}


/*
 SwiftSyntaxRule – можно получить кэш использовав функцию preprocess

 Функция получения syntaxTree из кэша (internal)
 Доступна из SwiftSyntaxRule
 func preprocess(file: SwiftLintFile) -> SourceFileSyntax? {
	 file.syntaxTree
 }
 */
struct SwiftLintCustomRule: SourceKitFreeRule {
	func validate(file: SwiftLintFramework.SwiftLintFile) -> [SwiftLintFramework.StyleViolation] {
		//file.syntaxClassifications // internal protection level

		// не используется кэш. Чтобы заиспользовать кэш swiftlint нужно использовать
		// SwiftSyntaxRule – можно получить кэш использовав функцию preprocess
		let syntaxTree = Parser.parse(source: file.contents)
		visitor.walk(syntaxTree)
		return []
	}

	let visitor = LightweightInitRule(viewMode: .all)

	init(configuration: Any) throws {}
	init() {}

	static var description: SwiftLintFramework.RuleDescription = .init(identifier: "bad-words",
																	   name: "Bad Words",
																	   description: "",
																	   kind: .style)

	var configurationDescription: String = ""
}

private func tryingToLaunchRuleWithSwiftLint() throws {
	let reporter = reporterFrom(identifier: XcodeReporter.identifier)
	let cache = LinterCache(configuration: .default)
	let otherRules = primaryRuleList
	var rules = RuleList(rules: [SwiftLintCustomRule.self])
	let config = try Configuration(dict: [:], ruleList: rules, enableAllRules: true)

	let files = [String]() // FileManager.default.filesToLint(inPath: "Sources", rootDirectory: nil)

	config.rules.forEach { rule in
		files.forEach { file in
			guard !(rule is AnalyzerRule) else { return }
			let violations = rule.validate(file: .init(path: file)!)
			let report = XcodeReporter.generateReport(violations)
			if !report.isEmpty { print(report) }
		}
	}
}
