import CoreGraphics
@testable import NoodleMobile
import Testing

@Suite struct MessageActionsTests {
    /// An iPhone's screen inside its safe area.
    private let area = CGRect(x: 0, y: 60, width: 390, height: 730)

    @Test func aMessageInTheMiddleStaysWhereItWas() {
        let message = CGRect(x: 16, y: 300, width: 250, height: 80)
        let layout = MessageActions.layout(message: message, yours: false, menuHeight: 52, in: area)
        #expect(layout.bubble == message)
        // The reactions are wider than the message, so they keep to the screen's margin.
        #expect(layout.bar.maxY < message.minY && layout.bar.minX == area.minX + 12)
        #expect(layout.menu.minY > message.maxY && layout.menu.minX == message.minX)
    }

    @Test func yourMessageLinesItsReactionsAndActionsUpOnTheRight() {
        let message = CGRect(x: 200, y: 300, width: 174, height: 44)
        let layout = MessageActions.layout(message: message, yours: true, menuHeight: 52, in: area)
        #expect(layout.menu.maxX == message.maxX)
        #expect(layout.bar.maxX <= area.maxX - 12 && layout.bar.minX >= area.minX + 12)
    }

    @Test func aMessageNearAnEdgeMovesSoTheReactionsAndActionsFit() {
        let top = MessageActions.layout(message: CGRect(x: 16, y: 70, width: 250, height: 44), yours: false, menuHeight: 52, in: area)
        #expect(top.bar.minY >= area.minY && top.bubble.minY > 70)
        let bottom = MessageActions.layout(message: CGRect(x: 16, y: 760, width: 250, height: 44), yours: false, menuHeight: 52, in: area)
        #expect(bottom.menu.maxY <= area.maxY && bottom.bubble.minY < 760)
    }

    @Test func aMessageTallerThanTheScreenShowsItsStartBetweenTheOthers() {
        let layout = MessageActions.layout(message: CGRect(x: 16, y: -400, width: 300, height: 2_000), yours: false, menuHeight: 52, in: area)
        #expect(layout.bar.minY >= area.minY && layout.menu.maxY <= area.maxY)
        #expect(layout.bubble.height < 2_000)
    }
}
