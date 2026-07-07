#!/usr/bin/env python3
"""
Populate VehicleDamageForensics.xcodeproj/project.pbxproj with all Swift
sources + Info.plist, preserving the on-disk folder structure as Xcode
groups.

Run from ios/ directory:  python3 ../scripts/build_pbxproj.py

Idempotent: re-running just verifies group/file presence (get_or_create_group
looks up existing groups by name; add_file(force=False) skips files that are
already referenced).
"""
import os
import sys

from pbxproj import XcodeProject
from pbxproj.pbxextensions.ProjectFiles import FileOptions
from pbxproj.PBXKey import PBXKey

PROJECT_PATH = "VehicleDamageForensics.xcodeproj/project.pbxproj"
SOURCE_DIR = "VehicleDamageForensics"
TARGET_NAME = "VehicleDamageForensics"


def main():
    project = XcodeProject.load(PROJECT_PATH)

    # Walk SOURCE_DIR, creating one Xcode group per on-disk subdirectory
    # (mirroring physical structure), and add every .swift file + the
    # Info.plist into the matching group.
    group_cache = {"": None}  # relative dir path -> PBXGroup (None = root src group)

    def group_for(rel_dir):
        """Get-or-create the nested group chain for a relative directory
        path like 'Views/Capture', returning the deepest group object."""
        if rel_dir in group_cache:
            return group_cache[rel_dir]
        parent_rel = os.path.dirname(rel_dir)
        parent_group = group_for(parent_rel) if parent_rel or parent_rel == "" else None
        if parent_rel == "" and rel_dir not in group_cache:
            parent_group = group_cache[""]
        name = os.path.basename(rel_dir)
        grp = project.get_or_create_group(name, parent=parent_group)
        group_cache[rel_dir] = grp
        return grp

    # Root group for all of VehicleDamageForensics/ contents, nested under
    # the project's main group so it shows as a top-level "VehicleDamageForensics"
    # folder in Xcode (matches the on-disk layout exactly).
    root_src_group = project.get_or_create_group(SOURCE_DIR)
    group_cache[""] = root_src_group

    added_files = []
    for dirpath, dirnames, filenames in os.walk(SOURCE_DIR):
        # .xcassets is added as a single opaque resource folder (Xcode's own
        # asset-catalog type), not walked into file-by-file, so prune it
        # from further recursion once we've added it as a unit.
        if os.path.basename(dirpath).endswith(".xcassets"):
            rel_dir_parent = os.path.relpath(os.path.dirname(dirpath), SOURCE_DIR)
            rel_dir_parent = "" if rel_dir_parent == "." else rel_dir_parent
            parent_grp = group_for(rel_dir_parent)
            result = project.add_file(
                dirpath,
                parent=parent_grp,
                target_name=TARGET_NAME,
                force=False,
                file_options=FileOptions(create_build_files=True),
            )
            added_files.append((dirpath, bool(result)))
            dirnames[:] = []  # don't recurse into the asset catalog's internals
            continue

        dirnames.sort()
        rel_dir = os.path.relpath(dirpath, SOURCE_DIR)
        rel_dir = "" if rel_dir == "." else rel_dir
        grp = group_for(rel_dir)

        for fname in sorted(filenames):
            if fname.startswith("."):
                continue
            if not (fname.endswith(".swift") or fname == "Info.plist"):
                continue
            rel_path = os.path.join(dirpath, fname)
            # NOTE: Info.plist must be added as a plain file reference only
            # (create_build_files=False) -- it's wired up via the
            # INFOPLIST_FILE build setting in project.pbxproj, not via the
            # Copy Bundle Resources build phase. Adding it as a resource
            # build file too causes Xcode's classic "Multiple commands
            # produce Info.plist" build error.
            is_plist = fname == "Info.plist"
            file_options = FileOptions(create_build_files=not is_plist)
            result = project.add_file(
                rel_path,
                parent=grp,
                target_name=None if is_plist else TARGET_NAME,
                force=False,
                file_options=file_options,
            )
            added_files.append((rel_path, bool(result)))

    project.save()

    print(f"Processed {len(added_files)} files:")
    for path, was_added in added_files:
        status = "added" if was_added else "already present / no-op"
        print(f"  [{status:24s}] {path}")


if __name__ == "__main__":
    main()
