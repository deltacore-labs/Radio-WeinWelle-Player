//
//  PlatformImage.swift
//  Radio-WeinWelle-Player
//

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif
