// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "xcgbootstrap",
	platforms: [
		.macOS(.v11)
	],
	products: [
		.executable(name: "xcgbootstrap", targets: ["xcgbootstrap"])
	],
    dependencies: [
         .package(url: "git@github.com:apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "xcgbootstrap",
            dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			]
		)
    ]
)
