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
  @State private var hasPoster: Bool = false

  @State private var focusState: BannerLabFocusState = .unfocused
  @State private var logoPlacement: TVPageBannerLogoPlacement = TVPageBannerChrome.current.logoPlacement
  @State private var alignment: TVPageBannerContentAlignment = TVPageBannerChrome.current.alignment
  @State private var verticalAlignment: TVPageBannerVerticalAlignment = TVPageBannerChrome.current.verticalAlignment
  @State private var showsPoster: Bool = TVPageBannerChrome.current.showsPoster
  @State private var scrimChoice: BannerLabScrim = .defaultBottom
  @State private var blend: TVPageBannerBlend = TVPageBannerChrome.current.blend
  @State private var vibrance: Double = Double(TVPageBannerChrome.current.textVibrance)
  @State private var vibranceEnabled: Bool = TVPageBannerChrome.current.vibranceEnabled

  @State private var showsRatingVotes: Bool = TVPageBannerChrome.current.showsRatingVotes
  @State private var ratingMaxCount: Int = TVPageBannerChrome.current.ratingMaxCount
  @State private var filterLowTurnout: Bool = TVPageBannerChrome.current.filterLowTurnout
  @State private var filterDominantScore: Bool = TVPageBannerChrome.current.filterDominantScore
  @State private var showsAggregateScore: Bool = TVPageBannerChrome.current.showsAggregateScore
  @State private var aggregateOnly: Bool = TVPageBannerChrome.current.aggregateOnly
  @State private var deduplicateSingleSource: Bool = TVPageBannerChrome.current.deduplicateSingleSourceAggregate
  @State private var customScores: MediaScores? = nil

  @State private var activeHintTitle: String = "Home Banner Lab"
  @State private var activeHintDescription: String = "Интерактивная настройка баннера на главной: размещение логотипа, выравнивание, наложение блендов, градиенты затемнения, яркость текста и переключение тайтлов каталога."

  public init() {}

  public var body: some View {
    HStack(alignment: .top, spacing: 48) {
      // LEFT COLUMN: Pinned live banner + description text (always visible)
      VStack(alignment: .center, spacing: 24) {
        TVPageBannerHost(
          chrome: chrome,
          feature: feature,
          isSimulatedFocused: focusState == .focused
        )
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
          focusSection
          presetsSection
          catalogIDSection
          scoresSection
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
    draft.verticalAlignment = verticalAlignment
    draft.showsPoster = showsPoster
    draft.blend = blend
    draft.textVibrance = CGFloat(vibrance)
    draft.vibranceEnabled = vibranceEnabled
    draft.isFocusedState = (focusState == .focused)
    draft.showsRatingVotes = showsRatingVotes
    draft.ratingMaxCount = ratingMaxCount
    draft.filterLowTurnout = filterLowTurnout
    draft.filterDominantScore = filterDominantScore
    draft.showsAggregateScore = showsAggregateScore
    draft.aggregateOnly = aggregateOnly
    draft.deduplicateSingleSourceAggregate = deduplicateSingleSource
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
      hasPoster: hasPoster,
      scores: customScores
    )
  }

  // MARK: - Right Column Sections

  private var focusSection: some View {
    controlSection("СОСТОЯНИЕ ФОКУСА (FOCUS STATE)") {
      HStack(spacing: 12) {
        ForEach(BannerLabFocusState.allCases) { state in
          Button {
            focusState = state
            setHint(
              title: "Фокус: \(state.label)",
              description: state == .focused
                ? "Симуляция фокуса на карточке: текст описания становится Primary (чистый белый #FFFFFF), цифры оценок остаются белыми."
                : "Карточка вне фокуса: текст описания имеет Secondary оттенок (70% белого)."
            )
          } label: {
            HStack(spacing: 8) {
              if focusState == state { Image(systemName: "checkmark") }
              Text(state.label)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
          }
          .buttonStyle(.card)
        }
      }
    }
  }

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
      VStack(alignment: .leading, spacing: 12) {
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

        HStack(spacing: 12) {
          ForEach(TVPageBannerVerticalAlignment.allCases, id: \.self) { vAlign in
            Button {
              verticalAlignment = vAlign
              setHint(title: "Вертикальное выравнивание: \(vAlign.title)", description: "Позиционирование блока контента по вертикали: \(vAlign.title).")
            } label: {
              HStack(spacing: 8) {
                if verticalAlignment == vAlign { Image(systemName: "checkmark") }
                Text(vAlign.title)
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
            }
            .buttonStyle(.card)
          }
        }
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
      VStack(alignment: .leading, spacing: 12) {
        Button {
          vibranceEnabled.toggle()
          setHint(
            title: "Vibrance (Высветление)",
            description: vibranceEnabled
              ? "Программное высветление включено: вторичный текст смешивается к белому на \(String(format: "%.2f", vibrance))."
              : "Высветление отключено: вторичный текст остается мягким 70% белым без искусственного пересвета."
          )
        } label: {
          HStack(spacing: 8) {
            Image(systemName: vibranceEnabled ? "checkmark.circle.fill" : "circle")
            Text("Высветление (Vibrance): \(vibranceEnabled ? "ВКЛ" : "ВЫКЛ")")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)

        if vibranceEnabled {
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
    }
  }

  private var scoresSection: some View {
    controlSection("РЕЙТИНГИ И ОЦЕНКИ (SCORES)") {
      VStack(alignment: .leading, spacing: 12) {
        Button {
          showsRatingVotes.toggle()
          setHint(
            title: "Количество оценок",
            description: showsRatingVotes
              ? "Показывает число проголосовавших в скобках после оценки: (12K), (4.2K)."
              : "Количество голосов скрыто, отображаются только логотипы и цифры оценок."
          )
        } label: {
          HStack(spacing: 8) {
            Image(systemName: showsRatingVotes ? "checkmark.circle.fill" : "circle")
            Text("Количество голосов `(12K)`: \(showsRatingVotes ? "ВКЛ" : "ВЫКЛ")")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)

        Button {
          ratingMaxCount = (ratingMaxCount == 1 ? 2 : 1)
          setHint(
            title: "Лимит оценок",
            description: "Максимальное количество плашек оценок на баннере: \(ratingMaxCount)."
          )
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "number")
            Text("Лимит оценок в строке: \(ratingMaxCount)")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)

        Button {
          filterLowTurnout.toggle()
          setHint(
            title: "Фильтр шума (< 10 голосов)",
            description: filterLowTurnout
              ? "Включен: если у оценки < 10 голосов при наличии нормальных рейтингов, она отбрасывается."
              : "Отключен: показываются даже оценки с единичными голосами."
          )
        } label: {
          HStack(spacing: 8) {
            Image(systemName: filterLowTurnout ? "checkmark.circle.fill" : "circle")
            Text("Фильтр шума (< 10 голосов): \(filterLowTurnout ? "ВКЛ" : "ВЫКЛ")")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)

        Button {
          filterDominantScore.toggle()
          setHint(
            title: "Фильтр доминанты (> 90%)",
            description: filterDominantScore
              ? "Включен: если один источник дает > 90% голосов (например КП 50K vs IMDb 1K), на баннере остается только он."
              : "Отключен: выводятся обе оценки."
          )
        } label: {
          HStack(spacing: 8) {
            Image(systemName: filterDominantScore ? "checkmark.circle.fill" : "circle")
            Text("Фильтр доминанты (> 90%): \(filterDominantScore ? "ВКЛ" : "ВЫКЛ")")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)

        Button {
          showsAggregateScore.toggle()
          setHint(
            title: "Агрегированная оценка",
            description: showsAggregateScore
              ? "Включена: перед индивидуальными рейтингами показывается единая плашка с общей оценкой."
              : "Отключена: отображаются только оригинальные оценки источников под своими логотипами."
          )
        } label: {
          HStack(spacing: 8) {
            Image(systemName: showsAggregateScore ? "checkmark.circle.fill" : "circle")
            Text("Агрегированная оценка: \(showsAggregateScore ? "ВКЛ" : "ВЫКЛ")")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
        }
        .buttonStyle(.card)

        if showsAggregateScore {
          Button {
            aggregateOnly.toggle()
            setHint(
              title: "Только агрегат",
              description: aggregateOnly
                ? "Отображается только агрегированная оценка без разбивки по источникам (максимально компактно)."
                : "После агрегата следуют плашки источников."
            )
          } label: {
            HStack(spacing: 8) {
              Image(systemName: aggregateOnly ? "checkmark.circle.fill" : "circle")
              Text("Только агрегат (без источников): \(aggregateOnly ? "ВКЛ" : "ВЫКЛ")")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
          }
          .buttonStyle(.card)

          Button {
            deduplicateSingleSource.toggle()
            setHint(
              title: "Дедупликация 1 источника",
              description: deduplicateSingleSource
                ? "Включена: если агрегат равен единственному источнику (например 8.5), у логотипа источника цифра 8.5 не дублируется."
                : "Отключена: цифра будет продублирована дважды подряд."
            )
          } label: {
            HStack(spacing: 8) {
              Image(systemName: deduplicateSingleSource ? "checkmark.circle.fill" : "circle")
              Text("Не дублировать цифру при 1 источнике: \(deduplicateSingleSource ? "ВКЛ" : "ВЫКЛ")")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
          }
          .buttonStyle(.card)
        }
      }
    }
  }

  private var resetSection: some View {
    controlSection("ДЕФОЛТЫ") {
      VStack(alignment: .leading, spacing: 10) {
        Button("Сбросить к новому дефолту (Без постера, 40%)") {
          applyPreset(.currentDefault)
          setHint(title: "Новый дефолт", description: "Все параметры возвращены к новому дефолту: без постера, сбалансированный нижний отступ 22pt, чистое описание.")
        }
        .buttonStyle(.card)

        Button("Пример 2: Восстановить как было (С постером)") {
          applyPreset(.previousFull)
          setHint(title: "Как было", description: "Параметры предыдущей версии: постер 42% справа, отступ 32pt, включенное высветление vibrance 0.65.")
        }
        .buttonStyle(.card)
      }
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
    case .currentDefault:
      sampleID = TVPageBannerSamples.primaryID
      hasLogo = true
      hasBackdrop = true
      hasPoster = false
      showsPoster = false
      alignment = .leading
      verticalAlignment = .bottom
      scrimChoice = .defaultBottom
      blend = .normal
      focusState = .unfocused
      vibranceEnabled = false
      customScores = nil
      showsRatingVotes = false
      ratingMaxCount = 2
      filterLowTurnout = true
      filterDominantScore = true
      showsAggregateScore = false
      aggregateOnly = false
      deduplicateSingleSource = true
    case .previousFull:
      sampleID = TVPageBannerSamples.primaryID
      hasLogo = true
      hasBackdrop = true
      hasPoster = true
      showsPoster = true
      alignment = .leading
      verticalAlignment = .bottom
      scrimChoice = .edgesBlack
      blend = .normal
      focusState = .unfocused
      vibranceEnabled = true
      vibrance = 0.65
      customScores = nil
      showsRatingVotes = true
    case .focusedState:
      focusState = .focused
    case .noisyScores:
      sampleID = TVPageBannerSamples.primaryID
      customScores = MediaScores(imdb: 8.5, imdbVotes: 6, kinopoisk: 8.1, kinopoiskVotes: 4200)
    case .unknownScore:
      sampleID = TVPageBannerSamples.primaryID
      customScores = MediaScores(imdb: 7.9, imdbVotes: 45, kinopoisk: nil, kinopoiskVotes: 2500)
    case .dominantScore:
      sampleID = TVPageBannerSamples.primaryID
      customScores = MediaScores(imdb: 8.0, imdbVotes: 1000, kinopoisk: 8.4, kinopoiskVotes: 50_000)
    case .fallbackSources:
      sampleID = TVPageBannerSamples.primaryID
      customScores = MediaScores(imdb: nil, kinopoisk: nil, tmdb: 7.5, tmdbVotes: 800, kinopubLikes: 135, kinopubDislikes: 15)
    case .kinopub100:
      sampleID = TVPageBannerSamples.primaryID
      customScores = MediaScores(imdb: 8.2, imdbVotes: 5000, kinopubLikes: 100, kinopubDislikes: 0)
    case .aggregateDedup:
      sampleID = TVPageBannerSamples.primaryID
      showsAggregateScore = true
      aggregateOnly = false
      deduplicateSingleSource = true
      customScores = MediaScores(imdb: 8.5, imdbVotes: 38)
    case .typographyOnly:
      sampleID = TVPageBannerSamples.primaryID
      hasLogo = false
      hasBackdrop = true
      hasPoster = false
      showsPoster = false
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
      hasPoster = false
      showsPoster = false
    case .catalog125268:
      sampleID = 125268
      hasLogo = false
      hasBackdrop = true
      hasPoster = false
      showsPoster = false
      customScores = nil
    case .catalog125260:
      sampleID = 125260
      hasLogo = false
      hasBackdrop = true
      hasPoster = false
      showsPoster = false
      customScores = nil
    }
  }

  private func isCurrentPreset(_ preset: BannerLabPreset) -> Bool {
    switch preset {
    case .currentDefault:
      return sampleID == TVPageBannerSamples.primaryID && hasLogo && !showsPoster && focusState == .unfocused && customScores == nil
    case .previousFull:
      return sampleID == TVPageBannerSamples.primaryID && hasLogo && showsPoster
    case .focusedState:
      return focusState == .focused
    case .noisyScores:
      return customScores?.imdbVotes == 6
    case .unknownScore:
      return customScores?.imdbVotes == 45
    case .dominantScore:
      return customScores?.kinopoiskVotes == 50_000
    case .fallbackSources:
      return customScores?.tmdbVotes == 800
    case .kinopub100:
      return customScores?.kinopubLikes == 100 && customScores?.kinopubDislikes == 0
    case .aggregateDedup:
      return showsAggregateScore && customScores?.imdbVotes == 38
    case .typographyOnly:
      return sampleID == TVPageBannerSamples.primaryID && !hasLogo
    case .noPoster:
      return sampleID == TVPageBannerSamples.primaryID && !showsPoster
    case .noBackdrop:
      return sampleID == TVPageBannerSamples.primaryID && !hasBackdrop
    case .catalog125268:
      return sampleID == 125268
    case .catalog125260:
      return sampleID == 125260
    }
  }
}
#endif

