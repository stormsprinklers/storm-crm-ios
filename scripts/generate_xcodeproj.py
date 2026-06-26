#!/usr/bin/env python3
"""Generate StormCRM.xcodeproj from project.yml layout."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STORMCRM = ROOT / "StormCRM"
OUT = ROOT / "StormCRM.xcodeproj" / "project.pbxproj"


def uid(key: str) -> str:
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()


def collect_swift_files() -> list[Path]:
    files = sorted(STORMCRM.rglob("*.swift"))
    return files


def pbx_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def main() -> None:
    swift_files = collect_swift_files()
    assert any(f.name == "TeamInboxView.swift" for f in swift_files), "TeamInboxView.swift missing"

    project_id = uid("project")
    target_id = uid("target")
    sources_phase_id = uid("sources")
    resources_phase_id = uid("resources")
    frameworks_phase_id = uid("frameworks")
    product_ref_id = uid("product")
    main_group_id = uid("main_group")
    products_group_id = uid("products_group")
    storm_group_id = uid("storm_group")

    file_refs: dict[str, str] = {}
    build_files: dict[str, str] = {}
    for path in swift_files:
        rel = pbx_path(path)
        file_refs[rel] = uid(f"fileref:{rel}")
        build_files[rel] = uid(f"buildfile:{rel}")

    assets_ref = uid("fileref:assets")
    entitlements_ref = uid("fileref:entitlements")
    plist_ref = uid("fileref:plist")
    assets_build = uid("buildfile:assets")

    groups: dict[str, list[str]] = {}
    for path in swift_files:
        rel = pbx_path(path)
        parent = str(Path(rel).parent)
        groups.setdefault(parent, []).append(rel)
    groups.setdefault("StormCRM", [])
    groups.setdefault("StormCRM/Features", [])
    groups["StormCRM/Resources"] = []

    group_ids: dict[str, str] = {".": main_group_id, "StormCRM": storm_group_id}
    for parent in groups:
        if parent not in group_ids:
            group_ids[parent] = uid(f"group:{parent}")

    lines: list[str] = []
    lines.append("// !$*UTF8*$!")
    lines.append("{")
    lines.append("\tarchiveVersion = 1;")
    lines.append("\tclasses = {")
    lines.append("\t};")
    lines.append("\tobjectVersion = 56;")
    lines.append("\tobjects = {")

    lines.append("\n/* Begin PBXBuildFile section */")
    for rel, bid in sorted(build_files.items(), key=lambda x: x[0]):
        lines.append(
            f"\t\t{bid} /* {Path(rel).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[rel]} /* {Path(rel).name} */; }};"
        )
    lines.append(
        f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};"
    )
    lines.append("/* End PBXBuildFile section */\n")

    lines.append("/* Begin PBXFileReference section */")
    lines.append(
        f"\t\t{product_ref_id} /* StormCRM.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = StormCRM.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    for rel, fid in sorted(file_refs.items(), key=lambda x: x[0]):
        lines.append(
            f"\t\t{fid} /* {Path(rel).name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {Path(rel).name}; sourceTree = \"<group>\"; }};"
        )
    lines.append(
        f"\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};"
    )
    lines.append(
        f"\t\t{entitlements_ref} /* StormCRM.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = StormCRM.entitlements; sourceTree = \"<group>\"; }};"
    )
    lines.append(
        f"\t\t{plist_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
    )
    lines.append("/* End PBXFileReference section */\n")

    lines.append("/* Begin PBXFrameworksBuildPhase section */")
    lines.append(
        f"\t\t{frameworks_phase_id} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};"
    )
    lines.append("/* End PBXFrameworksBuildPhase section */\n")

    lines.append("/* Begin PBXGroup section */")
    lines.append(
        f"\t\t{products_group_id} /* Products */ = {{isa = PBXGroup; children = ({product_ref_id} /* StormCRM.app */); name = Products; sourceTree = \"<group>\"; }};"
    )

    def group_block(path_key: str) -> str:
        gid = group_ids[path_key]
        children: list[str] = []
        if path_key == ".":
            children = [
                f"{storm_group_id} /* StormCRM */",
                f"{products_group_id} /* Products */",
            ]
        else:
            for rel in sorted(groups.get(path_key, [])):
                children.append(f"{file_refs[rel]} /* {Path(rel).name} */")
            child_dirs = sorted(
                {
                    p
                    for p in groups
                    if p != path_key and p.startswith(path_key + "/") and "/" not in p[len(path_key) + 1 :]
                }
            )
            for child in child_dirs:
                children.append(f"{group_ids[child]} /* {Path(child).name} */")
            if path_key == "StormCRM/Resources":
                children.extend(
                    [
                        f"{assets_ref} /* Assets.xcassets */",
                        f"{entitlements_ref} /* StormCRM.entitlements */",
                        f"{plist_ref} /* Info.plist */",
                    ]
                )
            if path_key == "StormCRM/Features":
                feature_dirs = sorted(
                    p for p in groups if p.startswith("StormCRM/Features/") and p.count("/") == 2
                )
                for child in feature_dirs:
                    children.append(f"{group_ids[child]} /* {Path(child).name} */")
        name = Path(path_key).name if path_key not in {".", "StormCRM"} else ("StormCRM" if path_key == "StormCRM" else None)
        if path_key == ".":
            return (
                f"\t\t{gid} = {{isa = PBXGroup; children = ({' '.join(children)}); sourceTree = \"<group>\"; }};"
            )
        return (
            f"\t\t{gid} /* {path_key} */ = {{isa = PBXGroup; children = ({' '.join(children)}); "
            f"name = {name}; path = {name}; sourceTree = \"<group>\"; }};"
        )

    lines.append(group_block("."))
    lines.append(group_block("StormCRM"))
    for path_key in sorted(group_ids):
        if path_key in {".", "StormCRM"}:
            continue
        lines.append(group_block(path_key))
    lines.append("/* End PBXGroup section */\n")

    lines.append("/* Begin PBXNativeTarget section */")
    lines.append(
        f"\t\t{target_id} /* StormCRM */ = {{isa = PBXNativeTarget; buildConfigurationList = {uid('target configs')} /* Build configuration list for PBXNativeTarget \"StormCRM\" */; buildPhases = ({sources_phase_id} /* Sources */, {frameworks_phase_id} /* Frameworks */, {resources_phase_id} /* Resources */); buildRules = (); dependencies = (); name = StormCRM; productName = StormCRM; productReference = {product_ref_id} /* StormCRM.app */; productType = \"com.apple.product-type.application\"; }};"
    )
    lines.append("/* End PBXNativeTarget section */\n")

    lines.append("/* Begin PBXProject section */")
    lines.append(
        f"\t\t{project_id} /* Project object */ = {{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 1500; }}; buildConfigurationList = {uid('project configs')} /* Build configuration list for PBXProject \"StormCRM\" */; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group_id}; productRefGroup = {products_group_id} /* Products */; projectDirPath = \"\"; projectRoot = \"\"; targets = ({target_id} /* StormCRM */); }};"
    )
    lines.append("/* End PBXProject section */\n")

    lines.append("/* Begin PBXResourcesBuildPhase section */")
    lines.append(
        f"\t\t{resources_phase_id} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assets_build} /* Assets.xcassets in Resources */); runOnlyForDeploymentPostprocessing = 0; }};"
    )
    lines.append("/* End PBXResourcesBuildPhase section */\n")

    lines.append("/* Begin PBXSourcesBuildPhase section */")
    source_entries = " ".join(
        f"{build_files[rel]} /* {Path(rel).name} in Sources */" for rel in sorted(build_files)
    )
    lines.append(
        f"\t\t{sources_phase_id} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({source_entries}); runOnlyForDeploymentPostprocessing = 0; }};"
    )
    lines.append("/* End PBXSourcesBuildPhase section */\n")

    lines.append("/* Begin XCBuildConfiguration section */")
    debug_id = uid("debug")
    release_id = uid("release")
    target_debug_id = uid("target debug")
    target_release_id = uid("target release")
    for cfg_id, name, target in [
        (debug_id, "Debug", False),
        (release_id, "Release", False),
        (target_debug_id, "Debug", True),
        (target_release_id, "Release", True),
    ]:
        if target:
            lines.append(
                f"\t\t{cfg_id} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_ENTITLEMENTS = StormCRM/Resources/StormCRM.entitlements; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = StormCRM/Resources/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 17.0; LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\"); MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.stormsprinklers.stormcrm; PRODUCT_NAME = \"$(TARGET_NAME)\"; SWIFT_VERSION = 5.9; TARGETED_DEVICE_FAMILY = \"1,2\"; }}; name = {name}; }};"
            )
        else:
            lines.append(
                f"\t\t{cfg_id} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; COPY_PHASE_STRIP = NO; DEBUG_INFORMATION_FORMAT = {'dwarf' if name == 'Debug' else 'dwarf-with-dsym'}; ENABLE_TESTABILITY = {'YES' if name == 'Debug' else 'NO'}; GCC_DYNAMIC_NO_PIC = NO; GCC_OPTIMIZATION_LEVEL = {'0' if name == 'Debug' else 's'}; IPHONEOS_DEPLOYMENT_TARGET = 17.0; MTL_ENABLE_DEBUG_INFO = {'INCLUDE_SOURCE' if name == 'Debug' else 'NO'}; ONLY_ACTIVE_ARCH = {'YES' if name == 'Debug' else 'NO'}; SDKROOT = iphoneos; SWIFT_ACTIVE_COMPILATION_CONDITIONS = {'DEBUG' if name == 'Debug' else ''}; SWIFT_OPTIMIZATION_LEVEL = {'-Onone' if name == 'Debug' else '-O'}; SWIFT_VERSION = 5.9; }}; name = {name}; }};"
            )
    lines.append("/* End XCBuildConfiguration section */\n")

    lines.append("/* Begin XCConfigurationList section */")
    lines.append(
        f"\t\t{uid('project configs')} /* Build configuration list for PBXProject \"StormCRM\" */ = {{isa = XCConfigurationList; buildConfigurations = ({debug_id} /* Debug */, {release_id} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};"
    )
    lines.append(
        f"\t\t{uid('target configs')} /* Build configuration list for PBXNativeTarget \"StormCRM\" */ = {{isa = XCConfigurationList; buildConfigurations = ({target_debug_id} /* Debug */, {target_release_id} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};"
    )
    lines.append("/* End XCConfigurationList section */")
    lines.append("\t};")
    lines.append(f"\trootObject = {project_id} /* Project object */;")
    lines.append("}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT} with {len(swift_files)} Swift files")


if __name__ == "__main__":
    main()
