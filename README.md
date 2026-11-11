# OCCA — Orienteering Cakra CAD Application

<img src="docs/images/occa-story.jpg" alt="OCCA promotional image (portrait)" width="260" align="right">

An orienteering map CAD app for **iPad and Mac**: draw, edit, and print ISOM/ISSprOM maps on top of satellite
imagery or your own GeoTIFF basemap. Georeferenced map frame (UTM), IOF symbols from OCAD symbol sets with Color
Hierarchy, OCAD/OOM-style vector tools (bezier pen, Move/Node/Measure, follow object, merge), Apple Pencil sketching,
contours from a DEM, IOF Course Settings, and export to raster + world file, GeoPDF, OMAP, and `.occa` project
files that open on both iPad and Mac.

> Former names: Cakra Pencil, then COCA. The repo, Xcode target, Swift module, and bundle id (`id.cakrapencil.app`)
> are unchanged; old `.coca` and `.cpencil` files still open.

- **Release:** Coming soon — **unpublished**, not yet available on the App Store (current version 1.0.0; see [CHANGELOG.md](CHANGELOG.md)).
- **Supported:** iPad with **iPadOS 17 or later** (Apple Pencil optional) and Mac with **Apple silicon and macOS 14
  Sonoma or later** (via Mac Catalyst, "Optimize for Mac" interface). Features are the same on both devices; the
  layout adapts to the device (see [iPad and Mac](#ipad-and-mac)).
- **Not supported:** Windows, Android, and iPhone.
- **Compatible files:**
  - **OCAD 10, OCAD 12 … OCAD 2018** (`.ocd`): maps and course setting files (controls and courses) — tested with
    real OCAD 10 and OCAD 12 files.
  - **OOM — OpenOrienteering Mapper** (`.omap`, `.xmap`): maps, and start / control / finish symbols as controls.
  - **OCCA** (`.occa`) project files, **OCCA symbol sets** (`.occasym`, import and export), **GeoTIFF** basemaps.
  - Export: OOM `.omap`, DXF (for OCAD), IOF XML 3.0 courses, georeferenced PDF, PNG / TIFF / JPEG + world file.
- **License:** proprietary, © 2026 Rizky Ajie Kurniawan — see [LICENSE](LICENSE).

<br clear="right">

## Features

**Map making**
- Georeferenced A4 map frame in UTM (WGS84), scales 1:1000–1:15000 in steps of 500 (indoor maps 1:250–1:2000), lock/unlock
  and reselect the area.
- Basemaps: Apple Maps Satellite / Hybrid / Standard as a saved **HD image** of the locked area (fixed at every zoom)
  or **Live**, your own **GeoTIFF**, one opacity control, and Map data info.
- ISOM 2017-2 and ISSprOM 2019-2 symbols from OCAD symbol sets, drawn with the OCAD **Color Hierarchy**
  (e.g. 509.1 railway as a black line with white dashes).
- **Indoor maps:** OCCA's own **ISInOM 6.7.3** set (IOF indoor specification, 1:700): walls, doors, pillars, stairways
  up/down (red/blue), escalators, lifts, ramps, furniture, toilets/sinks, one-way and compulsory-crossing directions,
  floor designators and indoor course symbols. Switch on **Indoor map (ISInOM)** in New project (or later in the Map
  tab, or the **Indoor** button while selecting the area): the map then follows ISInOM — indoor scales 1:250–1:2000
  (default 1:700; larger scales such as 1:500 enlarge everything, smaller ones such as 1:1000 keep the 1:700 sizes),
  the ISInOM set is the default and wins over ISSprOM for shared codes (fences 516/518, water 301/302, 520, course
  701–715), course symbols use the ISInOM sizes (control ø6.0 mm at 1:700, not ISSprOM × 5.7), the description picker
  lists the indoor features first (7.119 Pillar, 7.132 Toilet, 7.133 Shower, 7.134 Sink, 7.141 Table or bench,
  7.142 Cupboard / shelf, 7.143 Couch / sofa), north lines stay optional (20 m apart if shown) and the Contours panel
  notes that indoor maps use 1201 Step lines instead. Switching it off returns to ISOM / ISSprOM from the scale; symbol
  objects are resized for the new standard (ISSprOM 1:700 ↔ ISInOM 1:700 = × 0.175 / × 5.71). Starter: the indoor
  scales are locked like the other scales outside 1:4000 / 1:10000.
- OCAD/OOM-style vector tools: bezier Pen, Freehand, Rectangle, Ellipse, Move Tool, Node Tool
  (Convert to Sharp / Smooth / Smart), Measure Tool, follow object, auto-join, **Join / Merge**, fill area,
  cut / split / scale / parallel, precise Shift-rotation.
- Apple Pencil sketching with ISOM pen presets; contours from a DEM (built-in Terrain Tiles, GeoTIFF, ASCII Grid,
  GeoJSON) with interval, index and form lines.
- North lines grid (grid or magnetic north) with quick show/hide (⇧⌘G), labeled scale bar, and frame corners in
  UTM, decimal degrees, and degrees-minutes-seconds.

**Course planning**
- Separate Course Settings page like Purple Pen: start / controls / finish, multiple courses sharing controls,
  automatic codes, lengths and climb, checks, illustrated IOF 2024 control descriptions, course objects
  (text, shapes, images), one-page race maps.

**Files and export**
- `.occa` project files that open on both iPad and Mac (Files, Finder, AirDrop).
- Import OCAD 10–2018 (.ocd) and OOM (.omap / .xmap) maps, and OCAD course setting files (controls and courses) —
  into a project, or straight from the project list as a new project.
- Export PNG / TIFF / JPEG + world file, georeferenced PDF (GeoPDF), OOM .omap, DXF, IOF XML 3.0, contours to
  Shapefile / KML / KMZ — optionally with the georeferenced basemap underneath. Back to OCAD: DXF for the map,
  IOF XML 3.0 for the courses (OCAD Course Setting import), raster + world file or GeoPDF as a background map.

**Two devices, one app**
- The same features on iPad (touch, Apple Pencil) and Mac (mouse, trackpad, keyboard shortcuts); the layout adapts
  to each device.

## Screenshots

| Mac — map workspace | iPad — map workspace |
| --- | --- |
| ![Map workspace on Mac with HD satellite basemap and the ISSprOM symbol panel](docs/images/mac-workspace.jpg) | ![Map workspace on iPad with HD satellite basemap and the Layers panel](docs/images/ipad-workspace.jpg) |

| Mac — Course Settings | Mac — Map tab (HD image / Live, map data info) |
| --- | --- |
| ![Course Planner on Mac with courses, controls, and legs](docs/images/mac-course-planner.jpg) | ![Map tab on Mac with basemap mode and HD image details](docs/images/mac-map-tab.jpg) |

## iPad and Mac

| | iPad | Mac (Mac Catalyst) |
| --- | --- | --- |
| Tools | Tool rail on the left (two columns on short screens), pen dock and object bar at the bottom | Toolbar band docked at the top: tools + map controls + pens in one row, object bar in the next row, compass in the right corner |
| Right panels | Floating panels | Docked full height on the right side |
| Sizes | 44 pt buttons, iPad font sizes | 36 pt buttons, smaller fonts (`CP.fs`) |
| Input | Touch, Apple Pencil (hover, double-tap), optional keyboard | Mouse/trackpad: two-finger scroll = pan the map, pinch / ⌘ + scroll = zoom, Shift for multi-select and precise rotation |
| Other | Compass follows the iPad's heading; leave the app with the usual iPadOS gesture (apps must not quit themselves) | No digital compass, hidden window title, minimum window size 1100 × 760, **Quit** button in the project list header (with confirmation; same as ⌘Q) |

Shared logic lives in `CakraCore` and the models; view branching uses `CP.isMac`.

## Status: G1 foundation

| Area | Done | Not yet (next) |
| --- | --- | --- |
| Project (FR-1) | New project (name, scale, dpi, **Indoor map (ISInOM)**), scales 1:1000–1:15000 in steps of 500 (indoor 1:250–1:2000), automatic UTM CRS, A4 Portrait/Landscape frame, live scale change, margins, corner snap, lock/unlock, frame info, `.cakra` package | Multi-sheet/A3, non-UTM EPSG (needs PROJ) |
| Splash screen | Every time OCCA opens (iPad and Mac, about 4 s; the pen stroke finishes at 3.5 s): warm paper background (dark in Dark Mode) with fading-in contour lines, the logo settling in, the name with an orange pen stroke drawing itself, the tagline, the version, and the "Supported by" Jendela Cakra Digital credit; then a fade to the project list | — |
| Home screen | Project cards with imagery + vector preview (projects whose area is not locked yet show a "No area selected" card without a photo), search, sort, rename, duplicate, save `.occa` file, **Open file** (`.occa` project, or an OCAD `.ocd` / OOM `.omap` `.xmap` map → **New project from map**: name, UTM zone — OCAD files don't store it, so the sheet checks it: a preview map with a pin at the map center, the place name from Apple geocoding (red warning when the center lands in the sea, plus a confirmation before Create), **Suggest zone** (tries neighboring zones until the map lands on land), and an automatic correction when the starting zone puts the map in the sea; OOM sets the zone from the file — then a project with its area locked on the map, objects and OCAD courses included), delete | Project folders/tags |
| View | Select area with a fixed frame in the center, map limited to the locked area, search with suggestions, two-finger rotation, zoom +/− (down to ±2 mm/pt), **Show whole map** button (⌘0: frame + all objects, sketches, and courses), zoom to frame, digital compass (follows the iPad's heading) — map controls merged into the left tool panel (two columns when a landscape screen is not tall enough), basemap opacity, north grid lines (grid/magnetic, spacing, color, opacity, width; settings in the Map tab → North line grid, quick show/hide with the north lines button in the map controls, ⇧⌘G, or the eye in Layers → Grid) | Field mode |
| Field (FR-5) | GPS position radar: accuracy circle, radar pulse, heading cone, accuracy badge, show/hide. **Field panel** (iPad and Mac, tab "Field"): field data stored in the project (`field.json`, photos in `field-photos/`, included in `.occa` files) — GPS tracks (dashed colored lines on the map, length · duration · accuracy) and field notes (category pins: boulder, cliff, water, vegetation, path, fence, building, control site, check again; done notes faded, averaged positions ringed); show/hide all or per track, zoom, rename, mark done / to do, delete; **GPX import** (GPS watches, phone apps: tracks, routes, waypoints) and **GPX export**. **Capture on iPad** (top of the Field panel; not on Mac): **Record track** (Battery saver / Normal / Detailed, keeps recording with the screen off, REC badge on the map with time · distance · points, pause/resume/stop), **Add note** (category, text, up to 4 photos from the camera or photo library resized to 2048 px, at the GPS position or the map center), **Average position** (stand still 10/20/30 s; fixes weighted by accuracy, jumps dropped, e.g. ±1.4 m from 34 fixes) and a GPS status line (Wi-Fi iPads have no GPS chip) **Ready check** (HD images of all three types for the area, contours, symbol sets, free storage, battery, location permission; **Download missing** while online) and **Field mode** (iPad: full-screen map, dark high-contrast header with exit · GPS · recording · battery, big buttons Record / Pause / Stop · Note · Average · Follow me · Lock; touch lock opened by holding 1 s; screen kept on). Pause/resume starts a new **segment** in the same track (the paused stretch is a gap on the map, not counted in length or time; GPX keeps one `<trkseg>` per segment). **Process notes** (iPad and Mac): tap a note in the list or its pin on the map (Navigate tool, or field mode) to open it — editable category and text, photos, time, UTM + lat/lon position, GPS/averaging accuracy, camera direction (also a wedge on the map pin); icon actions **Make map object** (symbols suggested for the note's category, e.g. 204 Boulder; a point symbol is placed at the note in one undo step and the note is marked done and linked, a line/area symbol is picked to draw from the note), Show map object, Zoom, Done / To do, Delete; **photo viewer** (full screen, swipe or ← →, pinch / double-tap zoom, share); filter All / To do / Done. **Stage 2:** **bearing + distance offset** for new notes (typed or compass bearing, meters or paces with pace calibration over 100 m; true bearing corrected for UTM grid convergence; the standing position is kept with the note); **quick vegetation** (iPad, also in field mode: tap ISOM/ISSprOM runnability class 401–410 at the GPS position or map center — a draft note whose area symbol is suggested first in Make map object); **external GNSS** (Bluetooth/Lightning receivers feed Core Location: status shows "External GNSS ±x m", Ready check lists the position source); **track → line** (track menu › Make line object: path symbol suggested, From/To trim highlighted on the map, smoothing Off/Light/Medium/Strong, split at pauses; one undo step, then node edit, cut and merge as usual); **survey coverage** (blue band ±10/25/50/100 m along the tracks, % of the map frame walked); **field report PDF** (GPX menu: summary, satellite overview with frame, tracks and numbered notes, every note with details and photos; plain background when offline). **Field data between devices** (`.occafield`, Data menu in the Field panel, the same on iPad and Mac): **Export field data** — all, or only what is new since the last export — tracks, notes and photos without the drawing; **Import field data** into the open project — new tracks and notes are added, nothing already there is duplicated, desk work is kept (renamed tracks, done notes, map object links), a track that came back longer gets its new points, another device's "Track 1" becomes "Track 1 (2)", data from another UTM zone is moved into the project's zone; summary such as "1 new track, 3 new notes · 2 already in the project". Move the whole project (with the drawing) once with `.occa`, then each survey day with `.occafield`. **Photos on existing notes:** Upload photo… from files on Mac (or from Photos), Take photo / Add photo on iPad, remove from the photo's menu (max 4 per note). **Track recording only on iPad Wi-Fi + Cellular** (GPS chip, detected by its cellular modem): on Wi-Fi-only iPads and on the Mac the recorder, its mode menu and the Record / Pause / Stop buttons (also in field mode) are not shown; notes, averaging and vegetation remain **Photo markup** (iPad and Mac): draw on a note photo with Apple Pencil, finger or mouse (PencilKit tools; red pen to start), saved as a separate drawing next to the photo (`<photo>.drawing`, the photo is unchanged), shown in thumbnails, the photo viewer and the field report, and carried in .occa / .occafield files. **Sketch notes** (iPad and Mac): **Draw** (Field panel capture row and field mode on iPad, Draw sketch note in the Field panel on Mac) draws freehand strokes on the map with a finger, Apple Pencil or the mouse while two fingers (or the trackpad) still pan and zoom; a bar offers Undo stroke, Clear, Cancel and Done; Done opens the note editor (category, text, up to 4 photos, sketch preview) and saves one note whose pin sits on the drawing. Sketches are drawn on the map as solid lines in the note's colour (done notes faded, never printed), marked with a scribble in the list, shown in the note detail (preview, Redraw; Add sketch on notes without one), Zoom fits the sketch, and **Make map object** turns the sketch into line objects (one per stroke) or one area with symbols suggested for the category (areas first for a closed loop; one undo step, note marked done and linked); carried in field.json, .occafield (a redrawn sketch replaces an older one on import), the field report PDF (overview and the note's own box with a scale bar) and moved with the data between UTM zones. **Show / hide field items** (iPad and Mac): an eye on every track and note row, a section eye for all tracks / all listed notes (dimmed with a dash when some are hidden), and **Select** (Mac: also ⌘-click / ⇧-click a row) with Show / Hide for the selected rows; hidden items are not drawn or tappable on the map and the survey coverage counts only visible tracks; the field report, GPX and .occafield exports include everything; visibility is saved in field.json and kept on import (older files with "hide all tracks/notes" open with those items hidden). | — |
| Imagery (FR-2) | Apple Maps satellite/hybrid/standard, GeoTIFF image basemap (see the row below), one opacity control for the active basemap, **Map data info** | Import photo + world file, GCPs |
| HD image (locked area) | Once the area is locked, Satellite, Hybrid, and Standard are each downloaded once as a georeferenced HD image of the frame + 5% margin (MKMapSnapshotter, ~0.25 m/px, longest side ≤ 4096 px, Web Mercator bounds) — current type first. The workspace then shows the fixed image instead of the live Apple map, so roads and buildings keep their size at every zoom; switching type uses the saved image. Live map while downloading or offline; **Download again** in the Map tab. **Basemap mode** in the Map tab keeps the two separate: **HD image** (default, the saved image) or **Live** (real-time Apple Maps for checking current conditions while online; saved per project); HD images keep downloading in Live mode, so exports can still include the basemap. Stored in the package under `imagery/` as a per-device cache (not in `.occa` files) | Imagery capture date (not provided by MapKit) |
| Sketch (FR-3) | Pencil with constant mm width, ISOM color presets (shown/hidden with the palette button in the pen dock; hidden by default, remembered per device), stroke eraser, undo/redo, Pencil draws / finger navigates, Pencil double-tap, two/three-finger tap | Pixel eraser, lasso, Metal engine |
| Vector (FR-4) | Bezier pen tool (double-tap = finish, continue a line from its end), freehand, Rectangle, Ellipse, snap to points of other objects, Node Tool (A): edit points/handles, drag the segment between two points = bend that segment (end points stay put, corners stay corners); active point → Convert to Sharp / Smooth / Smart (smart = automatic handles that adjust when the point or its neighbors move; double-tap a point = sharp ↔ smooth), rotation 0–360°, Layers panel (show/hide, lock, order, rename, duplicate, delete) | Editing several points at once |
| Symbols (FR-4.2) | Symbol set library from OCCA `.occasym`, OCAD .ocd and OpenOrienteering Mapper .omap / .xmap. **Default: OCCA's own ISOM 2017-2 (1:15000) and ISSprOM 2019-2 (1:4000) sets**, written from the IOF specifications (Rev. 6, 2024: codes, names, sizes, CMYK colors, color order; area patterns and line decorations stored per symbol) and saved as `.occasym` (JSON); plus OCCA's **ISInOM 6.7.3 indoor set (1:700)** — 91 symbols with the specification's codes, CMYK colors and color order (walls 1102/1103, stairways 1206/1207, spiral stairs 1208–1211, escalators, lift, ramps, furniture 1401–1404, water 1302–1305, directions 1771–1775, floor/building designators, course 701–715 and 1703), never picked from the scale alone (indoor maps are large-scale like sprint maps) but the default on maps with **Indoor map (ISInOM)** on, and selectable in the set menu on any map; it is enlarged on maps larger than 1:700 and keeps its 1:700 sizes on smaller scales. The symbol groups shown as filter chips follow the set (ISInOM adds 11 Construction, 12 Floors, 13 Water, 14 Furniture, 17 Directions) — any set can be **exported** as `.occasym` (with its enabled/disabled choices) from the set menu and **imported** on another iPad/Mac (Import in the set menu, or open the file from Files / Finder / AirDrop). Other built-in sets: ISSprOM 2019-2 (British Orienteering, OCAD), and from OpenOrienteering Mapper ISOM 2017-2 1:10000, ISSprOM 2019 1:4000, and Course design 1:4000 / 1:10000 (course symbols 701–799). The set for the map is chosen automatically (same scale, then the same IOF standard — e.g. the ISOM 1:10000 set is sized to 67% on a 1:15000 map; switch sets in the Symbols panel menu), enable/disable per set and per symbol, list/6-column grid, point/line/area symbols with the matching tool, IOF widths (double lines, dashes, caps; e.g. 509.1 railway: black line with white dashes), solid area fill like OCAD/OOM, change an object's symbol (point ↔ point, line ↔ area; one object or every object with the same symbol) **ISOM/ISSprOM patterns and decorations** are drawn on the map, in raster/PDF export and in the symbol swatches: area patterns (marsh lines, good-visibility lines, scattered-tree holes, cultivated/orchard dots, vineyard lines, boulder-field triangles, out-of-bounds hatching; pattern-only areas are transparent and on by default) and line decorations (cliff and earth-bank tags on the right of the drawing direction, wall dots, pairs of dots (515) and half dots offset from the centre line (105.2 / 513.2), fence tags, marks centred on dashes (106 / 514 / 517), chevrons and pairs of chevrons (528 / 529), one-sided bridge ticks (ISOM 512), rows of triangles without a main line (ISSprOM 512.1), pylon bars, stairway steps, transparent double lines (215, 509.2, 511, 532, 710.2), pointed ends (107)); dashed and staggered pattern lines (310, 414), random scalene boulder triangles (208 / 209, the same on every redraw), jittered dot patterns, 4-value dash patterns (507 pairs of dashes, map lines and course objects), point symbols painted per element in the colour order (417 / 419 masks don't hide contours or the course). **2026-11 review** against the Rev 6 PDFs (precise definitions ISOM p.39–40, ISSprOM p.30–31): shapes 111/112/115/203/203.2/303/311/312/313/519/524–527/602/702/712/713 with their centres of gravity, tag lengths 104/201/202/516/518/528/529, 510 bars, 215/511 widths, 507/106/514/517 dashes, 114/212 densities, 520 solid olive green, 709 cross-hatch, names 105.2/506/511/526/529; ISSprOM 104.1 removed (not in the spec). Existing maps are updated on open (`OccaSymbolMigration`: old OCCA colours → Rev 4 colours, renamed symbols, changed line styles and point shapes; custom colours kept). Patterns are read from .omap (hatch/dot patterns) and OCAD 11+ .ocd (area hatch, dot structures) sets and written to .omap exports. | OCAD line primary/secondary symbols in .ocd sets; project thumbnails are simplified (no patterns/decorations); 107 tapers linearly; 511 bars / 532 step spacing / 710.2 ends are figure-based (the spec gives no value) |
| IOF map standards | Follows **ISOM 2017-2** (forest, base 1:15000) and **ISSprOM 2019-2** (sprint, base 1:4000), Revision 6 (January 2024), chosen by the map scale (≤ 1:5000 = sprint). **ISInOM 6.7.3** (indoor, base 1:700; enlarged only, never reduced) applies when the project's **Indoor map (ISInOM)** option is on (`SheetSpec.standardOverride`): its symbol set, course symbol sizes (the ISSprOM sizes from the 1:700 base), indoor scales and north line defaults. Enlarged maps enlarge everything proportionally (1:10000 = 150%, 1:3000 = 133%). Course symbols: control circle ø5.0 / ø6.0 mm, start triangle 6.0 / 7.0 mm, finish ø4/6 / ø5/7 mm, line 0.35 mm, control numbers Arial 4.0 mm; the purple course overprint follows the IOF colour order (IOF Printing and Colour Definitions Rev 4 §4): in PNG/TIFF/JPEG and PDF exports lower-purple symbols (701, 703–706, 708, 710, 712, 713, 715; ISOM 704) are painted below black, blue and brown 100 % and upper-purple symbols (702, 707, 709, 711, 710.2, 714 and ISSprOM 704) on top, without multiply blending; on screen the course is a separate layer drawn with multiply so the detail under it stays readable while planning. Contour interval presets per standard: ISOM 5 m (2.5 m only in flat terrain, with a hint), ISSprOM 2 / 2.5 m (5 m in steep areas). Contours 0.14 / 0.25 mm (ISOM) or 0.21 / 0.30 mm (ISSprOM), form lines thinner and dashed (2.0/0.2 or 3.0/0.3 mm); magnetic north line defaults 300 m / blue 0.12 mm (ISOM) or 120 m / blue 0.18 mm (ISSprOM) | North lines are not yet rotated with the map to magnetic north |
| Symbol guide | A 📖 **Symbol guide** button on the active symbol bar, on each row of the Symbols panel (and its grid menu), and on the selected-object bar (⇧⌘/ toggles it): a side panel next to the map shows the IOF omapwiki page for that symbol — **ISSprOM 2019-2** for sprint scales (≤ 1:5000), **ISOM 2017-2** otherwise (switchable) — opening the symbol's own detail page, with the code highlighted, match count and next/previous, a search field for any other code (e.g. 520 or 509.1), and a **Safari** link to the full page. While open it follows the active symbol automatically; offline it shows the symbol's basics from the symbol set | Needs an internet connection (the omapwiki pages are not stored offline) |
| Contours (FR-8) | Built-in contours (AWS Terrain Tiles, stored in the project for offline use), upload a DEM GeoTIFF/ASCII Grid or GeoJSON contour lines, interval/index/form line/smoothing/display panel, interval warning, relief info, opacity up/down, convert to vector objects, included in export (101.0/102.0/103.0), export contours only to Shapefile/KML/KMZ | Elevation labels, hillshade |
| Merge, follow object, fill area | Like OCAD/OOM: a line end placed on the end of a line with the same symbol, and an area whose side is placed on an area with the same symbol, merge right away (always on, no button); a **Join** button for lines (gap ≤ 2 mm on paper) and **Merge** for areas (touching/overlapping) appears at the front of the bar when objects with the same symbol meet, and when several objects are selected (⌘J; merges only with other selected objects). **Follow object** (always on, no button): a first tap then a second tap on the same object = its shape is followed, across kinds (a line symbol follows lines or areas, an area symbol follows areas or lines; closed lines are followed along the shortest side like areas; a line lying exactly on an area edge counts as the same object); the cursor snaps to object edges in every drawing tool (pen, freehand, rectangle/ellipse, point symbol); two consecutive pen taps on the same object copy the shape between them (including up to the object's end; overlapping lines are not merged), returning to the start point with a line symbol = a closed line (not an area), freehand along an object follows its shape; guides show during Apple Pencil hover. **Fill area**: the selected line is filled with a new area symbol below it, the line stays. Merging keeps the holes of the merged areas, and areas that close a ring (also snapped automatically) get the gap as a **hole**; overlapping areas are united on their exact bezier outlines (curves kept) | Only when the exact outlines can't be resolved does a merge fall back to straight points |
| Multi-select & duplicate | Move Tool (V): tap = select a whole object (no points), drag = move, **rotation handle** above the selected object (drag = rotate around its center; **Shift** = precise: a straight side snaps parallel/perpendicular to a straight line of a nearby object or grid north, within 4°, the reference side is highlighted; otherwise 15° steps), double-tap a selected object = enter Node Tool; click and drag on empty space = selection box (replaces the selection; pan with two fingers or the Navigate tool), tap empty space = deselect all; Shift + tap / Shift + box = add to selection, ⌘A = select all (no button). Selected objects move together, **Duplicate** (⌘D: copy 3 mm on paper to the lower right, right above the original, selected immediately) and **Delete N objects** — each one undo step | Point/shape editing, symbol change, and rotation work on one object only; locked/hidden objects are not included in the selection box |
| Pan the view | Navigate tool (H): one-finger drag/click-drag; in every tool: two fingers, **trackpad/mouse scroll**, trackpad pinch = zoom at the cursor, **⌘ + scroll** = zoom | Trackpad scroll/pinch not covered by automated tests (iOS XCUITest cannot send scroll events); direction checked manually on Mac |
| Save & open project files | **Save file** (⌘S in the map workspace top bar, or the project card menu) → one `.occa` file with the whole project (objects, sketches, courses + their images, contours, DEM, preview; LZFSE). **Open file** (⌘O in the project list), or open an `.occa` (or old `.coca` / `.cpencil`) from Files / Finder / AirDrop. The format is the same on iPad and Mac, so a file from one device can be imported on the other. Existing projects are never overwritten: same id → an "(imported)" copy | No automatic sync (iCloud) yet; files are saved/moved manually |
| Reselect area | Map tab → **Reselect area**: the old area is kept (also in the project file); while the new area is not locked, the basemap/imagery stays visible and **Cancel** (Esc) restores the previous area, scale, orientation, margins, and snap and locks it again | — |
| Image basemap (GeoTIFF) | During **Select map area**: the **Skip — upload basemap** button → choose a GeoTIFF, the UTM zone is taken from the image, the frame (chosen scale/orientation) is centered on the image, the area is locked right away, and the image becomes the basemap. Or at any time in the **Map** tab → **Import GeoTIFF basemap…**: georeferenced imagery/maps (GeoTIFF tags; UTM WGS84 any zone or WGS84 lat/lon) show in the map workspace below the objects. While it is in use (**Use**), the Satellite/Hybrid/Standard picker is disabled and Apple imagery is hidden (except while selecting an area); Opacity + Hide/30/60/100% apply to the active basemap; zoom to image, replace, delete. An image that does not touch the frame → offer to **Move frame to image** (undoable). The file is copied into the project package (included in .occa files and duplicates). Large images: a ≤ 2048 px version when zoomed out, full resolution when zoomed in | Rotated GeoTIFFs (ModelTransformation), world files (.tfw), and CRSs other than UTM/WGS84 are not supported; the area outside the frame is masked like satellite imagery |
| Measure Tool | Measure tool (R): drag from point to point → ground distance (m), length on paper (mm at map scale), and grid azimuth; ends snap to point symbols, corners, and object edges. Esc / Clear measurement = clear | UTM grid azimuth (not corrected for magnetic declination); one straight segment, no polyline yet |
| Color Hierarchy (Symbol Layering) | Color stacking follows the color table of the symbol set: OCCA's ISOM and ISSprOM sets use the **IOF Printing and Colour Definitions Rev 4** table exactly — its CMYK values (brown 25/75/100/0, green 80/0/100/0, olive green 38/27/100/0, purple 50 % 18/43/0/0…) and a separate order per standard with the table's roles (blue point / line / area, brown point / line, whites for railway, two-level stripes, over green and brown, over yellow; brown 50 % road infill vs paved; black road outline above the screens; dark green line vs area). Both sets number their colours by the row of that one table, so they layer together; areas drawn only by a pattern (marsh, boulder fields, 709) sit at their pattern colour's level. Symbols of other sets (OCAD, OOM) are matched to the nearest row of the map's standard by kind (edges → road outline). Colors higher in the table automatically cover colors below, regardless of drawing order — e.g. black over blue, contours over lakes, marsh over green, road fill over its black edges. Applies on the map, PNG/TIFF/JPEG export, GeoPDF, and .omap (color order = OOM priority); tapping an object selects the one visible on top. Objects of the same color follow the Layers panel order; sketches without a symbol sit above everything | The Layers panel order only matters among objects of the same color; on the map, generated/imported contours are drawn above all objects (export already uses the correct color order); older imported symbol sets must be re-imported to pick up their color order |
| Tooltips | Every icon button (tool panel, object bar, pen dock, top bar, Course/Layers/Contours panels) shows its name and keyboard shortcut when the mouse/trackpad pointer hovers over it | On touch screens without a pointer tooltips do not show (names are still read by VoiceOver) |
| Shape editing (OCAD) | Reshape: move/delete points, corner ↔ smooth, **add point** (double-tap on the selected object's line, the curve shape stays). **Edit shape** menu: **Cut line** (tap a point = cut in two; drag a box = the parts of the line inside it are removed, cut exactly at the box edge, curves stay curves, closed lines open up, works on a rotated map) / **Split area** (tap two points on the edge, or pick a tool in the prompt or press its key: a **rectangle**, **ellipse** or closed **pen** path cuts that part away — drawn anywhere: completely inside the area it punches a **hole**, over a hole it enlarges it, across the edge and a hole it opens the hole to the outside, over a whole hole it absorbs it ("The shape is inside a hole." when nothing filled is touched); an open **pen** or **freehand** path splits the area along it (holes go to the piece they lie in, a path through a hole splits it); every piece becomes its own area with the same symbol, keeps its holes, and all pieces are selected; one undo step). **Areas with holes**: filled with the even-odd rule, patterns clipped around the holes, a tap in a hole doesn't hit the area, hole edges are snap/follow edges, the selection outline shows every hole; Node Tool edits hole points like outer points (move, handles, add/delete point, sharp/smooth/smart; a hole left with fewer than 3 points disappears) and **Remove hole** appears when a hole point is active; moving, rotating (also Shift precise), scaling, duplicating, Parallel (inward = smaller area with larger holes, a hole that shrinks away is dropped) and undo carry the holes; the Layers row says "1 hole", **Scale** (10–400% slider or buttons, line width unchanged), **Parallel** (copy/move parallel to the left, right, or both sides; areas: inside/outside), **Reverse line direction**; Rotation stays on the Rotate button, Join via the Join button | A path that crosses itself inside the area can't split it; a split path must cut a piece off (a path from the edge into a hole only is refused); tapping two edge points splits along the outer edge only; switching an area with holes to a line symbol keeps only its outer ring; parallel offsets of sharp curves use a simple miter |
| Course planner | A separate Course page (Course button in the workspace) like Purple Pen, with **Import course** (top bar and the Courses list): controls and courses from an `.occa` project (descriptions kept, positions converted to this project's zone), an OCAD course setting `.ocd` (OCAD 10–11 control strings and OCAD 12+ control object strings; map exchanges are skipped), or the start/control/finish symbols (701/702/706) of an OOM `.omap`/`.xmap` (OOM has no course order; controls get free codes). When the imported controls lie outside the locked map area (a course file made for another map), a dialog gives the distance and direction and offers **Undo import** or **Keep**, and those courses are marked "Outside the map area"; the background is only the drawn map (no imagery) with map intensity, import OCAD/OOM maps (.ocd, .omap, .xmap) as background, Start/Control/Finish rail, Courses · Controls · Descriptions · Report panels. Course names can be typed directly on the course card. The organizer name is printed centered below the event name in the descriptions. Multiple courses (ordered/score) share controls and start/finish, automatic codes 31–255 (skipping ambiguous codes) + renumber, drag to move, reorder, length + legs, climb, competitors, load per control and shared legs, checks, illustrated IOF 2024 descriptions with columns A–H (symbols C–H, thick lines after C and F, 8 directions for the column G side/edge/part/corner/tip/end/foot symbols, bend in column F; optional classes line, climb rounded to 5 m, 5–7 mm boxes; optional 14.1 distance to the start triangle, 15.1–15.6 special instruction rows between controls (taped routes, mandatory crossing point / passage, map exchange, map flip) with thick lines on both sides, 16.1/16.2/16.3 finish rows; projects saved with the 2018 numbering are converted when opened; text style option; black or purple like the controls; symbol icons in the picker), IOF standard symbol sizes that can be changed (globally and per control), PDF preview before export, one-page race map (descriptions in a chosen corner or a free position dragged on the map thumbnail, row limit per column: extra rows move to the next column; separate description page option), **Objects** tab: text (multi-line, font size in mm/pt, bold, italic), rectangle/ellipse (optional transparent purple fill), lines, and JPG/PNG images (max 10 MB, 8000 px, 10 images; downscaled to 2000 px; PNG transparency kept) that can be dragged, any color (quick colors + color picker), shown on all courses or selected courses, included in PDF and PNG; **All controls** (master: control codes, no legs) can be previewed and exported as PDF/PNG with control descriptions sorted by code, IOF XML 3.0 export + race map PDF + PNG with world file **IOF course symbols** as course objects (Objects tab › IOF course symbols): 702 map issue point, 707 marked route (dashed), 708 out-of-bounds boundary, 709 out-of-bounds area (hatched rectangle + boundary), 710 crossing point, 711 out-of-bounds route (crosses), 712 first aid, 713 refreshment, 715 map exchange — shapes from OCCA's course symbols, sized per ISOM/ISSprOM and enlarged with the map. Course lines stop 0.3 mm before the circles (705). | Description sheet inside the map, crossing points/forbidden areas, variations (butterfly/forking), relays |
| Guide | Short guide for new users (6 pages: welcome, start a project, draw, fieldwork on iPad, iPad ⇄ Mac with `.occa` once and `.occafield` per survey day, process and share), with notes for this device (Mac: no GPS; Wi-Fi-only iPad: no track recorder). Opens by itself once per device on first launch (no account: stored on the device), any time from **Guide** on the project list or **Help › OCCA Guide** (⌘?) | — |
| Import | OCAD 10–2018 (.ocd) and OOM (.omap/.xmap): lines + areas with curves and **area holes** (OCAD hole-flagged parts, OOM hole points), georeferencing, colors, symbol codes, dashes. **OCAD course setting files** (.ocd with courses) go straight into Course Settings: start / controls / finish at their positions and every course in order (Import in Layers, or Import Course on the Course Settings page) | OOM point objects, text, extra parts of line objects; OCAD control descriptions (OCAD's own numbering) are not converted |
| Export (FR-6) | PNG/TIFF/JPEG 300/600/900 dpi + .pgw/.tfw/.jgw + .prj, .omap (original bezier curves, area holes as OOM hole parts) and DXF R12 (an area's outer ring and each hole as separate closed polylines on the symbol's layer), georeferenced vector PDF (Geospatial PDF; map symbols and the course in **DeviceCMYK** with the IOF CMYK × screen of each colour role, RGB only for sketches, north lines, basemaps and images), .omap colours with the IOF CMYK and dash groups (507), raster in sRGB (the spec defines no RGB), grid included in export (601.0), pre-export check. **Georeferenced PDF is the default** on every plan (map sheet and course exports); raster, OMAP, DXF, IOF XML and course PNG are optional under **Other formats** (collapsed, off by default). A **File name** field (default: project + scale) names every file; files are saved straight into the device's Documents (iPad: Files › On My iPad › OCCA › Exports; Mac: `~/Documents/OCCA/Exports`, allowed by a home-relative sandbox exception for direct distribution) without overwriting (a taken name gets " 2", " 3"… for the whole set), then a **Saved** screen lists them with Show in Finder / Files and Share… **Include basemap** (off by default; map sheet and course exports): the basemap in use (HD Apple Maps image or GeoTIFF) georeferenced under the map in PNG/TIFF/JPEG and PDF at the current opacity, with an "Imagery © Apple Maps" credit for Apple imagery; OMAP/DXF get `<name>_basemap.jpg` + .jgw + .prj, and the .omap references it as a georeferenced image template behind the map | Striped rendering via libtiff, Shapefile, GeoJSON, GPX, ZIP; open tests in OOM 0.9.x and OCAD |
| Storage | Atomic JSON + Data Protection, debounced background autosave | SQLite + GRDB + R*Tree |

Symbol codes in export: objects drawn with a symbol (or imported from OCAD) carry their original ISOM code,
e.g. `101.0 Contour` in .omap and layer `101_0_CONTOUR` in DXF. Pencil sketches and objects without a symbol use the
neutral code `990.x` per color + width.

RTK (FR-7) is not started yet.

Tool shortcuts: H navigate, V Move Tool, A Node Tool, R Measure Tool, N pencil, E eraser, T point symbol,
P pen tool, F freehand, M rectangle, L ellipse. In the pen tool: Return = finish line, Delete = remove the last
point, Esc = cancel.

Command shortcuts: ⌘Z / ⇧⌘Z undo/redo, ⌘A select all, ⌘D duplicate, ⌘J join/merge, ⌘0 whole map,
⌘= / ⌘− zoom, ⇧⌘G north lines, ⌘S save `.occa` file, ⌘E export, ⌘K Course Settings; in the project list ⌘N new project, ⌘O open file.

## Structure

```
CakraPencil.xcodeproj         App target "OCCA" (iPadOS 17 + Mac Catalyst), synchronized folders (no manual file list)
Config/CakraPencil-Info.plist .occa project file type (UTI id.cakrapencil.project), merged with Xcode's generated Info.plist
CakraPencil/                  SwiftUI + UIKit (Swift module still "CakraPencil")
  App/                        Entry point, Mac window, debug snapshot
  DesignSystem/Tokens.swift   Color, spacing, per-device font/button size tokens, button styles
  Projects/                   Project list, new project, About (credits), .cakra repository, .occa files
  Workspace/                  Workspace model, MKMapView + frame + Pencil ink + vector layer, panels, Course Planner
  Symbols/                    Symbol set library (.ocd) and symbol panel
  Export/                     Export sheet
  Resources/SymbolSets/       Built-in ISSprOM 2019-2 symbol set (.ocd)
  CakraPencilMac.entitlements Mac sandbox (network, user-selected files, location)
CakraPencilUITests/           XCUITest (iPad simulator)
Packages/CakraCore/           Pure logic (iOS + macOS), tested with `swift test`
  Geodesy/                    UTM WGS84 (Krüger series), zones, .prj WKT
  Sheet/                      Paper/ground/pixel sizes, north-up frame, snap, scale presets
  Georef/                     World files
  Sketch/                     Strokes (mm), ISOM pen presets
  Vector/                     Bezier objects, symbols, merge, follow object, shape editing, Color Hierarchy, precise rotation, measure
  Contour/                    DEM (GeoTIFF/ASCII Grid/Terrain Tiles), contour generation, contour export
  Course/                     Course Planner, overprint, IOF descriptions, IOF XML
  Import/                     OCAD (.ocd) and OOM (.omap/.xmap) readers
  Export/                     Raster, GeoPDF, OMAP/DXF
  Project/                    Project model, .cakra package, .occa files, GeoTIFF basemap
  Support/                    Number formatting, app identity (AppInfo)
Tools/                        Logo generator script
docs/images/                  README images (promo, screenshots)
```

## Running

```sh
# Core tests (UTM, frame size table, world files, export roundtrip ≤ 1 px, 900 dpi export budget)
cd Packages/CakraCore && swift test

# App: open in Xcode, pick an iPad simulator / physical iPad, or "My Mac (Mac Catalyst)", then Run
open CakraPencil.xcodeproj

# Build for Mac (Release) and install to /Applications/OCCA.app (signed "Sign to Run Locally")
xcodebuild build -project CakraPencil.xcodeproj -scheme CakraPencil -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath .build/mac
ditto .build/mac/Build/Products/Release-maccatalyst/OCCA.app /Applications/OCCA.app
```

This Mac build only runs on the Mac that built it. Other Macs need a Developer ID + notarization (Apple Developer
Program); for the Mac App Store, the sandbox is already set up in `CakraPencilMac.entitlements`.

The simulator has no Apple Pencil. Turn on the hand button in the pen dock so one finger draws too.

DEBUG builds accept launch arguments for screenshots/UI tests, including: `-cp-open-first`, `-cp-open-project <name>`,
`-cp-inspector-tab <Layers|Symbols|Contours|Map>`, `-cp-use-symbol <number>`, `-cp-select-first`, `-cp-open-course`,
`-cp-reselect-area`, `-cp-import-basemap <file>`, `-cp-skip-area-basemap <file>`, `-cp-save-file <name>`,
`-cp-import-file <file>`, `-cp-force-shift`, `-cp-guide-audit` (checks every OCCA symbol against the Symbol Guide's
ISOM / ISSprOM omapwiki pages with the guide's own search and writes Documents/guide-audit.txt, then quits), and
`-cp-snapshot <name>` (saves a window image to the app's Documents —
used to check the Mac layout without screen recording permission; UI tests on Mac need signing with a Team).

UI tests (XCUITest, target `CakraPencilUITests`, iPad simulator): project deletion, contours-only export, OCAD/OOM-like
drawing, symbol change, rotation (including Shift + precise rotation), multi-select + duplicate, Move/Node/Measure Tool,
Convert to Sharp/Smooth/Smart, merging (Join/Merge), follow object across kinds, Color Hierarchy, and the course
planner. Some tests use the "Uji Vektor" test project on the simulator.

```sh
xcodebuild test -project CakraPencil.xcodeproj -scheme CakraPencil \
  -destination 'platform=iOS Simulator,name=iPad Air (5th generation)' -only-testing:CakraPencilUITests
```

Performance test: run the app with `-cp-open-project "Uji Performa" -cp-perf` (Debug build, or Release with
`SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG` for numbers like the installed app). The app adds 600 strokes + 200 objects,
measures rotation, pan, zoom, drag, and contour recalculation, then Course Settings (60 controls + 6 courses):
overprint, load, checks, race map PDF, IOF XML, the Course page (rotate/pan/zoom, drag a control, panel changes).
Results go to `Documents/perf.txt`; course data is restored at the end (back up the test project if you don't want
strokes/objects added). Options: `-cp-course-tab Report` (panel tab), `-cp-course-no-panel` (no panel).

Latest results (iPad Air simulator, Release, 10 Nov 2026; test project with 1,800 strokes and 600 objects after the
run): pan, zoom, object drag and the whole Course page at 60 fps without hitches; map rotation about 50 fps with this
heavy test data (the same as before the license and version updates); race map PDF with 625 objects in 30–57 ms;
IOF XML about 1.3 ms; opening the Course page 0.2–0.3 s; memory about 150 MB (peak 195 MB), unchanged.

## Credits

<img src="docs/images/occa-hero.jpg" alt="OCCA promotional image (landscape)" width="480" align="right">

- Developed by **Rizky Ajie Kurniawan**.
- Supported by **PT. Jendela Cakra Digital** — [jcdigital.co.id](https://jcdigital.co.id).

Built-in symbol sets:

| Symbol set | Source | License |
| --- | --- | --- |
| ISOM 2017-2 (1:15000) and ISSprOM 2019-2 (1:4000) · OCCA — default | Made for OCCA from the IOF specifications (`.occasym`) | Part of OCCA (proprietary) |
| ISInOM 6.7.3 (1:700) · OCCA | Made for OCCA from the IOF indoor specification ISInOM v6.7.3 (`.occasym`) | Part of OCCA (proprietary); the specification is CC BY 4.0 |
| ISSprOM 2019-2 (OCAD, 1:4000) | British Orienteering — BOF O-Map 4000 O12 v1 | Published by British Orienteering for orienteering mapping |
| ISOM 2017-2 (1:10000), ISSprOM 2019 (1:4000), Course design (1:4000, 1:10000) | [OpenOrienteering Mapper](https://github.com/OpenOrienteering/mapper/tree/master/symbol%20sets) — © OpenOrienteering Mapper contributors | [GPL-3.0](CakraPencil/Resources/SymbolSets/OpenOrienteering/LICENSE-GPL-3.0.txt); included unmodified as data files |

ISOM 2017-2, ISSprOM 2019-2 and ISInOM 6.7.3 are specifications of the International Orienteering Federation (IOF);
ISInOM is published by the IOF Map Commission under CC BY 4.0.

The in-app **About OCCA** screen (ⓘ in the project list, or tap the credit footer) shows the same credits with the
company logo, the release status and supported platforms, **Size and storage** (app size, projects, symbol library,
caches and temporary files on this device), plus the symbol set credits, licenses and third-party data notices.

<br clear="right">

## Plans and license keys

| Plan | Category | Key | Features |
|---|---|---|---|
| **Starter** (Mac only) | Individual | none (free) | up to 3 projects at 1:4000 or 1:10000 (one A4 sheet each), up to 4 courses, no fieldwork (field mode, notes, tracks), contours, images on course maps, live basemap, or my location; PDF with a small "Made with OCCA · Starter" credit. iPad has no free plan: without a key, projects open view-only and export to PDF |
| **Trial** | Individual | term key (e.g. 14 or 30 days) | every feature until it ends |
| **Professional** | Individual | paid key per period (e.g. 6 months, 1 year) | every feature |
| **Lifetime** | Individual | one-time payment, no end date | every feature |
| **Organization** | Organization | one key for a team, community, club, or federation | every feature, more devices |

Keys are created in the Jendela Cakra Digital back office (HRIS › License Manager): plan, end date or lifetime, active /
inactive, and a device limit per key. Full list: `internal/business/OCCA-Daftar-Lisensi-dan-Fitur.pdf`.

- Key format: `OC{platform}{plan}-XXXX-XXXX-XXXX-{number}`, e.g. `OC32-7KQM-2XRT-9HZP-0001`. Platform 3 Mac, 5 iPad;
  plan 1 Trial, 2 Professional, 3 Lifetime, 4 Organization (Mac 31-34, iPad 52-54: no Trial on iPad). A Mac key
  only activates on a Mac and an iPad key only on an iPad (the app flags a wrong-platform key before sending it, and
  drops a token signed for the other platform). The back office can make a Mac + iPad pair for one buyer. Each
  platform numbers its keys separately; the number is also the certificate reference `LIC-OCCA-MAC-0001` /
  `LIC-OCCA-IPAD-0001`.
  Always 20 characters (5 groups of 4): the back office keeps the number at 4 digits (up to 9999 per product and platform) and
  the key field stops at 20. The field adds the dashes as you type or paste,
  hides the key like a password (eye button to show it), and Activate needs all 20 characters.
- The License screen links the **OCCA License Terms** (`CakraPencil/License/LicenseTerms.md`, a copy of the back
  office's `resources/license-products/terms/occa.md` — keep both on the same version).
- Tap the plan chip (STARTER, TRIAL, PROFESSIONAL, …) in the project list to open **License**: enter a key, **Check now**, or
  **Release this device** (frees the seat for another device).
- Activation needs the internet once (`POST https://api.jcdigital.co.id/api/licenses/occa/activate`). The server
  answers with a token signed with Ed25519; OCCA checks the signature with the public key built into
  `LicenseManager`, so it works offline. It refreshes about weekly; a key switched off or expired in the back office
  falls back to Starter, and after 30 days without a check OCCA asks to go online once. A key **replaced after a plan
  change** (`key_replaced`: same number, new plan code) or a released one-per-device key (`key_used`) also signs the
  device out; OCCA shows the server's message and opens the License screen for the new key.
- Projects are never locked: on Starter they still open and export to PDF.
- Developer builds (Debug, or Release with `OCCA_DEV`) are Lifetime, with **Simulate Starter plan** on the License
  screen. Debug launch arguments: `-cp-license starter|trial|professional|lifetime|organization|key`,
  `-cp-license-api <url>`. Builds for other people (the DMG)
  must not have `OCCA_DEV`.
- `LicenseUITests.testActivateAndReleaseLicenseKey` runs the full key flow against a local back office API:
  set `TEST_RUNNER_OCCA_TEST_KEY` (and `TEST_RUNNER_OCCA_LICENSE_API`, default `http://127.0.0.1:8765`); it's
  skipped otherwise.

## Versions and updates

Every version, with its new features, improvements and bug fixes, is in [CHANGELOG.md](CHANGELOG.md) (semantic
versioning: patch = fixes, minor = features, major = new major version). The same list is kept in HRIS (License
Manager › OCCA › Versions), where each version is published together with its Mac installer (`.dmg`, stored for
later download). Trial, Professional and Organization licenses get every version; a Lifetime license covers one
major version and its updates (`updates_major` in the signed token), so OCCA 2 asks a Lifetime 1.x key for the
upgrade. The app sends its version on every license check, and HRIS logs version changes per device
(`app_updated`).

## Mac installer (.dmg)

`Tools/make-dmg.sh` builds `build/release/OCCA-<version>.dmg` for clients: archived with the hardened runtime,
exported and signed with **Developer ID**, packed with an Applications shortcut, notarized by Apple and stapled. It
prints the size and SHA-256 (HRIS shows the same SHA-256 after the upload). Upload the file in HRIS › License Manager ›
OCCA › Versions, then publish the version.

One-time setup on the Mac that builds releases:

1. Xcode › Settings › Accounts › Manage Certificates › + › **Developer ID Application** (Account Holder or an Admin
   with Developer ID access).
2. `xcrun notarytool store-credentials occa-notary --apple-id <Apple ID> --team-id <TEAM_ID>` (asks for an
   app-specific password from appleid.apple.com and keeps it in the Keychain).

Options: `--no-notarize` (signed only, quick check) and `--local` (ad-hoc, tests the packaging on this Mac only; never
for clients). Keep the bundle ID `id.cakrapencil.app` and the team the same in every release; otherwise macOS treats
it as another app and the projects and license on the client's Mac are not found.

## License

Proprietary — © 2026 Rizky Ajie Kurniawan. All rights reserved. This code and app may not be used, copied, modified,
or shared without written permission. Third-party data and components (BOF ISSprOM symbol set, OpenOrienteering Mapper symbol sets under GPL-3.0, Apple Maps imagery,
Terrain Tiles elevation data) are subject to their own terms. See [LICENSE](LICENSE).
