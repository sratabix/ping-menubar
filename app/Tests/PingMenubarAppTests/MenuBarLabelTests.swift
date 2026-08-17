import AppKit
import Foundation
import TestKit

@testable import PingMenubarApp

final class MenuBarLabelTests: TestCase {
    private let everyState: [PingState] = [
        .waiting, .ok(0.0005), .ok(0.001), .ok(0.014), .ok(0.099),
        .slow(0.148), .slow(0.999), .slow(1.5), .slow(30), .dns, .offline,
    ]

    func testEveryStateRendersAtTheSameWidth() {
        let widths = Set(everyState.map { MenuBarLabel.image(for: $0).size.width })
        expectEqual(widths.count, 1, "the menubar item must never change width")
    }

    func testEveryStateRendersAtTheSameHeight() {
        let heights = Set(everyState.map { MenuBarLabel.image(for: $0).size.height })
        expectEqual(heights, [MenuBarLabel.height])
    }

    func testEveryStateFitsTheReservedWidth() {
        let reserved = MenuBarLabel.width(of: MenuBarLabel.widestText, showDot: true)
        for state in everyState {
            expectEqual(
                MenuBarLabel.width(of: MenuBarLabel.text(for: state), showDot: true),
                reserved,
                "\(MenuBarLabel.text(for: state)) must fit without widening the item")
        }
    }

    func testWidthReservesRoomForThreeDigits() {
        expectEqual(
            MenuBarLabel.width(of: "9 ms", showDot: true),
            MenuBarLabel.width(of: MenuBarLabel.widestText, showDot: true))
    }

    func testAnUnexpectedlyWideStringStillGetsItsSpace() {
        expectGreaterThan(
            MenuBarLabel.width(of: "8888888 ms", showDot: true),
            MenuBarLabel.width(of: MenuBarLabel.widestText, showDot: true))
    }

    func testDroppingTheDotShrinksTheCanvas() {
        let withDot = MenuBarLabel.width(of: "14 ms", showDot: true)
        let without = MenuBarLabel.width(of: "14 ms", showDot: false)
        expectLessThan(without, withDot)
        expectEqual(withDot - without, MenuBarLabel.dotDiameter + MenuBarLabel.dotGap)
    }

    func testWidthWithoutTheDotIsAlsoConstant() {
        let widths = Set(everyState.map { MenuBarLabel.image(for: $0, showDot: false).size.width })
        expectEqual(widths.count, 1)
    }

    func testMillisecondFormatting() {
        expectEqual(MenuBarLabel.milliseconds(0.0142), "14 ms")
        expectEqual(MenuBarLabel.milliseconds(0.0005), "<1 ms")
        expectEqual(MenuBarLabel.milliseconds(0.0), "<1 ms")
        expectEqual(MenuBarLabel.milliseconds(0.001), "1 ms")
        expectEqual(MenuBarLabel.milliseconds(0.9994), "999 ms")
        expectEqual(MenuBarLabel.milliseconds(1.0), "1.0 s")
        expectEqual(MenuBarLabel.milliseconds(1.234), "1.2 s")
        expectEqual(MenuBarLabel.milliseconds(2.5), "2.5 s")
    }

    func testTheSecondsBoundaryDoesNotPrint1000ms() {
        expectEqual(MenuBarLabel.milliseconds(0.9996), "1.0 s")
    }

    func testStateGlyphs() {
        expectEqual(MenuBarLabel.text(for: .dns), "DNS")
        expectEqual(MenuBarLabel.text(for: .offline), "---")
        expectEqual(MenuBarLabel.text(for: .waiting), "···")
        expectEqual(MenuBarLabel.text(for: .ok(0.014)), "14 ms")
        expectEqual(MenuBarLabel.text(for: .slow(0.148)), "148 ms")
    }

    func testColoursDistinguishEveryState() {
        let colours = [PingState.ok(0.01), .slow(0.5), .dns, .offline].map { MenuBarLabel.colour(for: $0) }
        expectEqual(Set(colours.map(\.description)).count, 4)
    }

    func testWaitingIsNotColouredLikeAFault() {
        expectNotEqual(
            MenuBarLabel.colour(for: .waiting).description,
            MenuBarLabel.colour(for: .offline).description)
    }

    func testTextIsBakedAgainstTheGivenAppearance() {
        let light = MenuBarLabel.image(for: .ok(0.014), appearance: NSAppearance(named: .aqua))
        let dark = MenuBarLabel.image(for: .ok(0.014), appearance: NSAppearance(named: .darkAqua))
        expectEqual(light.size, dark.size)
        expectNotEqual(
            light.tiffRepresentation, dark.tiffRepresentation,
            "the label must follow the menubar's appearance, not draw one colour for both")
    }

    func testEveryStateCarriesAnAccessibilityDescription() {
        for state in everyState {
            let image = MenuBarLabel.image(for: state)
            expectFalse(image.accessibilityDescription?.isEmpty ?? true)
        }
    }

    func testTheAccessibilityDescriptionNamesTheFault() {
        expectEqual(MenuBarLabel.accessibilityDescription(for: .dns), "DNS unreachable")
        expectEqual(MenuBarLabel.accessibilityDescription(for: .offline), "no connection")
        expectEqual(MenuBarLabel.accessibilityDescription(for: .ok(0.014)), "ping 14 ms")
        expectEqual(MenuBarLabel.accessibilityDescription(for: .slow(0.5)), "ping 500 ms, slow")
    }

    func testTheImageHasRealPixels() {
        let image = MenuBarLabel.image(for: .ok(0.014))
        expectGreaterThan(image.size.width, 0)
        expectNotNil(image.tiffRepresentation)
    }
}
