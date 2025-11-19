
extension PackageResolved {
	enum WithoutObjRoot {}
}

extension PackageResolved.WithoutObjRoot {
	struct Pins: Codable {
		let pins: [Pin]
		let version: Int
	}
	
	struct Pin: Codable {
		let identity: String
		let kind: String
		let location: String
		let state: PinState
	}
	
	struct PinState: Codable {
		let revision: String
		let version: String
	}
}
