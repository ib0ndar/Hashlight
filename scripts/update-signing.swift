// Ed25519 helper for scripts/update-signing.sh. Private keys travel through stdin and stdout
// only, never through arguments, so they do not show up in process listings.
//
//   generate                         print a new private key (base64)
//   public-key                       stdin: private key; print its public key (base64)
//   sign FILE                        stdin: private key; print the signature of FILE (base64)
//   verify FILE SIGNATURE PUBLIC-KEY exit 0 if SIGNATURE (a file holding base64) signs FILE

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("update-signing: \(message)\n".utf8))
    exit(1)
}

func privateKeyFromStandardInput() -> Curve25519.Signing.PrivateKey {
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw = Data(base64Encoded: text),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("stdin does not hold a base64 Ed25519 private key")
    }
    return key
}

func contents(of path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    return data
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "generate" where arguments.count == 1:
    print(Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString())
case "public-key" where arguments.count == 1:
    print(privateKeyFromStandardInput().publicKey.rawRepresentation.base64EncodedString())
case "sign" where arguments.count == 2:
    let key = privateKeyFromStandardInput()
    guard let signature = try? key.signature(for: contents(of: arguments[1])) else { fail("signing failed") }
    print(signature.base64EncodedString())
case "verify" where arguments.count == 4:
    let signatureText = String(decoding: contents(of: arguments[2]), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let signature = Data(base64Encoded: signatureText) else { fail("the signature is not base64") }
    guard let rawKey = Data(base64Encoded: arguments[3]),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else {
        fail("the public key is not a base64 Ed25519 key")
    }
    guard publicKey.isValidSignature(signature, for: contents(of: arguments[1])) else {
        fail("the signature does not match \(arguments[1])")
    }
    print("Signature OK")
default:
    fail("usage: generate | public-key | sign FILE | verify FILE SIGNATURE PUBLIC-KEY")
}
