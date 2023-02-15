// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "xcgen",
	platforms: [
		.macOS(.v11)
	],
	products: [
		.executable(name: "xcgen", targets: ["xcgen"])
	],
    dependencies: [
         .package(url: "git@github.com:apple/swift-argument-parser.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "xcgen",
            dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			]
		)
    ]
)
