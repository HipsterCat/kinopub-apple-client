//
//  Locale+Extensions.swift
//  Piratic
//
//  Created by Patrikas Karpickas on 06/02/2025.
//
import Foundation

extension Locale {
    static var currentLanguageCode: String {
        self.current.language.languageCode?.identifier ?? "en"
    }
}
