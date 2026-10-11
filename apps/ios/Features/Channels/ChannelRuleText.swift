import Foundation

/// Turning a rule into words, and the facets the builder offers.
///
/// A rule the reader cannot restate is a rule they cannot fix when the channel
/// comes back empty, so every condition has a phrase — and the builder offers
/// those phrases rather than a pile of switches.
enum ChannelRuleText {
  /// m:ss, the same shape the rest of the app uses for a clip length.
  static func duration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  /// The rule in a sentence.
  static func describe(_ rule: ChannelRule) -> String {
    var parts: [String] = []

    if rule.unratedOnly == true {
      parts.append(String(localized: "channels.rule.unrated"))
    } else if let low = rule.minRating, let high = rule.maxRating {
      parts.append(String(localized: "channels.rule.between_ratings \(low) \(high)"))
    } else if let low = rule.minRating {
      parts.append(String(localized: "channels.rule.min_rating \(low)"))
    } else if let high = rule.maxRating {
      parts.append(String(localized: "channels.rule.max_rating \(high)"))
    }

    if let low = rule.minSeconds, let high = rule.maxSeconds {
      parts.append(String(localized: "channels.rule.between_lengths \(duration(low)) \(duration(high))"))
    } else if let high = rule.maxSeconds {
      parts.append(String(localized: "channels.rule.shorter_than \(duration(high))"))
    } else if let low = rule.minSeconds {
      parts.append(String(localized: "channels.rule.longer_than \(duration(low))"))
    }

    if rule.unwatchedOnly == true {
      parts.append(String(localized: "channels.rule.unwatched"))
    } else if rule.watchedOnly == true {
      parts.append(String(localized: "channels.rule.watched"))
    }

    if rule.favourite == true {
      parts.append(String(localized: "channels.rule.favourites"))
    } else if rule.favourite == false {
      parts.append(String(localized: "channels.rule.not_favourites"))
    }

    if rule.uncollected == true {
      parts.append(String(localized: "channels.rule.uncollected"))
    }
    if let days = rule.addedWithinDays {
      parts.append(String(localized: "channels.rule.added_within \(days)"))
    }

    guard !parts.isEmpty else { return String(localized: "channels.rule.everything") }
    return parts.joined(separator: String(localized: "channels.rule.join"))
  }
}

// MARK: - Facets

/// One FACET of a rule — rating, length, seen, and so on — offered as a list of
/// whole meanings rather than a pile of separate switches.
///
/// This is what makes a contradictory rule unwritable. "Rated 8 or more" and
/// "never rated" are both good conditions, and a rule holding both matches
/// nothing forever while still calling itself a channel. So they are not two
/// controls you might leave both on: they are two answers to one question, and
/// answering it again replaces the answer. The server refuses a contradiction
/// as well — the interface simply never has to send one.
struct ChannelFacetOption: Identifiable, Hashable {
  let id: String
  let label: String
  /// Applied to the whole facet, so choosing one answer clears the others.
  let apply: @Sendable (inout ChannelRule) -> Void

  static func == (lhs: ChannelFacetOption, rhs: ChannelFacetOption) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ChannelFacet: Identifiable {
  let id: String
  let label: String
  let symbol: String
  let options: [ChannelFacetOption]
  /// Which option the current rule reads as.
  let selection: (ChannelRule) -> String

  func current(_ rule: ChannelRule) -> ChannelFacetOption {
    let id = selection(rule)
    return options.first { $0.id == id } ?? options[0]
  }
}

enum ChannelFacets {
  static func all(collections: [(id: String, title: String)]) -> [ChannelFacet] {
    [rating, length, seen, favourite, filing(collections: collections), added]
  }

  private static func clearRating(_ rule: inout ChannelRule) {
    rule.minRating = nil
    rule.maxRating = nil
    rule.unratedOnly = nil
  }

  private static func clearLength(_ rule: inout ChannelRule) {
    rule.minSeconds = nil
    rule.maxSeconds = nil
  }

  private static func clearSeen(_ rule: inout ChannelRule) {
    rule.unwatchedOnly = nil
    rule.watchedOnly = nil
  }

  private static func clearFiling(_ rule: inout ChannelRule) {
    rule.collectionId = nil
    rule.uncollected = nil
  }

  private static var rating: ChannelFacet {
    var options: [ChannelFacetOption] = [
      ChannelFacetOption(id: "any", label: String(localized: "channels.any")) { clearRating(&$0) }
    ]
    for score in [9, 8, 7, 6] {
      options.append(
        ChannelFacetOption(id: "min:\(score)", label: String(localized: "channels.rule.min_rating \(score)")) {
          clearRating(&$0)
          $0.minRating = score
        }
      )
    }
    options.append(
      ChannelFacetOption(id: "between:6:8", label: String(localized: "channels.rule.between_ratings \(6) \(8)")) {
        clearRating(&$0)
        $0.minRating = 6
        $0.maxRating = 8
      }
    )
    options.append(
      ChannelFacetOption(id: "max:5", label: String(localized: "channels.rule.max_rating \(5)")) {
        clearRating(&$0)
        $0.maxRating = 5
      }
    )
    options.append(
      ChannelFacetOption(id: "unrated", label: String(localized: "channels.rule.unrated")) {
        clearRating(&$0)
        $0.unratedOnly = true
      }
    )
    return ChannelFacet(
      id: "rating",
      label: String(localized: "channels.facet.rating"),
      symbol: "star.fill",
      options: options
    ) { rule in
      if rule.unratedOnly == true { return "unrated" }
      if let low = rule.minRating, let high = rule.maxRating { return "between:\(low):\(high)" }
      if let low = rule.minRating { return "min:\(low)" }
      if let high = rule.maxRating { return "max:\(high)" }
      return "any"
    }
  }

  private static var length: ChannelFacet {
    var options: [ChannelFacetOption] = [
      ChannelFacetOption(id: "any", label: String(localized: "channels.any")) { clearLength(&$0) }
    ]
    for seconds in [30.0, 60.0, 180.0] {
      options.append(
        ChannelFacetOption(
          id: "under:\(Int(seconds))",
          label: String(localized: "channels.rule.shorter_than \(ChannelRuleText.duration(seconds))")
        ) {
          clearLength(&$0)
          $0.maxSeconds = seconds
        }
      )
    }
    options.append(
      ChannelFacetOption(
        id: "band:30:120",
        label: String(
          localized: "channels.rule.between_lengths \(ChannelRuleText.duration(30)) \(ChannelRuleText.duration(120))"
        )
      ) {
        clearLength(&$0)
        $0.minSeconds = 30
        $0.maxSeconds = 120
      }
    )
    for seconds in [60.0, 180.0] {
      options.append(
        ChannelFacetOption(
          id: "over:\(Int(seconds))",
          label: String(localized: "channels.rule.longer_than \(ChannelRuleText.duration(seconds))")
        ) {
          clearLength(&$0)
          $0.minSeconds = seconds
        }
      )
    }
    return ChannelFacet(
      id: "length",
      label: String(localized: "channels.facet.length"),
      symbol: "clock",
      options: options
    ) { rule in
      if let low = rule.minSeconds, let high = rule.maxSeconds { return "band:\(Int(low)):\(Int(high))" }
      if let high = rule.maxSeconds { return "under:\(Int(high))" }
      if let low = rule.minSeconds { return "over:\(Int(low))" }
      return "any"
    }
  }

  private static var seen: ChannelFacet {
    ChannelFacet(
      id: "seen",
      label: String(localized: "channels.facet.seen"),
      symbol: "eye",
      options: [
        ChannelFacetOption(id: "any", label: String(localized: "channels.any")) { clearSeen(&$0) },
        ChannelFacetOption(id: "unwatched", label: String(localized: "channels.rule.unwatched")) {
          clearSeen(&$0)
          $0.unwatchedOnly = true
        },
        ChannelFacetOption(id: "watched", label: String(localized: "channels.rule.watched")) {
          clearSeen(&$0)
          $0.watchedOnly = true
        },
      ]
    ) { rule in
      if rule.unwatchedOnly == true { return "unwatched" }
      if rule.watchedOnly == true { return "watched" }
      return "any"
    }
  }

  private static var favourite: ChannelFacet {
    ChannelFacet(
      id: "favourite",
      label: String(localized: "channels.facet.favourite"),
      symbol: "heart",
      options: [
        ChannelFacetOption(id: "any", label: String(localized: "channels.any")) { $0.favourite = nil },
        ChannelFacetOption(id: "yes", label: String(localized: "channels.rule.favourites")) { $0.favourite = true },
        ChannelFacetOption(id: "no", label: String(localized: "channels.rule.not_favourites")) { $0.favourite = false },
      ]
    ) { rule in
      if rule.favourite == true { return "yes" }
      if rule.favourite == false { return "no" }
      return "any"
    }
  }

  private static func filing(collections: [(id: String, title: String)]) -> ChannelFacet {
    var options: [ChannelFacetOption] = [
      ChannelFacetOption(id: "any", label: String(localized: "channels.any")) { clearFiling(&$0) },
      ChannelFacetOption(id: "none", label: String(localized: "channels.rule.uncollected")) {
        clearFiling(&$0)
        $0.uncollected = true
      },
    ]
    for collection in collections {
      let identifier = collection.id
      options.append(
        ChannelFacetOption(
          id: "in:\(identifier)",
          label: String(localized: "channels.rule.in_collection \(collection.title)")
        ) {
          clearFiling(&$0)
          $0.collectionId = identifier
        }
      )
    }
    return ChannelFacet(
      id: "filing",
      label: String(localized: "channels.facet.filing"),
      symbol: "folder",
      options: options
    ) { rule in
      if rule.uncollected == true { return "none" }
      if let collectionId = rule.collectionId { return "in:\(collectionId)" }
      return "any"
    }
  }

  private static var added: ChannelFacet {
    var options: [ChannelFacetOption] = [
      ChannelFacetOption(id: "any", label: String(localized: "channels.any_time")) { $0.addedWithinDays = nil }
    ]
    for days in [7, 30, 90, 365] {
      options.append(
        ChannelFacetOption(id: "days:\(days)", label: String(localized: "channels.rule.added_within \(days)")) {
          $0.addedWithinDays = days
        }
      )
    }
    return ChannelFacet(
      id: "added",
      label: String(localized: "channels.facet.added"),
      symbol: "calendar",
      options: options
    ) { rule in
      if let days = rule.addedWithinDays { return "days:\(days)" }
      return "any"
    }
  }
}
