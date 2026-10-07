// swift-tools-version: 6.0
// PROTOTYPE, throw away. Answers ticket 06 "What should the menu bar title and popover look like?"
import PackageDescription

let package = Package(
    name: "MenubarPopoverPrototype",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "MenubarPopoverPrototype")]
)
