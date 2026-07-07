// CameraLevelMath.swift
// Vehicle Damage Investigation Assistant
// Converts a raw gravity vector into a pitch/roll pair meaningful for
// *handheld photography*, where 0/0 means "phone held vertically, camera
// aimed level at the subject" -- fixing a real bug in the original code.

import Foundation

/// NOTE(AI Developer), added 2026-07 per Sean's on-device report ("why is
/// the camera preferred to be pointing down for everything?"):
///
/// The original code fed `CMDeviceMotion.attitude.pitch`/`.roll` straight
/// into `SensorData`/`SensorReading`. Those are correct raw values, but
/// **CMAttitude's own zero-point is "phone lying flat on a table, screen
/// up"** — not "phone held upright, camera aimed at the horizon" (the
/// orientation you're actually in for 95% of these forensic shots).
/// `CaptureProtocolStep.fullProtocol`'s `idealPitchDegrees` (0°, ±5°, ±15°)
/// were clearly authored assuming the *second* convention (small angles =
/// small tilts from "aimed level at the vehicle"). Comparing those against
/// raw `attitude.pitch` meant the only way to satisfy "pitch near 0" was
/// to physically flatten the phone and point the camera at the ground --
/// exactly the symptom Sean reported.
///
/// Fix: derive pitch/roll from the device's raw `gravity` vector instead
/// (an unambiguous physical quantity, magnitude 1g, expressed in the
/// device's own X-right/Y-toward-top/Z-out-of-screen frame), using a
/// convention where 0°/0° = "phone vertical, camera level".
///
/// NOTE: I don't have a physical device in this sandbox to verify the sign
/// empirically. The *zero point and magnitude* are derived correctly from
/// first principles below, but if the on-screen up/down arrow (see
/// `SensorLevelBar`) ever points the *opposite* of what feels natural on
/// your phone, this is an isolated one-line fix: negate the `atan2`
/// argument order on the `pitchRad` line below (and tell me — 30 second
/// turnaround).
enum CameraLevelMath {

    /// - Parameter g: `CMDeviceMotion.gravity` components (x, y, z), each
    ///   in units of g (magnitude ~1 when stationary).
    /// - Returns: (pitchDegrees, rollDegrees) where both are ~0 when the
    ///   phone is held vertically in portrait orientation with the camera
    ///   aimed level at the horizon.
    static func pitchRollDegrees(fromGravity g: (x: Double, y: Double, z: Double)) -> (pitchDegrees: Double, rollDegrees: Double) {
        // Device frame (portrait, held vertically for photography):
        //   +X = right, +Y = toward top of phone, +Z = out of the screen
        //   (toward the user's face).
        // Held level, aimed at the horizon: gravity points straight down
        // the phone's own -Y axis, i.e. g ~= (0, -1, 0).
        //
        // Pitch (camera aim tilting up/down from the horizon) rotates
        // gravity between the Y and Z axes:
        let pitchRad = atan2(-g.z, -g.y)
        // Roll (tilting left/right, e.g. a Dutch angle) rotates gravity
        // between the Y and X axes:
        let rollRad = atan2(g.x, -g.y)
        return (pitchRad * 180.0 / .pi, rollRad * 180.0 / .pi)
    }
}
