//
//  File.swift
//  
//
//  Created by zm on 19.08.24.
//

import Foundation

struct RestoreRequest: Codable {
    let outputs:[Output]
}

struct RestoreResponse: Codable {
    let outputs:[Output]
    let signatures:[Promise]
}
