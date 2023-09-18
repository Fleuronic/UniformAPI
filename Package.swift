// swift-tools-version:5.7
import PackageDescription

let package = Package(
	name: "UniformAPI",
	platforms: [
		.macOS(.v13)
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
