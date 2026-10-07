# Screenshot alignment review · 2026-10-03

## Scope and source truth

Existing Electron renderer, starting at local commit `6732a0a4b2d6d26d7821699d6d9b51755f5a44f5`. This pass aligns the existing project/tag surfaces to the original repository screenshots; it does not port missing managers, Gantt, or the full focus-workspace feature set.

Source visual truth:
- `../准备传Github用的截图/截屏2026-08-26 16.25.26.png`: project task list, hierarchy, section headings and project inspector
- `../准备传Github用的截图/截屏2026-08-28 07.33.16.png`: selected tag, category navigation and tag inspector
- Other original repository screenshots were inspected for toolbar/rail consistency

Source PNGs: 3230 × 2132 with embedded Display ICC profile. UI crop is (112,76)–(3118,1984), or 1503 × 954 logical pixels at 2×. Samples were interpreted in sRGB, not copied from raw ICC-profile RGB values.

Implementation: real sandboxed Electron production window on the cloud Linux desktop, 1364 × 936 pixels, 1×, with isolated fictional data. The available desktop constrains the window width; the center is therefore 139 logical pixels narrower than the source. Fixed column dimensions remain source-sized. No same-viewport pixel-error score is claimed.

Implementation screenshot path: unavailable. The supported capture interface returned and displayed actual image bytes but supplied no supported file-save path. Images were visually opened in the tool and the source and rendered project view were included together in one comparison call. Independent downloadable screenshot files are not included. No reconstructed screenshot is substituted for an app capture.

## Findings and changes

### Layout and spacing
- Corrected fixed tracks to 79 / 301 / flexible / 390 border-box pixels, matching source 78 / 300 / flexible / 390 plus the two separate 1 px dividers
- Project/tag page and inspector headers: 71 → 50 px; toolbar stays 78 px
- Project/tag rows: 38 px comfortable, 32 px compact; use variable-height chunk windowing instead of the old 70/50 px virtual-row arithmetic
- Restored existing section/category display, 18 px child indentation and same-line plan/deadline/priority/tag metadata
- Removed the permanent filter toolbar from the resting project/tag view; header filter/search and Ctrl/Cmd+K retain those controls
- Removed row dividers, persistent ellipsis, heavy selection stripe and unnecessary project subtitle in reference views
- Post-capture correction removed an accidental margin caused by a hidden generic heading still counting as a DOM first child. The first/second project section dividers now visually land near the source's 180/378 px logical positions

### Typography
- Use system UI/PingFang first, with explicit Noto Sans CJK SC fallback on Linux
- Workspace 16 px, page heading 21 px, inspector title 19 px, task/browser rows 13 px, metadata 10.5 px
- Fixed title clipping after a display-mode change; long titles now ellipsize before same-line metadata and retain their full title tooltip
- Mac SF/PingFang rasterization is not available on Linux; font rendering is an expected remaining platform difference

### Colors and tokens
- Source-derived neutral surfaces: rail #F4F4FC, browser #F9FAFC, canvas #FDFDFE, inspector #FFFFFF, dividers #E4E4E5, text #272727
- Flat selection fills and entity-colored project/tag icons; shared blue completion state retained
- Dark mode retains its own readable token set; section colors are lightened without changing their hue family
- Interaction text and primary controls are slightly darker than the source's #0088FF where needed for legibility. This is an intentional contrast accommodation, not a pixel match

### Icons and imagery
- No raster artwork is required for these source screens. Native macOS traffic-light controls are OS chrome and are not imitated inside Linux app content
- Replaced custom path drawings with static per-icon imports from Phosphor Icons 2.1.10. Tags/calendar/checklist/history/Gantt meanings now follow the reference
- Phosphor is a cross-platform approximation of SF Symbols, not the original Apple glyphs
- JS production payload increases from about 362 kB / 112 kB gzip to about 455 kB / 131 kB gzip due to the licensed icon family and reference-view components; only required icon modules are imported

### Copy/content and functional boundaries
- Fictional reference-named projects, sections, tags and task hierarchy were used; date labels use the current local test date rather than pretending it is August 2026
- Existing tag definitions/categories populate a real read-only tag inspector; no fabricated edit/merge/delete controls were added
- Source controls for project icon palettes, full tag management, composer quick-property menus and Gantt remain unported. The focus workspace also remains the existing simpler Electron implementation. These are material differences for a full-application screenshot replica and are not claimed complete in this pass

## Iteration history

1. Initial comparison: major vertical-density drift, wrong neutral palette, generic task list instead of sections, generic statistics in tag inspector, mismatched icon meanings
2. Implemented source-sized tracks, 50/38 px geometry, shared surfaces, real metadata grouping/details and licensed icons; captured actual project/tag views
3. Corrected first-heading margin, precise date labels, bounded tags/titles, custom section colors and the compact-mode cascade; captured revised views and tested related interactions
4. Final native review: verified light project/tag views, dark/compact rendering and large-list navigation. Remaining source-feature/viewport/font differences are explicit below

## Executed verification

- 106 aggregate Node tests passed
- Renderer and Electron TypeScript checks and production Vite build passed
- Whitespace/diff checks passed
- Reference fixture's initial hash remained unchanged through navigation, selection, search and collapse checks before deliberate drag mutations
- Ctrl+K opened hidden search; searching only a grandchild retained its correct root section; clear/hide restored the reference layout
- Section collapse/reopen retained counts and hierarchy
- Real 38 px row handle drag moved a child subtree under a sibling; attempting to move that parent into its own descendant was rejected with the existing Chinese error; a valid drag restored the original parent relationship
- Selected-tag navigation showed the correct tag's workspace, category, color, task/project counts and timestamps from existing data
- Compact rows visually remained denser than comfortable rows; dark controls and metadata stayed readable
- In a separate 10,000-task fixture, the dense tag path scrolled to Task 09999 with Ctrl+End. Long Task 09951 remained ellipsized before dates/tag chips, and selecting the last task opened its inspector. Today navigation continued to show its existing list workflow
- Prior linear ID lookup, formatter cache, chunk mounting and hidden move-control optimizations remain in place; the same CPU benchmark still reports bounded initial rendering. These measurements are not GUI FPS or end-to-end input-latency claims

## Remaining limits / acceptance decision

- Full source-screen parity still includes unported functional controls listed above; adding fake controls would misrepresent their availability
- Exact same-viewport screenshots, persistent image files, pixel-diff scoring and browser-console inspection were not available in this native-only check
- macOS/Windows rendering and assistive-technology behavior remain unverified
- Timelines with very dense overlap and expanded large move selectors retain the earlier known scaling limits

The scoped project/tag style refinement is implemented and functionally checked. Full-application screenshot fidelity is not yet accepted because the material remaining feature and visual-verification gaps have not been resolved.

final result: blocked
