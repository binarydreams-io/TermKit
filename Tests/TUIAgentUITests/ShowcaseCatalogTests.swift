import Testing

@testable import TUIAgentUI

struct ShowcaseCatalogTests {
    @Test("Default showcase covers the required agent UI inventory")
    func requiredInventory() {
        let catalog = ShowcaseCatalog()

        #expect(catalog.missingRequiredComponents.isEmpty)
        #expect(catalog.coveredComponents == Set(ShowcaseComponent.allCases))
        #expect(catalog.entries.count == 10)
    }

    @Test("Catalog reports missing showcase sections")
    func missingInventory() {
        let catalog = ShowcaseCatalog(entries: [ShowcaseEntry(component: .prompt, title: "Prompt")])

        #expect(catalog.missingRequiredComponents.contains(.commandPalette))
        #expect(catalog.missingRequiredComponents.contains(.sidebar))
        #expect(catalog.missingRequiredComponents.contains(.prompt) == false)
    }
}
