# Reference analysis

Prisme is an independently written Swift application informed by the visible
workflow of Tangerine. This report records bounded inspection of a locally
installed reference on 19 October 2026. No original executable, JavaScript,
artwork, or other application resources are included in this repository. The
reference was not patched, its entitlement checks were not changed, and its
trial allowance was not reset. This is not a full decompilation or a claim of
feature equivalence.

## Target and evidence ledger

The inspected target was `/Applications/Tangerine.app`, version **2.0.2 (9)**,
bundle identifier `com.th.Tangerine`. REA **6.7.0** was used through its CLI;
no disassembler was installed and no native analysis session was opened.

| ID | Evidence and scope | Established facts |
| --- | --- | --- |
| R1 | `inspect-artifact`, Evidence `ev_73a27bda3cea5f0d57fc2f5265de8eba367b1d8ab233ad7faa7a874ecff1dc5c` | Static directory inventory only. |
| R1a | Nested inventory Evidence `ev_4bd22f58e8fa04e11d09496dce56c824d1a2804a1ab5b3c8fe0a3521f7ac677f`, manifest `agm_1486d87829bcef0c083d842722f2853d9e829a7f8bb9ff71a5b80dc574b56319` | 422 unique artifact nodes, 525 occurrences, 488 graph edges; container-entry coverage reported complete. |
| R2 | `trace-dylib-resolution`, Evidence `ev_fd83c0ec75ef45aea880961ba47830c29d1c4b81bd128f4d9a633dd324074ed4` | Static Mach-O load commands and modeled in-bundle dependency paths; 7 executable roots, 9 parsed images, 95 edges. |
| P1 | Direct `plistlib` read of `Contents/Info.plist`; not a REA Evidence record | Name, version/build, bundle identifier, minimum system 13.0, and `LSUIElement = true`. |
| U1 | Reference settings observed in the native UI during this task; not an automated REA runtime trace | Menu bar workflow, configurable conversion/tool/action keys, appearance choices, and folder settings. |
| W1 | [Publisher's public feature page](https://tangerineformac.com/), retrieved 19 October 2026 | Public feature claims, which were not all exercised in the installed application. |
| W2 | Browser interaction with the publisher's simulated demo on 19 October 2026; not installed-app runtime evidence | Enter on `landscape.jpg` opened a roughly 272 × 272 px petal ring. PNG was selected; ArrowRight selected WEBP and updated the center label. |

Identity anchors:

```text
R1/R1a bundle root SHA-256 (REA directory identity):
ec4f2ecc3a151db6de7491fbefde182270257b4a35fd3cf097083859242d772c
R2 main executable SHA-256, arm64, 11,200,496 bytes:
7691b34cc2c728aaf280041c0a13adef3e5192c43cb3e886a19ae4c69ea92928
P1 Info.plist SHA-256:
045e050657437b52b0a81dafdc155f6d01998d9571286dfe90ba339371eabb70
```

The directory digest and executable digest describe different subjects. They
must not be compared as if they were hashes of the same file. A later app update
requires a fresh inventory and version check.

## Findings and implications

**Observed reference interaction (U1).** General settings show independently
configurable Shift conversion, Command tool, and Control action triggers. The
reference offers glass/solid appearance and folder settings. These observations
support a menu bar utility with a transient drag interaction; they do not
establish its internal event-monitor or drag-pasteboard implementation.

**Public behavior (W1).** The publisher describes local processing, a modifier
key wheel during dragging, conversion across several media/document families,
and file actions. It advertises 275 conversion choices, 26 tools, and six
actions, and requires Apple silicon with macOS 13 or later. These counts are
marketing claims, not verified test coverage. [Source](https://tangerineformac.com/)

**Interactive site demo (W2).** The simulated file interaction exposed a ring of
rounded petals, keyboard selection, and a changing center label. The website
explicitly identifies its operations as simulated, so this observation does not
verify a real conversion or installed-app behavior. Prisme uses an independently
written segmented wheel with its own color treatment and adjusted petals; the
reference's implementation and resources were not copied.

**Static native dependencies (R2).** The main executable is an arm64 Mach-O and
declares Swift runtime, SwiftUI, AppKit, ImageIO, AVFoundation, PDFKit, Vision,
WebKit, and JavaScriptCore dependencies, among others. These load commands
establish linked interfaces. They do not show which conversion path executes
which API, its quality settings, or its failure handling. The presence of
StoreKit establishes a declared dependency, not the design of trial accounting.

**Packaged helpers (R1a, R2).** The inventory includes `Tools/cwebp`,
`Tools/ffmpeg`, Java launcher trees under `PowerPoint/arm64` and
`PowerPoint/x86_64`, and resources named `OfficePreview.js` and `PagesWriter.js`.
It also includes JARs named for Apache POI and PDFBox. These are observed files
and path/name facts; their names alone do not prove the role of a particular
function or every claimed conversion. Prisme does not copy these resources.

**Analysis limits.** `inspect-macho` and `inspect-plist` initially failed while
REA compiled its macOS process ownership helper: the sandbox denied its default
Swift module-cache location. Retrying with writable module-cache environment
variables did not change that error. Those error envelopes are not Evidence.
The successful R1/R2 built-in parsers remain useful without these operations.
System library paths remain undetermined in R2 because its selected boundary
does not inspect the dyld shared cache. Static parse coverage does not establish
runtime feature coverage, privacy properties, signing validity, or conversion
correctness. Original method bodies, exact algorithms, defaults, and edge cases
remain unknown.

## Reconstruction coverage

The following is a scope ledger, not an equivalence score. The native Swift and
SwiftUI application compiles. Sixteen fixture/geometry tests passed on the
development Mac outside the sandbox, with no skips. Inside the sandbox the HEIC
service was unavailable, so that restricted run alone could not validate HEIC.
The universal build completed with both architecture slices targeting macOS 13.
Its local ad hoc signature was verified. Native launch, wheel conversion, and
the user's complete drag gesture were exercised on the development Mac.

| Area | Reference basis | Prisme implementation/verification status |
| --- | --- | --- |
| Menu bar app and file intake | U1, P1 | Native launch, file-picker intake and successful history record observed; global drag intake confirmed by the user. |
| Transient conversion/tool/action interface | U1, W1, W2 | Original segmented `NSView` radial wheel; geometry tests pass, PNG conversion observed, and complete drag-and-drop conversion confirmed by the user. Exact reference mechanics remain unknown. |
| Configurable modifier triggers and appearance | U1 | Configurable keys and tinted/solid appearance implemented; default Shift gesture confirmed by the user. Other trigger/appearance combinations not individually exercised. |
| Image conversion and basic tools | W1; relevant dependencies in R2 | Native engine subset implemented; fixture-backed outcomes are covered within the 16 passing tests. This does not establish every advertised format pair or visual fidelity. |
| PDF/text/media/archive processing | W1; relevant helper/dependency presence in R1a/R2 | Implemented subset with fixture-backed engine checks within the 16 passing tests; broader reference parity remains unverified. |
| File actions and folder destinations | U1, W1 | Reveal, copy, copy path, AirDrop, and Terminal implemented, with output-folder selection. Float and Move are not implemented. Manual verification pending. |
| Office/slide/ebook fidelity and all advertised format pairs | W1; helper names in R1a | Unverified; no parity claim. |
| Licensing and conversion allowance | User-reported commercial behavior; StoreKit dependency in R2 | No reconstruction required; Prisme has its own independent feature scope. |

## Integrated native validation

The final universal app was built and launched on the development Mac. Its
radial wheel converted the authorized HEIC test file to a 2190 × 2130 PNG;
the output was readable and the original hash was unchanged. The user then
confirmed the complete Finder drag + Shift + drop interaction worked. This
user-reported live check applies to Prisme, not to the reference application.
See [validation](VALIDATION.md) for exact coverage and remaining limitations.

## Reproduce the static inspection

Run `./scripts/analyze-reference.sh /Applications/Tangerine.app` from a checkout
with Node.js, npm, Python 3, and the pinned REA CLI available. The script explains
the CLI-only installation if it cannot find REA. `REA_CLI` can select an
explicit installed executable. No MCP configuration is needed.

The script reads the bundle and writes complete JSON to a new `.analysis/`
directory. Keep `.analysis/` ignored by Git; full evidence and reference files
are local investigation material. `REA_NATIVE=1` additionally attempts the two
optional native metadata operations and retains any error envelopes. The script
does not launch the reference, attach a debugger, extract resources, modify
preferences, or contact a reference service.

Document only sanitized summaries, Evidence IDs, source boundaries, and digests
in a shared report. Review complete local evidence before sharing it; it is not
automatically a distributable source artifact.
