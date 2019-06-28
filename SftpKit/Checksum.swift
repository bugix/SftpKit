//
//  Checksum.swift
//  Checksum
//
//  Created by Ruben Nine on 11/11/2016.
//  Copyright © 2016 9Labs. All rights reserved.
//

import CommonCrypto

public typealias CompletionHandler = (_ checksum: String?) -> Void
public typealias ProgressHandler = (_ bytesProcessed: Int, _ totalBytes: Int) -> Void

public enum DigestAlgorithm {

    case md5

    public var digestLength: Int {

        switch self {
        case .md5: return Int(CC_MD5_DIGEST_LENGTH)
        }
    }
}

// MARK: - Public Extensions

public extension URL {

    /**
     Returns a checksum of the file's content referenced by this URL using the specified digest algorithm.

     - Parameter algorithm: The digest algorithm to use.
     - Parameter chunkSize: *(optional)* The processing buffer's size (mostly relevant for large file computing)

     - Note: For large local files or remote resources, you may want to try `checksum(algorithm:chunkSize:queue:progressHandler:completionHandler:)` instead.
     - SeeAlso: `checksum(algorithm:chunkSize:queue:progressHandler:completionHandler:)`

     - Returns: *(optional)* A String with the computed checksum.
     */
    func checksum(algorithm: DigestAlgorithm, chunkSize: Int = 4096) throws -> String? {

        let data = try Data(contentsOf: self, options: .mappedIfSafe)
        return try data.checksum(algorithm: algorithm, chunkSize: chunkSize)
    }

    /**
     Asynchronously returns a checksum of the file's content referenced by this URL using the specified digest algorithm.

     - Parameter algorithm: The digest algorithm to use.
     - Parameter chunkSize: *(optional)* The processing buffer's size (mostly relevant for large file computing)
     - Parameter queue: *(optional)* The dispatch queue used for processing.
     - Parameter progress: *(optional)* The closure to call to signal progress.
     - Parameter completion: The closure to call upon completion containing the checksum.
     */
    func checksum(algorithm: DigestAlgorithm,
                  chunkSize: Int = 4096,
                  queue: DispatchQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background),
                  progress: ProgressHandler?,
                  completion: @escaping CompletionHandler) throws {

        let data = try Data(contentsOf: self, options: .mappedIfSafe)

        data.checksum(algorithm: algorithm,
                      chunkSize: chunkSize,
                      queue: queue,
                      progress: progress,
                      completion: completion)
    }
}

public extension Data {

    /**
     Returns a checksum of the Data's content using the specified digest algorithm.

     - Parameter algorithm: The digest algorithm to use.
     - Parameter *(optional)* chunkSize: The internal buffer's size (mostly relevant for large file computing)

     - Returns: *(optional)* A String with the computed checksum.
     */
    func checksum(algorithm: DigestAlgorithm, chunkSize: Int = 4096) throws -> String? {

        let cc = CCWrapper(algorithm: algorithm)
        var bytesLeft = count

        withUnsafeBytes { (u8Ptr: UnsafePointer<UInt8>) in
            var uMutablePtr = UnsafeMutablePointer(mutating: u8Ptr)

            while bytesLeft > 0 {
                let bytesToCopy = Swift.min(bytesLeft, chunkSize)

                cc.update(data: uMutablePtr, length: CC_LONG(bytesToCopy))

                bytesLeft -= bytesToCopy
                uMutablePtr += bytesToCopy
            }
        }

        cc.final()
        return cc.hexString()
    }

    /**
     Asynchronously returns a checksum of the Data's content using the specified digest algorithm.

     - Parameter algorithm: The digest algorithm to use.
     - Parameter chunkSize: *(optional)* The processing buffer's size (mostly relevant for large file computing)
     - Parameter queue: *(optional)* The dispatch queue used for processing.
     - Parameter progress: *(optional)* The closure to call to signal progress.
     - Parameter completion: The closure to call upon completion containing the checksum.
     */
    func checksum(algorithm: DigestAlgorithm,
                  chunkSize: Int = 4096,
                  queue: DispatchQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background),
                  progress: ProgressHandler?,
                  completion: @escaping CompletionHandler) {

        queue.async {
            let cc = CCWrapper(algorithm: algorithm)
            let totalBytes = self.count
            var bytesLeft = totalBytes

            self.withUnsafeBytes { (u8Ptr: UnsafePointer<UInt8>) in
                var uMutablePtr = UnsafeMutablePointer(mutating: u8Ptr)

                while bytesLeft > 0 {
                    let bytesToCopy = Swift.min(bytesLeft, chunkSize)

                    cc.update(data: uMutablePtr, length: CC_LONG(bytesToCopy))

                    bytesLeft -= bytesToCopy
                    uMutablePtr += bytesToCopy

                    let actualBytesLeft = bytesLeft

                    DispatchQueue.main.async {
                        progress?(totalBytes - actualBytesLeft, totalBytes)
                    }
                }
            }

            cc.final()

            DispatchQueue.main.async {
                completion(cc.hexString())
            }
        }
    }
}

// MARK: - CCWrapper (for internal use)

private class CCWrapper {

    private typealias CC_XXX_Update = (UnsafeRawPointer, CC_LONG) -> Void
    private typealias CC_XXX_Final = (UnsafeMutablePointer<UInt8>) -> Void

    public let algorithm: DigestAlgorithm

    private var digest: UnsafeMutablePointer<UInt8>?
    private var md5Ctx: CC_MD5_CTX?
    private var updateFun: CC_XXX_Update?
    private var finalFun: CC_XXX_Final?

    init(algorithm: DigestAlgorithm) {

        self.algorithm = algorithm

        switch algorithm {
        case .md5:
            var ctx = CC_MD5_CTX()

            CC_MD5_Init(&ctx)

            md5Ctx = ctx
            updateFun = { (data, len) in CC_MD5_Update(&ctx, data, len) }
            finalFun = { (digest) in CC_MD5_Final(digest, &ctx) }
        }
    }

    deinit {

        digest?.deallocate()
    }

    func update(data: UnsafeMutableRawPointer, length: CC_LONG) {

        updateFun?(data, length)
    }

    func final() {

        // We already got a digest, return early
        guard digest == nil else { return }

        digest = UnsafeMutablePointer<UInt8>.allocate(capacity: algorithm.digestLength)

        if let digest = digest {
            finalFun?(digest)
        }
    }

    func hexString() -> String? {

        // We DON'T have a digest YET, return early
        guard let digest = digest else { return nil }

        var string = ""

        for i in 0..<algorithm.digestLength {
            string += String(format: "%02x", digest[i])
        }

        return string
    }
}
