//
//  Config.swift
//  AVSExample
//

import Foundation
import Foundation

struct Config {
    
    struct LoginWithAmazon {
        static let ClientId = "<< Client ID Here >>"
        static let ProductId = "<< Product ID Here >>"
        static let DeviceSerialNumber = "<< Device Serial Number Here >>"
    }
    
    struct Debug {
        static let General = false
        static let Errors = true
        static let HTTPRequest = false
        static let HTTPResponse = false
    }
    
    struct Error {
        static let ErrorDomain = "net.ioncannon.SimplePCMRecorderError"
        
        static let PCMSetupIncompleteErrorCode = 1
        
        static let AVSUploaderSetupIncompleteErrorCode = 2
        static let AVSAPICallErrorCode = 3
        static let AVSResponseBorderParseErrorCode = 4
    }

}
