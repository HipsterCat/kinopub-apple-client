//
//  MediaCardMenuAlerts.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI

extension View {
  /// Presents the New Folder alert driven by `MediaCardMenuCoordinator`, and the HUD
  /// its bookmark toggles show (the same one the detail page's Bookmark menu shows).
  /// Also hosts the Change Images sheet a card's menu opens.
  func mediaCardNewFolderAlert(_ menu: MediaCardMenuCoordinator) -> some View {
    hudToast(Binding(get: { menu.hudToast }, set: { menu.hudToast = $0 }))
    .sheet(item: Binding(get: { menu.imagePickerTarget }, set: { menu.imagePickerTarget = $0 })) { target in
      TitleImagePickerSheet(target: target,
                            images: AppContext.shared.metadataService.images,
                            onSaved: {})
    }
    .alert("New Folder", isPresented: Binding(
      get: { menu.newFolderItemID != nil },
      set: { if !$0 { menu.cancelNewFolder() } }
    )) {
      TextField("Folder name", text: Binding(
        get: { menu.newFolderName },
        set: { menu.newFolderName = $0 }
      ))
      Button("Create") { menu.confirmNewFolder() }
      Button("Cancel", role: .cancel) { menu.cancelNewFolder() }
    }
  }
}
