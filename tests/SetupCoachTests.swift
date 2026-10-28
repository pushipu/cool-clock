import AppKit

@main struct SetupCoachTests {
    static func main() {
        let size = NSSize(width: 420, height: 620)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let right = SetupCoach.panelFrame(settingsFrame: NSRect(x: 100, y: 100, width: 600, height: 600), visibleFrame: screen, panelSize: size)
        precondition(right.minX == 712, "Place beside Settings on the right when there is room")
        let left = SetupCoach.panelFrame(settingsFrame: NSRect(x: 700, y: 100, width: 600, height: 600), visibleFrame: screen, panelSize: size)
        precondition(left.minX == 268, "Use the left side when the right side is occupied")
        let laptop = NSRect(x: 0, y: 0, width: 1372, height: 662)
        let settings = NSRect(x: 28, y: 25, width: 882, height: 592)
        let clockPopover = NSRect(x: 580, y: 250, width: 650, height: 180)
        let besidePopover = SetupCoach.panelFrame(settingsFrame: settings, visibleFrame: laptop, panelSize: size, avoiding: [clockPopover])
        precondition(!besidePopover.intersects(clockPopover), "Leave the clock popover and its Never menu unobstructed")
        precondition(laptop.contains(besidePopover))
        for visible in [screen, NSRect(x: -1920, y: 0, width: 1920, height: 1080),
                        NSRect(x: 0, y: 1080, width: 1920, height: 1080),
                        NSRect(x: 0, y: 0, width: 340, height: 600)] {
            for settings in [NSRect?.none, NSRect(x: visible.midX - 400, y: visible.maxY - 700, width: 800, height: 600)] {
                for requested in [size, NSSize(width: 3000, height: 3000)] {
                    let frame = SetupCoach.panelFrame(settingsFrame: settings, visibleFrame: visible, panelSize: requested)
                    precondition(visible.contains(frame), "Keep coach visible on small or displaced displays")
                }
            }
        }
        print("PASS: coach placement beside Settings, small displays and secondary-display coordinates")
    }
}
