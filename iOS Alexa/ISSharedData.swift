//
//  ISSharedData.swift
//  iOS Alexa
//
//  Created by Chintan Prajapati on 24/05/16.
//  Copyright © 2016 Chintan. All rights reserved.
//

import Foundation

open class ISSharedData : NSObject {
    open static let sharedInstance = ISSharedData()
    
    open var accessToken:String?
}
