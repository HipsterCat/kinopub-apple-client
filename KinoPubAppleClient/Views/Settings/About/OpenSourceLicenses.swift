//
//  OpenSourceLicenses.swift
//  KinoPubAppleClient
//
//  Settings › About › Licenses: the third-party packages the app links, with their
//  copyright lines, and the licence they share. Every one is MIT with the same text
//  (checked against each package's LICENSE at the pinned version, 2026-10-16), so the
//  text is shown once under all the notices. A new package in `Package.resolved` gets a
//  line here; one under another licence gets its own text.
//

import SwiftUI
import KinoPubUI

struct OpenSourceLicense: Identifiable {
  var name: String
  var url: String
  var copyright: String

  var id: String { name }
}

enum OpenSourceLicenses {
  static let all: [OpenSourceLicense] = [
    OpenSourceLicense(name: "KeychainAccess", url: "github.com/kishikawakatsumi/KeychainAccess",
                      copyright: "Copyright (c) 2014 kishikawa katsumi"),
    OpenSourceLicense(name: "Nuke", url: "github.com/kean/Nuke",
                      copyright: "Copyright (c) 2015-2026 Alexander Grebenyuk"),
    OpenSourceLicense(name: "PopupView", url: "github.com/exyte/PopupView",
                      copyright: "Copyright (c) 2019 exyte <info@exyte.com>"),
    OpenSourceLicense(name: "Pulse", url: "github.com/kean/Pulse",
                      copyright: "Copyright (c) 2020-2024 Alexander Grebenyuk"),
    OpenSourceLicense(name: "Reachability.swift", url: "github.com/ashleymills/Reachability.swift",
                      copyright: "Copyright (c) 2016 Ashley Mills"),
  ]

  static let mitLicense = """
  Permission is hereby granted, free of charge, to any person obtaining a copy \
  of this software and associated documentation files (the "Software"), to deal \
  in the Software without restriction, including without limitation the rights \
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
  copies of the Software, and to permit persons to whom the Software is \
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all \
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
  SOFTWARE.
  """
}

/// The popup's content.
struct OpenSourceLicensesView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      Text("Licenses_Intro")
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(Color.KinoPub.text)
        .fixedSize(horizontal: false, vertical: true)

      ForEach(OpenSourceLicenses.all) { license in
        VStack(alignment: .leading, spacing: 6) {
          Text(verbatim: license.name)
            .font(InfoPopupMetrics.bodyFont.weight(.semibold))
            .foregroundStyle(Color.KinoPub.text)
          Text(verbatim: "\(license.copyright) · MIT License\n\(license.url)")
            .font(.callout)
            .foregroundStyle(Color.KinoPub.subtitle)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        Text(verbatim: "MIT License")
          .font(InfoPopupMetrics.subtitleFont)
          .foregroundStyle(Color.KinoPub.text)
        Text(verbatim: OpenSourceLicenses.mitLicense)
          .font(.callout)
          .foregroundStyle(Color.KinoPub.subtitle)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 8)
    }
  }
}

#Preview("Licenses") {
  InfoPopupView(title: Text("Licenses")) {
    OpenSourceLicensesView()
  }
}
