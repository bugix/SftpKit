//
//  SftpSession.swift
//  SFTPKit
//
//  Created by Martin Imobersteg on 03.05.19.
//  Copyright © 2019 Martin Imobersteg. All rights reserved.
//

import Foundation
import Libssh2

public struct SftpError: Error {
    let reason: String
}

public class SftpSession {

    let hostname: String
    let username: String
    let password: String

    var cancel = false

    public init(hostname: String, username: String, password: String) {
        self.hostname = hostname
        self.username = username
        self.password = password
    }

    public func download(file pathAndFileName: String, md5: String, failure: (SftpError) -> Void, success: () -> Void, progress: (_ bytesRead: Int, _ totalBytes: Int) -> Void) {

        let fileName = (pathAndFileName as NSString).lastPathComponent

        let documentUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileUrlInDocument = documentUrl.appendingPathComponent(fileName)

        let cacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileUrlInCache = cacheUrl.appendingPathComponent(fileName)

        guard libssh2_init(0) == 0 else {
            failure(SftpError(reason: "libssh2_init"))
            return
        }

        let session = libssh2_session_init_ex(nil, nil, nil, UnsafeMutableRawPointer(mutating: _bridge(self)))

        guard session != nil else {
            failure(SftpError(reason: "libssh2_session_init"))
            return
        }

        guard let socket = openSocket() else {
            failure(SftpError(reason: "socket_open"))
            return
        }

        defer {
            if CFSocketIsValid(socket) {
                CFSocketInvalidate(socket)
            }
        }

        guard libssh2_session_handshake(session, CFSocketGetNative(socket)) == 0 else {
            failure(SftpError(reason: "libssh2_session_handshake"))
            return
        }

        defer {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "disconnect", "")
        }

        let userauth = libssh2_userauth_password_ex(session, username, UInt32(username.utf8.count), password, UInt32(password.utf8.count), nil)

        guard userauth == 0 || userauth == Int(LIBSSH2_ERROR_EAGAIN) else {
            failure(SftpError(reason: "libssh2_userauth_password"))
            return
        }

        guard let sftpSession = libssh2_sftp_init(session) else {
            failure(SftpError(reason: "libssh2_sftp_init"))
            return
        }

        defer {
            libssh2_sftp_shutdown(sftpSession)
        }

        libssh2_session_set_blocking(session, 1)

        FileManager.default.createFile(atPath: fileUrlInCache.path, contents: nil, attributes: nil)

        guard let handle = libssh2_sftp_open_ex(sftpSession, pathAndFileName, UInt32(pathAndFileName.utf8.count), UInt(LIBSSH2_FXF_READ), 0, LIBSSH2_SFTP_OPENFILE) else {
            failure(SftpError(reason: "libssh2_sftp_open"))
            return
        }

        defer {
            libssh2_sftp_close_handle(handle)
        }

        let attributes = UnsafeMutablePointer<LIBSSH2_SFTP_ATTRIBUTES>.allocate(capacity: 1)
        libssh2_sftp_fstat_ex(handle, attributes, 0)

        let fileSize = attributes.pointee.filesize

        let bufferSize = 32 * 1024
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufferSize)

        defer {
            buffer.deallocate()
        }

        guard let fileHandle = try? FileHandle(forUpdating: fileUrlInCache) else {
            failure(SftpError(reason: "fileHandle"))
            return
        }

        var bytesRead = 0
        var returnCode: Int

        repeat {

            returnCode = libssh2_sftp_read(handle, buffer, bufferSize)

            guard returnCode >= 0 || returnCode == Int(LIBSSH2_ERROR_EAGAIN) else {
                failure(SftpError(reason: "libssh2_sftp_read"))
                return
            }

            if returnCode > 0 {
                let data = NSData(bytes: buffer, length: returnCode)
                fileHandle.write(data as Data)
                bytesRead += returnCode

                progress(bytesRead, Int(fileSize))
            }

        } while returnCode > 0 && !cancel

        fileHandle.synchronizeFile()
        fileHandle.closeFile()

        if cancel {

            do {
                try FileManager.default.removeItem(at: fileUrlInCache)
            } catch {
                print("Failed to remove cached file")
            }

            failure(SftpError(reason: "canceled"))
            return
        }

        if let md5sum = try? fileUrlInCache.checksum(algorithm: .md5), md5sum == md5 {

            // Move cache file to document directory
            do {
                if FileManager.default.fileExists(atPath: fileUrlInDocument.path) {
                    try FileManager.default.removeItem(at: fileUrlInDocument)
                }
                try FileManager.default.moveItem(at: fileUrlInCache, to: fileUrlInDocument)
                success()
            } catch {
                failure(SftpError(reason: "can not move"))
            }

        } else {
            failure(SftpError(reason: "md5sum did not match"))
        }

    }

    public func write(data: Data, path: String, filename: String, success: () -> Void, failure: (SftpError) -> Void) {

        guard libssh2_init(0) == 0 else {
            failure(SftpError(reason: "libssh2_init"))
            return
        }

        let session = libssh2_session_init_ex(nil, nil, nil, UnsafeMutableRawPointer(mutating: _bridge(self)))

        guard session != nil else {
            failure(SftpError(reason: "libssh2_session_init"))
            return
        }

        guard let socket = openSocket() else {
            failure(SftpError(reason: "socket_open"))
            return
        }

        defer {
            if CFSocketIsValid(socket) {
                CFSocketInvalidate(socket)
            }
        }

        guard libssh2_session_handshake(session, CFSocketGetNative(socket)) == 0 else {
            failure(SftpError(reason: "libssh2_session_handshake"))
            return
        }

        defer {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "disconnect", "")
        }

        let userauth = libssh2_userauth_password_ex(session, username, UInt32(username.utf8.count), password, UInt32(password.utf8.count), nil)

        guard userauth == 0 || userauth == Int(LIBSSH2_ERROR_EAGAIN) else {
            failure(SftpError(reason: "libssh2_userauth_password"))
            return
        }

        guard let sftpSession = libssh2_sftp_init(session) else {
            failure(SftpError(reason: "libssh2_sftp_init"))
            return
        }

        defer {
            libssh2_sftp_shutdown(sftpSession)
        }

        libssh2_session_set_blocking(session, 1)

        var fullPath = path

        if let last = fullPath.last, last == "/" {
            fullPath = String(fullPath[..<fullPath.index(before: fullPath.endIndex)])
        }

        var intermediatePath = ""

        if let first = fullPath.first, first == "/" {
            fullPath.remove(at: fullPath.startIndex)
            intermediatePath = "/"
        }

        let pathComponents = fullPath.components(separatedBy: "/")

        for pathComponent in pathComponents {
            intermediatePath += pathComponent

            libssh2_sftp_mkdir_ex(sftpSession, path, UInt32(path.utf8.count), Int(LIBSSH2_SFTP_S_IRWXU | LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IXGRP | LIBSSH2_SFTP_S_IROTH | LIBSSH2_SFTP_S_IXOTH))

            intermediatePath += "/"
        }

        let pathAndFilename = intermediatePath + filename

        guard let handle = libssh2_sftp_open_ex(sftpSession, pathAndFilename, UInt32(pathAndFilename.utf8.count), UInt(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC), Int(LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR | LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IROTH), LIBSSH2_SFTP_OPENFILE) else {
            failure(SftpError(reason: "libssh2_sftp_open"))
            return
        }

        let bufferSize = 32 * 1024
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufferSize)

        defer {
            buffer.deallocate()
        }

        var bytesWritten = 0
        var returnCode: Int

        repeat {
            let length = min(data.count, bufferSize)
            (data as NSData).getBytes(buffer, range: NSRange(location: bytesWritten, length: length))

            returnCode = libssh2_sftp_write(handle, buffer, length)

            guard returnCode >= 0 || returnCode == Int(LIBSSH2_ERROR_EAGAIN) else {
                failure(SftpError(reason: "libssh2_sftp_write"))
                return
            }

            if returnCode > 0 {
                bytesWritten += returnCode
            }
        } while bytesWritten < data.count

        success()
    }

    private func openSocket() -> CFSocket? {
        let addresses: [Data]

        do {
            addresses = try DNS(hostname: hostname).lookup() as [Data]
        } catch {
            return nil
        }

        for address in addresses {

            let addressFamily: Int32
            let dataAddress: Data

            switch address.count {
            case MemoryLayout<sockaddr_in>.size:
                // IPv4
                var socketAddress: sockaddr_in = address.withUnsafeBytes {
                    UnsafeRawPointer($0).bindMemory(to: sockaddr_in.self, capacity: address.count).pointee
                }
                socketAddress.sin_port = CFSwapInt16HostToBig(22)
                addressFamily = AF_INET
                dataAddress = Data(bytes: &socketAddress, count: MemoryLayout.size(ofValue: socketAddress))

            case MemoryLayout<sockaddr_in6>.size:
                // IPv6
                var socketAddress: sockaddr_in6 = address.withUnsafeBytes {
                    UnsafeRawPointer($0).bindMemory(to: sockaddr_in6.self, capacity: address.count).pointee
                }
                socketAddress.sin6_port = CFSwapInt16HostToBig(22)
                addressFamily = AF_INET6
                dataAddress = Data(bytes: &socketAddress, count: MemoryLayout.size(ofValue: socketAddress))

            default:
                continue
            }

            guard let socket = CFSocketCreate(kCFAllocatorDefault, addressFamily, SOCK_STREAM, IPPROTO_IP, 0, nil, nil) else {
                continue
            }

            guard socket.setSocketOption(1, level: SOL_SOCKET, name: SO_NOSIGPIPE) else {
                continue
            }

            if CFSocketConnectToAddress(socket, dataAddress as CFData, Double(5)/1000) == .success {
                return socket
            }
        }

        return nil
    }
}

internal func _bridge<T: AnyObject>(_ obj: T) -> UnsafeRawPointer {
    return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

internal func _bridge<T: AnyObject>(_ ptr: UnsafeRawPointer) -> T {
    return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

internal extension CFSocket {

    func setSocketOption<T: BinaryInteger>(_ value: T, level: Int32, name: Int32) -> Bool {
        var value = value
        if setsockopt(CFSocketGetNative(self), level, name, &value, socklen_t(MemoryLayout.size(ofValue: value))) == -1 {
            return false
        }

        return true
    }

}
