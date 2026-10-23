"""Generate a deterministic Xcode project without personal signing settings."""
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def create_id(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def quote_value(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def generate_files():
    objects = []
    groups = {}

    def add_object(name, body):
        identifier = create_id(name)
        objects.append(f'{identifier} = {{ {body} }};')
        return identifier

    def add_reference(relative, file_type):
        identifier = add_object(relative, f'isa = PBXFileReference; lastKnownFileType = {file_type}; path = {quote_value(relative)}; sourceTree = SOURCE_ROOT;')
        directory = str(Path(relative).parent)
        groups.setdefault(directory, []).append(identifier)
        return identifier

    def add_build_file(relative, file_type):
        reference = add_reference(relative, file_type)
        return add_object('build:' + relative, f'isa = PBXBuildFile; fileRef = {reference};')

    source_paths = sorted([*ROOT.glob('Sources/GearhouseCore/**/*.swift'), *ROOT.glob('GearhouseApp/**/*.swift')])
    sources = [add_build_file(str(path.relative_to(ROOT)), 'sourcecode.swift') for path in source_paths]
    resources = [add_build_file(path, kind) for path, kind in [
        ('Sources/GearhouseCore/Resources/gearhouse-rules.js', 'sourcecode.javascript'),
        ('Sources/GearhouseCore/Resources/preview-fixture.json', 'text.json'),
        ('GearhouseApp/GearhouseIcon.icon', 'folder.icon'),
    ]]
    ui_sources = [add_build_file(str(path.relative_to(ROOT)), 'sourcecode.swift') for path in sorted(ROOT.glob('UITests/*.swift'))]
    config_reference = add_reference('Config/Project.xcconfig', 'text.xcconfig')
    add_reference('GearhouseApp/Info.plist', 'text.plist.xml')
    add_reference('GearhouseApp/GearhouseApp.entitlements', 'text.plist.entitlements')

    def create_group(directory):
        children = list(groups.get(directory, []))
        descendants = sorted({str(Path(path).relative_to(directory if directory != '.' else '').parts[0]) for path in groups if path != directory and (directory == '.' or path.startswith(directory + '/'))})
        for child in descendants:
            path = child if directory == '.' else directory + '/' + child
            children.append(create_group(path))
        if directory == '.':
            children.append(create_id('products'))
        return add_object('group:' + directory, f'isa = PBXGroup; children = ({",".join(children)},); name = {quote_value(Path(directory).name or "Gearhouse")}; sourceTree = "<group>";')

    main_group = create_group('.')
    app_product = add_object('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = GearhouseApp.app; sourceTree = BUILT_PRODUCTS_DIR;')
    ui_product = add_object('ui-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = GearhouseUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    add_object('products', f'isa = PBXGroup; children = ({app_product},{ui_product},); name = Products; sourceTree = "<group>";')
    for name, kind, files in [('sources', 'PBXSourcesBuildPhase', sources), ('resources', 'PBXResourcesBuildPhase', resources), ('ui-sources', 'PBXSourcesBuildPhase', ui_sources)]:
        add_object(name, f'isa = {kind}; buildActionMask = 2147483647; files = ({",".join(files)},); runOnlyForDeploymentPostprocessing = 0;')

    common = 'CODE_SIGN_STYLE = Automatic; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TARGETED_DEVICE_FAMILY = 1; SWIFT_VERSION = 5.0;'
    for configuration in ['Debug', 'Release']:
        optimization = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if configuration == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
        settings = common + f''' ASSETCATALOG_COMPILER_APPICON_NAME = GearhouseIcon; CODE_SIGN_ENTITLEMENTS = GearhouseApp/GearhouseApp.entitlements; ENTITLEMENTS_REQUIRED = YES; INFOPLIST_FILE = GearhouseApp/Info.plist; PRODUCT_BUNDLE_IDENTIFIER = "$(GEARHOUSE_BUNDLE_IDENTIFIER)"; PRODUCT_NAME = "$(TARGET_NAME)"; CURRENT_PROJECT_VERSION = 2; MARKETING_VERSION = 0.2.0; {optimization}'''
        add_object('target:' + configuration, f'isa = XCBuildConfiguration; name = {configuration}; baseConfigurationReference = {config_reference}; buildSettings = {{ {settings} }};')
        add_object('project:' + configuration, f'isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{ SWIFT_VERSION = 5.0; ALWAYS_SEARCH_USER_PATHS = NO; }};')
        ui_settings = common + ' GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = "$(GEARHOUSE_BUNDLE_IDENTIFIER).UITests"; PRODUCT_NAME = "$(TARGET_NAME)"; TEST_TARGET_NAME = GearhouseApp;'
        add_object('ui:' + configuration, f'isa = XCBuildConfiguration; name = {configuration}; baseConfigurationReference = {config_reference}; buildSettings = {{ {ui_settings} }};')
    for target in ['target', 'project', 'ui']:
        add_object('config:' + target, f'isa = XCConfigurationList; buildConfigurations = ({create_id(target + ":Debug")},{create_id(target + ":Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
    app_target = add_object('target', f'isa = PBXNativeTarget; buildConfigurationList = {create_id("config:target")}; buildPhases = ({create_id("sources")},{create_id("resources")},); buildRules = (); dependencies = (); name = GearhouseApp; productName = GearhouseApp; productReference = {app_product}; productType = "com.apple.product-type.application";')
    proxy = add_object('ui-proxy', f'isa = PBXContainerItemProxy; containerPortal = {create_id("project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = GearhouseApp;')
    dependency = add_object('ui-dependency', f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
    ui_target = add_object('ui-target', f'isa = PBXNativeTarget; buildConfigurationList = {create_id("config:ui")}; buildPhases = ({create_id("ui-sources")},); buildRules = (); dependencies = ({dependency},); name = GearhouseUITests; productName = GearhouseUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
    project = add_object('project', f'isa = PBXProject; attributes = {{LastUpgradeCheck = 2600;}}; buildConfigurationList = {create_id("config:project")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; knownRegions = (en, Base, "zh-Hans",); mainGroup = {main_group}; productRefGroup = {create_id("products")}; projectDirPath = ""; projectRoot = ""; targets = ({app_target},{ui_target},);')
    project_text = '// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + '\n}; rootObject = ' + project + '; }\n'

    def create_reference(identifier, name):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:GearhouseApp.xcodeproj"/>'

    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{create_reference(app_target, "GearhouseApp.app")}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{create_reference(ui_target, "GearhouseUITests.xctest")}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{create_reference(app_target, "GearhouseApp.app")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{create_reference(app_target, "GearhouseApp.app")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    return {'GearhouseApp.xcodeproj/project.pbxproj': project_text, 'GearhouseApp.xcodeproj/xcshareddata/xcschemes/GearhouseApp.xcscheme': scheme}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Fail if the checked-in project differs from the sources.')
    args = parser.parse_args()
    outdated = []
    for relative, text in generate_files().items():
        path = ROOT / relative
        if args.check:
            if not path.exists() or path.read_text() != text:
                outdated.append(relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    if outdated:
        raise SystemExit('Regenerate the Xcode project: python3 scripts/generate-project.py\n' + '\n'.join(outdated))
    print('Xcode project is current.' if args.check else 'Generated Xcode project.')


if __name__ == '__main__':
    main()
