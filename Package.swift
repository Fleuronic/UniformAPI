// swift-tools-version:6.0
import PackageDescription

let package = Package(
	name: "UniformAPI",
	platforms: [
		.iOS(.v15),
		.macOS(.v12),
		.tvOS(.v15),
		.watchOS(.v8)
	],
	products: [
		.library(
			name: "UniformAPI",
			targets: ["UniformAPI"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/Fleuronic/UniformService", branch: "main"),
		.package(url: "https://github.com/tid-kijyun/Kanna.git", from: "5.2.2")
	],
	targets: [
		.target(
			name: "UniformAPI",
			dependencies: [
				"UniformService",
				"Kanna"
			]
		)
	],
	swiftLanguageModes: [.v6]
)

for target in package.targets {
	target.swiftSettings = [
		.enableExperimentalFeature("StrictConcurrency")
	]
}
