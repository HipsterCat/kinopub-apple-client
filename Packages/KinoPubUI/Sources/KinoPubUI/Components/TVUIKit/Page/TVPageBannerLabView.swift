#if os(tvOS)
//
//  TVPageBannerLabView.swift
//  KinoPubUI
//
//  Interactive developer lab for experimenting with Home banner (`TVPageBannerCell`) chrome,
//  placement, alignment, poster visibility, scrims, blend modes, and real catalogue IDs.
//  Uses a 50/50 split layout: pinned live banner on the left, settings controls on the right.
//

import KinoPubMedia
import SwiftUI
import UIKit

public struct TVPageBannerLabView: View {
  @State private var sampleID: Int = TVPageBannerSamples.primaryID
  @State private var hasLogo: Bool = true
  @State private var hasBackdrop: Bool = true
  @State private var hasPoster: Bool = true

  @State private var logoPlacement: TVPageBannerLogoPlacement = TVPageBannerChrome.current.logoPlacement
  @State private var alignment: TVPageBannerContentAlignment = TVPageBannerChrome.current.alignment
  @State private var showsPoster: Bool = TVPageBannerChrome.current.showsPoster
  @State private var scrimChoice: BannerLabScrim = .edgesBlack
  @State private var blend: TVPageBannerBlend = TVPageBannerChrome.current.blend
  @State private var vibrance: Double = Double(TVPageBannerChrome.current.textVibrance)

  @State private var activeHintTitle: String = "Home Banner Lab"
  @State private var activeHintDescription: String = "Интерактивная настройка баннера на главной: размещение логотипа, выравнивание, наложение блендов, градиенты затемнения, яркость текста и переключение тайтлов каталога."

  public init() {}

  public var body: some View {
    HStack(alignment: .top, spacing: 48) {
      // LEFT COLUMN: Pinned live banner + description text (always visible)
      VStack(alignment: .center, spacing: 24) {
        TVPageBannerHost(chrome: chrome, feature: feature)
          .frame(width: 720, height: 450)

        VStack(alignment: .leading, spacing: 8) {
          Text(activeHintTitle)
            .font(.headline)
            .foregroundStyle(.primary)
          Text(activeHintDescription)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 720, alignment: .leading)

        Spacer()
      }
      .frame(maxWidth: .infinity)
      .padding(.leading, 40)
      .padding(.top, 40)

      // RIGHT COLUMN: Scrollable settings controls
      ScrollView {
        VStack(alignment: .leading, spacing: 36) {
          presetsSection
          catalogIDSection
          logoSection
          alignmentSection
          posterSection
          scrimSection
          blendSection
          vibranceSection
          resetSection
        }
        .padding(.trailing, 60)
        .padding(.top, 40)
        .padding(.bottom, 60)
      }
      .frame(maxWidth: .infinity)
    }
    .background(Color.KinoPub.background)
    .navigationTitle("Banner Chrome Lab")
  }

  // MARK: - Banner Model

  private var chrome: TVPageBannerChrome {
    var draft = TVPageBannerChrome.current
    draft.logoPlacement = logoPlacement
    draft.alignment = alignment
    draft.showsPoster = showsPoster
    draft.blend = blend
    draft.textVibrance = CGFloat(vibrance)
    if let scrim = scrimChoice.value {
      draft.scrim = scrim
    }
    return draft
  }

  private var feature: TVPageFeature {
    TVPageBannerSamples.makeFeature(
      id: sampleID,
      title: sampleID == TVPageBannerSamples.primaryID ? "Паук-Нуар" : "Тайтл #\(sampleID)",
      overview: sampleID == TVPageBannerSamples.primaryID
        ? TVPageBannerSamples.primaryOverview
        : "Арт и постер загружаются напрямую из каталога staticpop по ID \(sampleID).",
      hasLogo: hasLogo && sampleID == TVPageBannerSamples.primaryID,
      hasBackdrop: hasBackdrop,
      hasPoster: hasPoster
    )
  }

  // MARK: - Right Column Sections

  private var presetsSection: some View {
    controlSection("ПРЕСЕТЫ ТАЙТЛА") {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(BannerLabPreset.allCases) { preset in
          Button {
            applyPreset(preset)
            setHint(
              title: preset.label,
              description: "Готовый сценарий: \(preset.label). Проверяет поведение плашки и подстройку контента."
            )
          } label: {
            HStack(spacing: 12) {
              Image(systemName: isCurrentPreset(preset) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isCurrentPreset(preset) ? .primary : .secondary)
              Text(preset.label)
                .font(.callout)
              Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
          }
          .buttonStyle(.card)
        }
      }
    }
  }

  private var catalogIDSection: some View {
    controlSection("КАТАЛОГ STATICPOP (ID)") {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
          Button("−10") {
            sampleID = max(1, sampleID - 10)
            setCatalogHint()
          }
          .buttonStyle(.card)

          Button("−1") {
            sampleID = max(1, sampleID - 1)
            setCatalogHint()
          }
          .buttonStyle(.card)

          Text("ID: \(sampleID)")
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)

          Button("+1") {
            sampleID += 1
            setCatalogHint()
          }
          .buttonStyle(.card)

          Button("+10") {
            sampleID += 10
            setCatalogHint()
          }
          .buttonStyle(.card)
        }

        Button("Сброс к 125269 (Паук-Нуар)") {
          sampleID = TVPageBannerSamples.primaryID
          hasLogo = true
          hasBackdrop = true
          hasPoster = true
          setHint(
            title: "Каталог ID",
            description: "Возврат к основному тестовому тайтлу 125269 (Паук-Нуар) с высоким разрешением бэкдропа и логотипом."
          )
        }
        .buttonStyle(.card)
      }
    }
  }

  private var logoSection: some View {
    controlSection("РАЗМЕЩЕНИЕ ЛОГОТИПА") {
      HStack(spacing: 12) {
        Button {
          logoPlacement = .top
          setHint(title: "Логотип: Top", description: "Логотип закреплен в верхнем инсете карточки баннера.")
        } label: {
          HStack(spacing: 8) {
            if logoPlacement == .top { Image(systemName: "checkmark") }
            Text("Top")
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)

        Button {
          logoPlacement = .aboveCopy
          setHint(title: "Логотип: Above copy", description: "Логотип смещен в колонку контента непосредственно над синопсисом.")
        } label: {
          HStack(spacing: 8) {
            if logoPlacement == .aboveCopy { Image(systemName: "checkmark") }
            Text("Above copy")
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)
      }
    }
  }

  private var alignmentSection: some View {
    controlSection("ВЫРАВНИВАНИЕ КОНТЕНТА") {
      HStack(spacing: 12) {
        Button {
          alignment = .leading
          setHint(title: "Выравнивание: Leading", description: "Текстовая колонка слева, постер справа.")
        } label: {
          HStack(spacing: 8) {
            if alignment == .leading { Image(systemName: "checkmark") }
            Text("Leading")
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)

        Button {
          alignment = .center
          setHint(title: "Выравнивание: Center", description: "Сгруппированный блок контента по центру карточки.")
        } label: {
          HStack(spacing: 8) {
            if alignment == .center { Image(systemName: "checkmark") }
            Text("Center")
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)
      }
    }
  }

  private var posterSection: some View {
    controlSection("ПОСТЕР") {
      Button {
        showsPoster.toggle()
        setHint(
          title: "Постер",
          description: showsPoster ? "Постер включен." : "Постер скрыт — широкий бэкдроп занимает все пространство."
        )
      } label: {
        HStack(spacing: 10) {
          Image(systemName: showsPoster ? "checkmark.circle.fill" : "circle")
          Text("Показывать постер: \(showsPoster ? "ВКЛ" : "ВЫКЛ")")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
      }
      .buttonStyle(.card)
    }
  }

  private var scrimSection: some View {
    controlSection("ЗАТЕМНЕНИЕ (SCRIM)") {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(BannerLabScrim.allCases) { item in
          Button {
            scrimChoice = item
            setHint(title: "Затемнение: \(item.label)", description: item.explanation)
          } label: {
            HStack(spacing: 10) {
              if scrimChoice == item { Image(systemName: "checkmark") }
              Text(item.label)
              Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
          }
          .buttonStyle(.card)
        }
      }
    }
  }

  private var blendSection: some View {
    controlSection("РЕЖИМ НАЛОЖЕНИЯ (BLEND)") {
      HStack(spacing: 10) {
        ForEach(TVPageBannerBlend.allSupportedCases, id: \.self) { item in
          Button {
            blend = item
            setHint(title: "Blend: \(item.title)", description: "Compositing-фильтр \(item.title) поверх бэкдропа.")
          } label: {
            HStack(spacing: 6) {
              if blend == item { Image(systemName: "checkmark") }
              Text(item.title)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
          }
          .buttonStyle(.card)
        }
      }
    }
  }

  private var vibranceSection: some View {
    controlSection("ЯРКОСТЬ ТЕКСТА (VIBRANCE)") {
      HStack(spacing: 16) {
        Button("− 0.05") {
          vibrance = max(0, ((vibrance - 0.05) * 20).rounded() / 20)
          setHint(title: "Vibrance", description: "Смешивание цвета вторичного текста к белому: \(String(format: "%.2f", vibrance)).")
        }
        .buttonStyle(.card)

        Text("\(String(format: "%.2f", vibrance))")
          .font(.headline)
          .foregroundStyle(.primary)
          .padding(.horizontal, 8)

        Button("+ 0.05") {
          vibrance = min(1, ((vibrance + 0.05) * 20).rounded() / 20)
          setHint(title: "Vibrance", description: "Смешивание цвета вторичного текста к белому: \(String(format: "%.2f", vibrance)).")
        }
        .buttonStyle(.card)
      }
    }
  }

  private var resetSection: some View {
    controlSection("ДЕФОЛТЫ") {
      Button("Сбросить к значениям по умолчанию") {
        let defaults = TVPageBannerChrome.current
        logoPlacement = defaults.logoPlacement
        alignment = defaults.alignment
        showsPoster = defaults.showsPoster
        blend = defaults.blend
        vibrance = Double(defaults.textVibrance)
        scrimChoice = .edgesBlack
        sampleID = TVPageBannerSamples.primaryID
        hasLogo = true
        hasBackdrop = true
        hasPoster = true
        setHint(title: "Сброс", description: "Все параметры возвращены к исходным значениям кода приложения.")
      }
      .buttonStyle(.card)
    }
  }

  // MARK: - Helpers

  @ViewBuilder
  private func controlSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      content()
    }
  }

  private func setHint(title: String, description: String) {
    activeHintTitle = title
    activeHintDescription = description
  }

  private func setCatalogHint() {
    setHint(
      title: "Каталог ID: #\(sampleID)",
      description: "Загрузка арта из каталога staticpop: https://m.staticpop.net/poster/item/wide/\(sampleID).jpg"
    )
  }

  private func applyPreset(_ preset: BannerLabPreset) {
    switch preset {
    case .primaryFull:
      sampleID = TVPageBannerSamples.primaryID
      hasLogo = true
      hasBackdrop = true
      hasPoster = true
      showsPoster = true
    case .typographyOnly:
      sampleID = TVPageBannerSamples.primaryID
      hasLogo = false
      hasBackdrop = true
      hasPoster = true
      showsPoster = true
    case .noPoster:
      sampleID = TVPageBannerSamples.primaryID
      hasLogo = true
      hasBackdrop = true
      hasPoster = false
      showsPoster = false
    case .noBackdrop:
      sampleID = TVPageBannerSamples.primaryID
      hasLogo = true
      hasBackdrop = false
      hasPoster = true
      showsPoster = true
    case .catalog125268:
      sampleID = 125268
      hasLogo = false
      hasBackdrop = true
      hasPoster = true
      showsPoster = true
    case .catalog125260:
      sampleID = 125260
      hasLogo = false
      hasBackdrop = true
      hasPoster = true
      showsPoster = true
    }
  }

  private func isCurrentPreset(_ preset: BannerLabPreset) -> Bool {
    switch preset {
    case .primaryFull:
      return sampleID == TVPageBannerSamples.primaryID && hasLogo && hasBackdrop && hasPoster && showsPoster
    case .typographyOnly:
      return sampleID == TVPageBannerSamples.primaryID && !hasLogo && hasBackdrop && hasPoster && showsPoster
    case .noPoster:
      return sampleID == TVPageBannerSamples.primaryID && !showsPoster
    case .noBackdrop:
      return sampleID == TVPageBannerSamples.primaryID && !hasBackdrop && hasPoster
    case .catalog125268:
      return sampleID == 125268
    case .catalog125260:
      return sampleID == 125260
    }
  }
}
#endif

