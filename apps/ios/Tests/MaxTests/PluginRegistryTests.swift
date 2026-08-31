import XCTest
import SwiftUI
@testable import Max

@MainActor
final class PluginRegistryTests: XCTestCase {
  
  override func setUp() {
    super.setUp()
    // Reset registry preferences before each test
    UserDefaults.standard.removeObject(forKey: "app.max.plugins.installedPluginIds")
    UserDefaults.standard.removeObject(forKey: "app.max.plugins.activeFeaturePluginIds")
    UserDefaults.standard.removeObject(forKey: "app.max.plugins.activeVisualPluginId")
    UserDefaults.standard.removeObject(forKey: "app.max.plugins.acceptedPermissions")
  }

  func testPluginRegistrationAndDiscovery() {
    let chromatic = ChromaticPlugin()
    let winter = WinterIsComingPlugin()
    let halloween = HalloweenPlugin()
    
    let store = PluginStore.shared
    store.registerBuiltInPlugins([chromatic, winter, halloween])
    
    XCTAssertEqual(store.availablePlugins.count, 3)
    XCTAssertTrue(store.availablePlugins.contains(where: { $0.manifest.id == "com.max.plugin.chromatic" }))
    XCTAssertTrue(store.availablePlugins.contains(where: { $0.manifest.id == "com.max.plugin.winter-is-coming" }))
    XCTAssertTrue(store.availablePlugins.contains(where: { $0.manifest.id == "com.max.plugin.halloween" }))
  }

  func testPluginInstallLifecycle() async {
    let chromatic = ChromaticPlugin()
    let store = PluginStore.shared
    store.registerBuiltInPlugins([chromatic])
    
    XCTAssertFalse(store.installedInstalledIdsContains(chromatic.manifest.id))
    
    await store.install(pluginId: chromatic.manifest.id)
    
    XCTAssertTrue(store.installedInstalledIdsContains(chromatic.manifest.id))
    XCTAssertEqual(store.pluginStates[chromatic.manifest.id], .installed)
  }

  func testVisualPluginExclusivity() async {
    let chromatic = ChromaticPlugin()
    let winter = WinterIsComingPlugin()
    let store = PluginStore.shared
    store.registerBuiltInPlugins([chromatic, winter])
    
    await store.install(pluginId: chromatic.manifest.id)
    await store.install(pluginId: winter.manifest.id)
    
    store.activateVisualPlugin(chromatic.manifest.id)
    XCTAssertEqual(store.activeVisualPluginId, chromatic.manifest.id)
    
    store.activateVisualPlugin(winter.manifest.id)
    XCTAssertEqual(store.activeVisualPluginId, winter.manifest.id)
    XCTAssertEqual(store.pluginStates[chromatic.manifest.id], .installed) // deactivated
    XCTAssertEqual(store.pluginStates[winter.manifest.id], .active)
  }

  func testSafeModeDeactivatesAll() async {
    let chromatic = ChromaticPlugin()
    let store = PluginStore.shared
    store.registerBuiltInPlugins([chromatic])
    
    await store.install(pluginId: chromatic.manifest.id)
    store.activateVisualPlugin(chromatic.manifest.id)
    
    XCTAssertEqual(store.activeVisualPluginId, chromatic.manifest.id)
    
    store.enterSafeMode()
    
    XCTAssertNil(store.activeVisualPluginId)
    XCTAssertEqual(store.activeFeaturePluginIds.count, 0)
  }
}

// Helper extension to keep tests clean without accessing non-Sendable / MainActor properties incorrectly
extension PluginStore {
  func installedInstalledIdsContains(_ id: String) -> Bool {
    return self.installedPluginIds.contains(id)
  }
}
