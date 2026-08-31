import AppKit

@MainActor
enum MainMenu {
    static func install(target: AnyObject) {
        let menu = NSMenu()
        menu.addItem(appMenu(target: target))
        menu.addItem(fileMenu(target: target))
        menu.addItem(editMenu())
        let window = windowMenu()
        menu.addItem(window)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = window.submenu
    }

    private static func appMenu(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(
            withTitle: "About Tenuo",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())

        add(
            to: menu, title: "Settings…", key: ",", target: target,
            action: #selector(AppDelegate.menuOpenSettings(_:)))
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Hide Tenuo",
            action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit Tenuo",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    private static func fileMenu(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "File")

        add(
            to: menu, title: "New Profile", key: "n", target: target,
            action: #selector(AppDelegate.menuNewProfile(_:)))

        let presets = NSMenuItem(title: "New from Preset", action: nil, keyEquivalent: "")
        let presetMenu = NSMenu(title: "New from Preset")
        for (index, preset) in Presets.all.enumerated() {
            let entry = NSMenuItem(
                title: preset.name,
                action: #selector(AppDelegate.menuNewFromPreset(_:)),
                keyEquivalent: "")
            entry.target = target
            entry.tag = index
            presetMenu.addItem(entry)
        }
        presets.submenu = presetMenu
        menu.addItem(presets)
        menu.addItem(.separator())

        let importItem = add(
            to: menu, title: "Import Profile…", key: "i", target: target,
            action: #selector(AppDelegate.menuImportProfile(_:)))
        importItem.keyEquivalentModifierMask = [.command, .shift]
        let exportItem = add(
            to: menu, title: "Export Profile…", key: "e", target: target,
            action: #selector(AppDelegate.menuExportProfile(_:)))
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        item.submenu = menu
        return item
    }

    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(
            withTitle: "Redo", action: Selector(("redo:")),
            keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())

        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        item.submenu = menu
        return item
    }

    private static func windowMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Window")

        menu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(
        to menu: NSMenu,
        title: String,
        key: String,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
