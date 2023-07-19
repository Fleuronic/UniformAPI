// swift-tools-version:5.6
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
		)
	],
	dependencies: [
		.package(url: "https://github.com/Fleuronic/UniformService", branch: "main"),
		.package(url: "https://github.com/Fleuronic/Caesura", branch: "main")
	],
	targets: [
		.target(
			name: "UniformAPI",
			dependencies: [
				"UniformService",
				"Caesura"
			]
		)
	]
)
