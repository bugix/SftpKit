//
//  SftpSession.swift
//  SFTPKit
//
//  Created by Martin Imobersteg on 03.05.19.
//  Copyright © 2019 Martin Imobersteg. All rights reserved.
//

import Foundation
import Libssh2

class SftpSession {

    let hostname: String
    let username: String
    let password: String

    init(hostname: String, username: String, password: String) {
        self.hostname = hostname
        self.username = username
        self.password = password
    }

    func connect() {
        guard libssh2_init(0) == 0 else {
            print("failure")
            return
        }

        print("success")
    }

}
