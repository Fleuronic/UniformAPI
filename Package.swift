// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "UniformAPI",
	platforms: [
		.iOS(.v13),
		.macOS(.v10_15),
		.tvOS(.v13),
		.watchOS(.v6)
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
