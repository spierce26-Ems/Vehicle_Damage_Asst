#!/usr/bin/env python3
"""Deterministic 24-hex-char ID generator for hand-authored pbxproj skeleton."""
import uuid

def gen_id(seed: str) -> str:
    return uuid.uuid5(uuid.NAMESPACE_OID, seed).hex.upper()[:24]

KEYS = [
    "PROJECT", "MAINGROUP", "PRODUCTS_GROUP", "APP_FILEREF",
    "TARGET", "BUILDPHASE_SOURCES", "BUILDPHASE_FRAMEWORKS", "BUILDPHASE_RESOURCES",
    "PROJECT_CONFIGLIST", "PROJECT_CONFIG_DEBUG", "PROJECT_CONFIG_RELEASE",
    "TARGET_CONFIGLIST", "TARGET_CONFIG_DEBUG", "TARGET_CONFIG_RELEASE",
]

if __name__ == "__main__":
    ids = {k: gen_id("com.spearitnow.vdf." + k) for k in KEYS}
    for k, v in ids.items():
        print(f"{k}={v}")
