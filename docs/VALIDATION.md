# Validation

Validation performed on the development Apple silicon Mac on 19 October 2026.
This records the tested scope of version 0.1.0, not feature equivalence with
the reference app.

## Automated results

16 XCTest cases passed, with zero failures and zero skips. The suite uses
generated temporary fixtures and the installed conversion engines:

- Native still images, resize/rotation, preserved originals, unique outputs.
- PDF merge, split, rotation, rendering, raster compression and text extraction.
- Text/DOCX/RTF/PDF and Pandoc Markdown conversions.
- CSV quoted fields, embedded newlines and malformed-row rejection.
- Subtitle Unicode text and SRT/VTT timing.
- ZIP/TAR/GZIP round trips and rejection of archive traversal and links.
- FFmpeg audio/video formats and tools, cwebp and AVIF.
- Cancellation of an active subprocess.
- Wheel selection matches every displayed segment, with no selection at the
  center or outside the wheel.

HEIC encoding needed access to the system encoder service unavailable inside
the agent's execution sandbox. The complete test suite passed outside that
sandbox. The resulting app is a normal locally signed macOS app, not an App
Sandbox container.

## Build checks

`./scripts/build-app.sh --universal` completed. `file` confirmed arm64 and
x86_64 slices. `vtool -show-build` confirmed minimum macOS 13.0 for each slice.
`codesign --verify --deep --strict` accepted the ad hoc signature.
The generated `.app` and ZIP live in ignored `dist/`.

Building for an architecture does not establish runtime testing on that hardware.
Neither Intel execution nor an older macOS installation was available for this run.

## Native interface checks

The packaged app launched successfully with its French workspace, menu bar
entry, file picker, format selection, and radial wheel. Selecting a real,
user-authorized HEIC file through the native picker populated all image options.
Opening the wheel displayed its rounded sectors. Clicking its PNG sector created
a readable 2190 × 2130 PNG beside the source, recorded a successful history entry,
and revealed the output in Finder. A SHA-256 check confirmed the original was
unchanged. The photo and generated output are not included in the repository.

The user subsequently performed the full Finder drag + Shift + wheel drop
gesture on the development Mac and confirmed both wheel appearance and
successful conversion. This is user-reported live validation, separate from the
automated geometry tests and the agent-observed click-to-convert check.

AirDrop recipient selection, Terminal integration and the full range of input
codecs/document layouts have not been individually exercised. Those are explicit
remaining coverage boundaries.

## Version 0.2.0 interface refresh

The blue Liquid Glass workspace, file selection, format controls, settings and
radial wheel were inspected in the packaged app on the development Mac. The
README contains actual workspace and wheel screenshots, with no personal files.
The wheel's PNG hover selection was checked after the visual changes. The full
Finder drag gesture was not repeated by the agent for this visual refresh.

All 16 existing tests passed again, with zero failures and zero skips. The
universal release build and strict signature verification also passed. The
installed app remains an accessory app with `LSUIElement` enabled. Native glass
uses availability guards; older macOS versions retain material fallbacks.
Dark appearance, Reduce Transparency and older macOS runtime behavior have not
been visually exercised in this refresh.
