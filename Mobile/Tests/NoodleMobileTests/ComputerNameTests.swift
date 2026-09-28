import HubLink
@testable import NoodleMobile
import Testing

/// A new computer's name follows the chosen kind until the user types their own.
struct ComputerNameTests {
    let templates = [LinkComputerTemplate(id: "desktop", name: "Desktop", description: "", symbol: "desktopcomputer"),
                     LinkComputerTemplate(id: "shell", name: "Shell", description: "", symbol: "terminal")]

    @Test func defaultNameFollowsKind() {
        #expect(templates.renamed("", from: "", to: "desktop") == "Desktop")
        #expect(templates.renamed("Desktop", from: "desktop", to: "shell") == "Shell")
        #expect(templates.renamed("Shell", from: "shell", to: "desktop") == "Desktop")
    }

    @Test func typedNameStays() {
        #expect(templates.renamed("Build Box", from: "desktop", to: "shell") == "Build Box")
        #expect(templates.renamed("Desk", from: "desktop", to: "shell") == "Desk")
    }
}
