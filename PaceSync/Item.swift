//
//  Item.swift
//  PaceSync
//
//  Created by bernhardt meyer on 2026/03/12.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
