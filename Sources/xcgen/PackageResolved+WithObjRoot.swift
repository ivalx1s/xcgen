import Foundation


extension PackageResolved {
	enum WithObjRoot {}
}

extension PackageResolved.WithObjRoot {
	struct Root: Codable {
		let object: Object
		let version: Int
	}
	
	struct Object: Codable {
		let pins: [Pin]
	}
	
	struct Pin: Codable {
		let package: String
		let repositoryURL: String
		let state: State
	}
	
	struct State: Codable {
		let branch: JSONNull?
		let revision: String
		let version: String
	}
	
	
	struct JSONNull: Codable, Hashable, Equatable {}
}
