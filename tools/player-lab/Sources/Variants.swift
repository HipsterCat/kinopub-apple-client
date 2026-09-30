import UIKit

/// Who touches a piece of `AVPlayerViewController` API today.
enum Use: String {
  case ours = "● USED"        // the shipping app sets/reads it
  case flagged = "◐ FLAG"     // used, behind a feature flag
  case unused = "○ —"         // available on tvOS, the app leaves the system default
}

/// One knob. `options[0]` is what the app does today (or the system default where the app
/// does nothing), so a fresh lab reproduces the app.
struct Axis {
  let id: String
  let title: String
  let options: [String]
  let use: Use
  /// Where in the app it lives, or why it is unused.
  let whereUsed: String
  let note: String
}

enum Axes {
  static let all: [Axis] = [
    // MARK: Info tab
    Axis(id: "infoActions", title: "infoViewActions  (Info tab buttons)",
         options: ["Next Episode + Go to Show  (app, new)", "System default only (From Beginning)",
                   "From Beginning + Next Episode", "From Beginning + Go to Show",
                   "Next Episode only", "From Beginning + Next + Go to  (3 — cap test)"],
         use: .ours, whereUsed: "PlayerManager.rebuildInfoViewActions",
         note: "tvOS shows 2 buttons at most (header: “up to 2”); the third is dropped."),
    Axis(id: "infoTab", title: "customInfoViewControllers  (extra Info tab)",
         options: ["Off", "“Up Next” tab — wide cards (Continue Watching cell)", "“Up Next” tab — poster cards (TVPosterView)", "“Up Next” tab — wide cards + badge and progress"],
         use: .unused, whereUsed: "not used — ROADMAP stage 7",
         note: "Apple's TV app puts next episodes in another tab (Up Next / Continue Watching)."),
    // MARK: During playback
    Axis(id: "contextual", title: "contextualActions  (buttons over the picture)",
         options: ["Off", "Next Episode in the last 60 s", "Skip Intro (5–20 s)", "Both"],
         use: .unused, whereUsed: "not used — ROADMAP: skip data, Up Next",
         note: "kino.pub's own app keeps Next Episode as the secondary button."),
    Axis(id: "proposal", title: "AVPlayerItem.nextContentProposal  (Up Next panel)",
         options: ["At credits, 10 s auto-accept  (app)", "At credits, manual", "Off"],
         use: .ours, whereUsed: "PlayerManager.installNextEpisodeProposal + delegate didAccept/didReject",
         note: "The lab puts the credits 15 s before the end."),
    Axis(id: "menus", title: "transportBarCustomMenuItems",
         options: ["Off", "“Episodes” menu"],
         use: .flagged, whereUsed: "PlayerManager.rebuildTransportBarMenus (dual subtitles, tvOSSidecarSubtitles)",
         note: "Off in the shipping build: the stock Audio / Subtitles menus are used."),
    Axis(id: "overlay", title: "customOverlayViewController",
         options: ["Off", "Badge in the corner"],
         use: .unused, whereUsed: "not used — ROADMAP: subtitle overlay inside the controller", note: ""),
    Axis(id: "chapters", title: "AVPlayerItem.navigationMarkerGroups  (chapters)",
         options: ["Off", "3 chapters"],
         use: .unused, whereUsed: "not used — ROADMAP: chapters once a marker source exists", note: ""),
    // MARK: Metadata
    Axis(id: "meta", title: "externalMetadata  (what is stamped)",
         options: ["All fields  (app)", "No genre", "No date", "No artwork", "Title only"],
         use: .ours, whereUsed: "PlayerInfo.metadataItems() + PlayerManager.configureExternalMetadata", note: ""),
    Axis(id: "date", title: "creationDate value shape",
         options: ["NSDate at noon UTC  (fixed)", "String “2025”  (old bug → 2026)", "String “2025-01-01”  (old bug → 12169)",
                   "String with time  (renders year)", "NSDate at midnight UTC  (2024 west of UTC)"],
         use: .ours, whereUsed: "PlayerInfo.metadataItems()", note: "Simulator time zone matters for the last one."),
    // MARK: Controller flags
    Axis(id: "speeds", title: "speeds",
         options: ["System default  (app)", "None ([])", "0.5 / 1 / 1.25 / 1.5 / 2"],
         use: .ours, whereUsed: "PlayerView.TVVideoPlayer.makeUIViewController", note: ""),
    Axis(id: "pip", title: "allowsPictureInPicturePlayback", options: ["On  (app)", "Off"],
         use: .ours, whereUsed: "PlayerView.TVVideoPlayer", note: ""),
    Axis(id: "subLangs", title: "allowedSubtitleOptionLanguages", options: ["nil  (system)", "[]  (hides system picker)"],
         use: .flagged, whereUsed: "PlayerManager.hideSystemSubtitlePicker (sidecar flag)", note: ""),
    Axis(id: "controls", title: "showsPlaybackControls", options: ["On", "Off"],
         use: .unused, whereUsed: "not used", note: "Off hides the whole transport UI."),
    Axis(id: "linear", title: "requiresLinearPlayback", options: ["Off", "On"],
         use: .unused, whereUsed: "not used", note: "On blocks scrubbing/skipping."),
    Axis(id: "bar", title: "playbackControlsIncludeTransportBar", options: ["On", "Off"],
         use: .unused, whereUsed: "not used", note: ""),
    Axis(id: "infoViews", title: "playbackControlsIncludeInfoViews", options: ["On", "Off"],
         use: .unused, whereUsed: "not used", note: "Off removes the Info tab."),
    Axis(id: "titleView", title: "transportBarIncludesTitleView", options: ["On", "Off"],
         use: .unused, whereUsed: "not used", note: ""),
    Axis(id: "skipping", title: "skippingBehavior", options: ["Default", "Skip item (skip buttons → delegate)"],
         use: .unused, whereUsed: "not used", note: "Lab: skip-next plays the next episode."),
    Axis(id: "fullSubs", title: "requiresFullSubtitles", options: ["Off", "On"],
         use: .unused, whereUsed: "not used", note: ""),
    Axis(id: "criteria", title: "appliesPreferredDisplayCriteriaAutomatically", options: ["On", "Off"],
         use: .unused, whereUsed: "not used", note: "HDR / frame-rate matching."),
    Axis(id: "start", title: "Start position", options: ["Beginning", "15 s before the credits"],
         use: .unused, whereUsed: "lab only", note: "So Up Next can be seen without waiting."),
  ]

  static func axis(_ id: String) -> Axis { all.first { $0.id == id }! }
}

/// Current choice per axis, and the presets that mimic the players we are comparing.
final class LabConfig {
  static let shared = LabConfig()
  private(set) var index: [String: Int] = [:]

  func value(_ id: String) -> Int { index[id] ?? 0 }
  func label(_ id: String) -> String { Axes.axis(id).options[value(id)] }
  func cycle(_ id: String) { index[id] = (value(id) + 1) % Axes.axis(id).options.count }

  struct Preset { let name: String; let note: String; let set: [String: Int] }

  static let presets: [Preset] = [
    Preset(name: "Ours today", note: "What the app ships (Info buttons new, uncommitted).", set: [:]),
    Preset(name: "Apple TV app style", note: "From Beginning + Go to; next episodes in an “Up Next” tab; Up Next panel at the credits.",
           set: ["infoActions": 3, "infoTab": 1, "proposal": 0]),
    Preset(name: "kino.pub style", note: "From Beginning in Info; Next Episode as the secondary button over the picture.",
           set: ["infoActions": 1, "contextual": 1, "proposal": 1, "start": 1]),
    Preset(name: "Everything on", note: "Every optional surface at once.",
           set: ["infoActions": 5, "infoTab": 1, "contextual": 3, "menus": 1, "overlay": 1, "chapters": 1]),
  ]

  func apply(_ p: Preset) { index = p.set }
  func replace(with set: [String: Int]) { index = set }
}

