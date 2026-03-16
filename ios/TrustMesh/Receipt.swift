import Foundation

struct ActionCommitment: Codable {
    let actionHash: String
    let timestamp: Int64
    let deviceID: String
    let sessionNonce: String
    let biometricModality: String
}

struct Receipt: Codable {
    let commitment: ActionCommitment
    let signature: String
    let publicKey: String
}
