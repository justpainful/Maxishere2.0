import Foundation

enum PluginState: String, Codable, Sendable, Hashable {
  case available
  case installing
  case installed
  case activating
  case active
  case disabled
  case updating
  case incompatible
  case failed
  case removing

  var localizedDescription: String {
    let key = "plugin.state.\(self.rawValue)"
    return String(localized: LocalizedStringResource(stringLiteral: key))
  }
}


