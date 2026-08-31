#!/usr/bin/env python3
"""Generates Tenuo.xcodeproj/project.pbxproj.

The project file is checked in; this script exists so it can be regenerated
deterministically rather than hand-edited, which is where pbxproj corruption
usually comes from. Run it from the repository root:

    python3 scripts/generate_project.py
"""

import os

APP_SOURCES = [
    ("App", "TenuoApp.swift"),
    ("App", "MainMenu.swift"),
    ("App", "TenuoController.swift"),
    ("App", "PermissionWindowController.swift"),
    ("App", "SettingsWindowController.swift"),
    ("Core", "KeyCodes.swift"),
    ("Core", "TriggerKey.swift"),
    ("Core", "KeyCatalog.swift"),
    ("Core", "KeyBinding.swift"),
    ("Core", "Layout.swift"),
    ("Core", "Presets.swift"),
    ("Core", "LayerEngine.swift"),
    ("Core", "KeyboardGeometry.swift"),
    ("Core", "Settings.swift"),
    ("System", "KeyboardMonitor.swift"),
    ("System", "CapsLockRemapper.swift"),
    ("System", "AccessibilityManager.swift"),
    ("System", "LaunchAtLoginManager.swift"),
    ("System", "SystemEventObserver.swift"),
    ("System", "UpdateController.swift"),
    ("UI", "DesignSystem.swift"),
    ("UI", "Controls.swift"),
    ("UI", "GlassStyle.swift"),
    ("UI", "AppModel.swift"),
    ("UI", "MenuBarController.swift"),
    ("UI", "MenuPanelView.swift"),
    ("UI", "SettingsView.swift"),
    ("UI", "LayersPage.swift"),
    ("UI", "SettingsControls.swift"),
    ("UI", "KeyboardLayoutView.swift"),
    ("UI", "LayerList.swift"),
    ("UI", "ProfileSwitcher.swift"),
    ("UI", "CheatSheetController.swift"),
]

CORE_SOURCES = [f for f in APP_SOURCES if f[0] == "Core"]

TEST_SOURCES = [
    ("TenuoTests", "LayerEngineTests.swift"),
    ("TenuoTests", "SettingsTests.swift"),
]

RESOURCES = [
    ("Resources", "Info.plist"),
    ("Resources", "Tenuo.entitlements"),
    ("Resources", "Assets.car"),
    ("Resources", "Tenuo.icns"),
    ("Resources", "TenuoTemplate.png"),
    ("Resources", "TenuoTemplate@2x.png"),
    ("Resources", "TenuoMark.png"),
    ("Resources", "TenuoMark@2x.png"),
]

PACKAGES = [
    {
        "name": "Sparkle",
        "url": "https://github.com/sparkle-project/Sparkle",
        "minimum": "2.6.0",
        "products": ["Sparkle"],
    },
]

XCCONFIG = ("", "Config.xcconfig")

COPIED_RESOURCES = [r for r in RESOURCES
                    if r[1] not in ("Info.plist", "Tenuo.entitlements")]


class IDGen:
    """Deterministic 24-hex-character object identifiers."""

    def __init__(self):
        self.counter = 0
        self.cache = {}

    def __call__(self, key):
        if key not in self.cache:
            self.counter += 1
            self.cache[key] = f"TENUO{self.counter:019X}"
        return self.cache[key]


oid = IDGen()


def pbx(value):
    """Quotes a value if pbxproj cannot take it bare.

    An unquoted pbxproj token may only contain letters, digits, `_`, `.` and
    `/`. A retina asset is named `Foo@2x.png`, and the `@` makes the whole file
    unparseable. Xcode reports only "Unable to read project".
    """
    import re as _re
    return value if _re.fullmatch(r"[A-Za-z0-9_./]+", value) else f'"{value}"'


def file_ref(group, name):
    return oid(f"ref:{group}/{name}")


def build_file(target, group, name):
    return oid(f"bf:{target}:{group}/{name}")


def main():
    lines = []
    add = lines.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")

    add("")
    add("/* Begin PBXBuildFile section */")
    for group, name in APP_SOURCES:
        add(f"\t\t{build_file('app', group, name)} /* {name} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_ref(group, name)} /* {name} */; }};")
    for group, name in TEST_SOURCES + CORE_SOURCES:
        add(f"\t\t{build_file('tests', group, name)} /* {name} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_ref(group, name)} /* {name} */; }};")
    for group, name in COPIED_RESOURCES:
        add(f"\t\t{build_file('res', group, name)} /* {name} in Resources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_ref(group, name)} /* {name} */; }};")
    for package in PACKAGES:
        for product in package["products"]:
            add(f"\t\t{oid(f'bf:pkg:{product}')} /* {product} in Frameworks */ = "
                f"{{isa = PBXBuildFile; productRef = {oid(f'pkgprod:{product}')} /* {product} */; }};")
    add("/* End PBXBuildFile section */")

    add("")
    add("/* Begin PBXFileReference section */")
    for group, name in APP_SOURCES + TEST_SOURCES:
        add(f"\t\t{file_ref(group, name)} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};")
    for group, name in RESOURCES:
        if name.endswith(".plist"):
            kind = "text.plist.xml"
        elif name.endswith(".entitlements"):
            kind = "text.plist.entitlements"
        elif name.endswith(".car"):
            kind = "archive.binhex"
        elif name.endswith(".png"):
            kind = "image.png"
        else:
            kind = "image.icns"
        add(f"\t\t{file_ref(group, name)} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {kind}; path = {pbx(name)}; sourceTree = \"<group>\"; }};")
    add(f"\t\t{file_ref(*XCCONFIG)} /* {XCCONFIG[1]} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = text.xcconfig; path = {XCCONFIG[1]}; sourceTree = \"<group>\"; }};")
    add(f"\t\t{oid('product:app')} /* Tenuo.app */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.application; includeInIndex = 0; path = Tenuo.app; "
        "sourceTree = BUILT_PRODUCTS_DIR; };")
    add(f"\t\t{oid('product:tests')} /* TenuoTests.xctest */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TenuoTests.xctest; "
        "sourceTree = BUILT_PRODUCTS_DIR; };")
    add("/* End PBXFileReference section */")

    add("")
    add("/* Begin PBXFrameworksBuildPhase section */")
    for target in ("app", "tests"):
        add(f"\t\t{oid(f'frameworks:{target}')} /* Frameworks */ = {{")
        add("\t\t\tisa = PBXFrameworksBuildPhase;")
        add("\t\t\tbuildActionMask = 2147483647;")
        add("\t\t\tfiles = (")
        if target == "app":
            for package in PACKAGES:
                for product in package["products"]:
                    add(f"\t\t\t\t{oid(f'bf:pkg:{product}')} /* {product} in Frameworks */,")
        add("\t\t\t);")
        add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    add("")
    add("/* Begin PBXGroup section */")

    def group(key, name, children, path=None):
        add(f"\t\t{oid(key)} /* {name} */ = {{")
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        for child_id, child_name in children:
            add(f"\t\t\t\t{child_id} /* {child_name} */,")
        add("\t\t\t);")
        if path:
            add(f"\t\t\tpath = {path};")
        elif name:
            add(f"\t\t\tname = {name};")
        add("\t\t\tsourceTree = \"<group>\";")
        add("\t\t};")

    for folder in ("App", "Core", "System", "UI"):
        group(f"group:{folder}", folder,
              [(file_ref(g, n), n) for g, n in APP_SOURCES if g == folder],
              path=folder)

    group("group:Resources", "Resources",
          [(file_ref(g, n), n) for g, n in RESOURCES], path="Resources")

    group("group:Tenuo", "Tenuo", [
        (oid("group:App"), "App"),
        (oid("group:Core"), "Core"),
        (oid("group:System"), "System"),
        (oid("group:UI"), "UI"),
        (oid("group:Resources"), "Resources"),
    ], path="Tenuo")

    group("group:TenuoTests", "TenuoTests",
          [(file_ref(g, n), n) for g, n in TEST_SOURCES], path="TenuoTests")

    group("group:Products", "Products", [
        (oid("product:app"), "Tenuo.app"),
        (oid("product:tests"), "TenuoTests.xctest"),
    ])

    group("group:root", "", [
        (file_ref(*XCCONFIG), XCCONFIG[1]),
        (oid("group:Tenuo"), "Tenuo"),
        (oid("group:TenuoTests"), "TenuoTests"),
        (oid("group:Products"), "Products"),
    ])
    add("/* End PBXGroup section */")

    add("")
    add("/* Begin PBXNativeTarget section */")

    def native_target(key, name, product_id, product_type, phases, deps):
        add(f"\t\t{oid(key)} /* {name} */ = {{")
        add("\t\t\tisa = PBXNativeTarget;")
        add(f"\t\t\tbuildConfigurationList = {oid(f'configlist:{key}')} "
            f"/* Build configuration list for PBXNativeTarget \"{name}\" */;")
        add("\t\t\tbuildPhases = (")
        for phase in phases:
            add(f"\t\t\t\t{phase},")
        add("\t\t\t);")
        add("\t\t\tbuildRules = (")
        add("\t\t\t);")
        add("\t\t\tdependencies = (")
        for dep in deps:
            add(f"\t\t\t\t{dep},")
        add("\t\t\t);")
        add(f"\t\t\tname = {name};")
        add(f"\t\t\tproductName = {name};")
        add(f"\t\t\tproductReference = {product_id};")
        add(f"\t\t\tproductType = \"{product_type}\";")
        add("\t\t};")

    native_target("target:app", "Tenuo", oid("product:app"),
                  "com.apple.product-type.application",
                  [oid("sources:app"), oid("frameworks:app"), oid("resources:app")], [])
    native_target("target:tests", "TenuoTests", oid("product:tests"),
                  "com.apple.product-type.bundle.unit-test",
                  [oid("sources:tests"), oid("frameworks:tests")], [])
    add("/* End PBXNativeTarget section */")

    add("")
    add("/* Begin PBXProject section */")
    add(f"\t\t{oid('project')} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 2600;")
    add("\t\t\t\tLastUpgradeCheck = 2600;")
    add("\t\t\t\tTargetAttributes = {")
    add(f"\t\t\t\t\t{oid('target:app')} = {{ CreatedOnToolsVersion = 26.0; }};")
    add(f"\t\t\t\t\t{oid('target:tests')} = {{ CreatedOnToolsVersion = 26.0; }};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add(f"\t\t\tbuildConfigurationList = {oid('configlist:project')} "
        "/* Build configuration list for PBXProject \"Tenuo\" */;")
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\ten,")
    add("\t\t\t\tBase,")
    add("\t\t\t);")
    add("\t\t\tpackageReferences = (")
    for package in PACKAGES:
        add(f"\t\t\t\t{oid('pkgref:' + package['name'])} "
            f"/* XCRemoteSwiftPackageReference \"{package['name']}\" */,")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {oid('group:root')};")
    add(f"\t\t\tproductRefGroup = {oid('group:Products')} /* Products */;")
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    add(f"\t\t\t\t{oid('target:app')} /* Tenuo */,")
    add(f"\t\t\t\t{oid('target:tests')} /* TenuoTests */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    add("")
    add("/* Begin XCRemoteSwiftPackageReference section */")
    for package in PACKAGES:
        add(f"\t\t{oid('pkgref:' + package['name'])} "
            f"/* XCRemoteSwiftPackageReference \"{package['name']}\" */ = {{")
        add("\t\t\tisa = XCRemoteSwiftPackageReference;")
        add(f"\t\t\trepositoryURL = \"{package['url']}\";")
        add("\t\t\trequirement = {")
        add("\t\t\t\tkind = upToNextMajorVersion;")
        add(f"\t\t\t\tminimumVersion = {package['minimum']};")
        add("\t\t\t};")
        add("\t\t};")
    add("/* End XCRemoteSwiftPackageReference section */")

    add("")
    add("/* Begin XCSwiftPackageProductDependency section */")
    for package in PACKAGES:
        for product in package["products"]:
            add(f"\t\t{oid(f'pkgprod:{product}')} /* {product} */ = {{")
            add("\t\t\tisa = XCSwiftPackageProductDependency;")
            add(f"\t\t\tpackage = {oid('pkgref:' + package['name'])} "
                f"/* XCRemoteSwiftPackageReference \"{package['name']}\" */;")
            add(f"\t\t\tproductName = {product};")
            add("\t\t};")
    add("/* End XCSwiftPackageProductDependency section */")

    add("")
    add("/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{oid('resources:app')} /* Resources */ = {{")
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for g, n in COPIED_RESOURCES:
        add(f"\t\t\t\t{build_file('res', g, n)} /* {n} in Resources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    add("")
    add("/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{oid('sources:app')} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for g, n in APP_SOURCES:
        add(f"\t\t\t\t{build_file('app', g, n)} /* {n} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add(f"\t\t{oid('sources:tests')} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for g, n in TEST_SOURCES + CORE_SOURCES:
        add(f"\t\t\t\t{build_file('tests', g, n)} /* {n} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    shared = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "15.0",
        "SDKROOT": "macosx",
        "SWIFT_VERSION": "5.0",
    }

    project_debug = dict(shared, **{
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["\"DEBUG=1\"", "\"$(inherited)\""],
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "\"DEBUG $(inherited)\"",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    })
    project_release = dict(shared, **{
        "DEBUG_INFORMATION_FORMAT": "\"dwarf-with-dsym\"",
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
    })

    app_common = {
        "CODE_SIGN_ENTITLEMENTS": "Tenuo/Resources/Tenuo.entitlements",
        "ENABLE_HARDENED_RUNTIME": "YES",
        "COMBINE_HIDPI_IMAGES": "YES",
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "1.0",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Tenuo/Resources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "\"@executable_path/../Frameworks\"",
        "LM_SKIP_METADATA_EXTRACTION": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.tenuo.Tenuo",
        "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }

    tests_common = {
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "1.0",
        "GENERATE_INFOPLIST_FILE": "YES",
        "LM_SKIP_METADATA_EXTRACTION": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.tenuo.TenuoTests",
        "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
    }

    add("")
    add("/* Begin XCBuildConfiguration section */")

    def configuration(key, name, settings, base_config=False):
        add(f"\t\t{oid(key)} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        if base_config:
            add(f"\t\t\tbaseConfigurationReference = {file_ref(*XCCONFIG)} "
                f"/* {XCCONFIG[1]} */;")
        add("\t\t\tbuildSettings = {")
        for setting_key in sorted(settings):
            value = settings[setting_key]
            if isinstance(value, list):
                add(f"\t\t\t\t{setting_key} = (")
                for entry in value:
                    add(f"\t\t\t\t\t{entry},")
                add("\t\t\t\t);")
            else:
                add(f"\t\t\t\t{setting_key} = {value};")
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")

    configuration("config:project:Debug", "Debug", project_debug)
    configuration("config:project:Release", "Release", project_release)
    configuration("config:app:Debug", "Debug", app_common, base_config=True)
    configuration("config:app:Release", "Release", app_common, base_config=True)
    configuration("config:tests:Debug", "Debug", tests_common, base_config=True)
    configuration("config:tests:Release", "Release", tests_common, base_config=True)
    add("/* End XCBuildConfiguration section */")

    add("")
    add("/* Begin XCConfigurationList section */")

    def configuration_list(key, comment, debug_key, release_key):
        add(f"\t\t{oid(key)} /* {comment} */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        add(f"\t\t\t\t{oid(debug_key)} /* Debug */,")
        add(f"\t\t\t\t{oid(release_key)} /* Release */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")

    configuration_list("configlist:project",
                       "Build configuration list for PBXProject \"Tenuo\"",
                       "config:project:Debug", "config:project:Release")
    configuration_list("configlist:target:app",
                       "Build configuration list for PBXNativeTarget \"Tenuo\"",
                       "config:app:Debug", "config:app:Release")
    configuration_list("configlist:target:tests",
                       "Build configuration list for PBXNativeTarget \"TenuoTests\"",
                       "config:tests:Debug", "config:tests:Release")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {oid('project')} /* Project object */;")
    add("}")

    os.makedirs("Tenuo.xcodeproj", exist_ok=True)
    with open("Tenuo.xcodeproj/project.pbxproj", "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print("Wrote Tenuo.xcodeproj/project.pbxproj")

    write_scheme()


def write_scheme():
    """Emits the shared scheme.

    Generated alongside the project rather than checked in by hand: the scheme
    refers to targets by object identifier, so hand-writing it means the two
    files silently drift apart and `xcodebuild -scheme` stops resolving.
    """
    app = oid("target:app")
    tests = oid("target:tests")

    def buildable(identifier, product, name):
        return f"""            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{identifier}"
               BuildableName = "{product}"
               BlueprintName = "{name}"
               ReferencedContainer = "container:Tenuo.xcodeproj">
            </BuildableReference>"""

    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
{buildable(app, "Tenuo.app", "Tenuo")}
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
{buildable(tests, "TenuoTests.xctest", "TenuoTests")}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
{buildable(tests, "TenuoTests.xctest", "TenuoTests")}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{buildable(app, "Tenuo.app", "Tenuo")}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{buildable(app, "Tenuo.app", "Tenuo")}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    path = "Tenuo.xcodeproj/xcshareddata/xcschemes"
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "Tenuo.xcscheme"), "w") as handle:
        handle.write(scheme)
    print(f"Wrote {path}/Tenuo.xcscheme")


if __name__ == "__main__":
    main()
