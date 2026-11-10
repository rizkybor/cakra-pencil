# Changelog

Every OCCA version with its new features, improvements and bug fixes. The same list lives in the HRIS back office
(License Manager › OCCA › Versions), where versions are published and tied to licenses.

## Versioning

OCCA uses semantic versioning, `MAJOR.MINOR.PATCH`:

| Change | Example | Contains | Lifetime licenses |
| --- | --- | --- | --- |
| Patch | 1.0.0 → 1.0.1 | Bug fixes | Included |
| Minor | 1.0 → 1.1 | New features and improvements | Included |
| Major | 1.x → 2.0 | A new major version | Paid upgrade (OCCA 1 keeps working) |

- Trial, Professional and Organization licenses get every version while they run.
- A Lifetime license covers one major version and all its updates (License Terms 2.3: "for the current major version
  and its updates"). The back office stores it per license (`updates_major`) and puts it in the signed license token;
  a newer major version asks for the upgrade instead of opening on the Lifetime plan.
- A release marked **critical** in the back office means older versions must update (e.g. a bug that can damage
  projects).
- Each entry below is `New`, `Improved` or `Fixed`, grouped by area.

## How to add a version

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`, the build) in Xcode.
2. Add the version at the top of this file.
3. Add the same version in HRIS (License Manager › OCCA › Versions) as a draft, then publish it on release day.

## 1.1.0 — Unreleased

New standards, indoor maps and cutting tools. Mac and iPad.

### Map making

- **New:** Cut areas with a rectangle, ellipse or drawn path anywhere in the shape: cut away a part, split it, or punch a hole in the middle (areas with holes are kept through edits, import and export).
- **New:** Cut lines with a drag box.
- **New:** Indoor maps: an "Indoor map" option for new projects with the ISInOM 6.7.3 symbol set (OCCA), the 1:700 base scale and indoor course symbols.
- **Improved:** ISOM 2017-2 and ISSprOM 2019-2 symbols reviewed against the specifications; corrected shapes, sizes and patterns (e.g. 115, 203.2, 208/209, 311, 313, 520, 524–529, 532, 709, 713).
- **Improved:** Colours follow IOF Printing and Colour Definitions Rev. 4: new CMYK values (brown, green, olive) and a separate colour order for ISOM and ISSprOM. Existing maps update their colours when opened.

### Course planning

- **New:** IOF Control Descriptions 2024: new and changed symbols (column G directions, Bend in column F, Canopy, Out of bounds area, Railway), classes per course, special instructions and finish routes. Older courses are converted when opened.
- **New:** Indoor control description symbols (pillar, toilet, shower, sink, table, cupboard, couch).
- **Improved:** Dashed distance rows in the description sheet are symmetric around the label.

### Files and export

- **Improved:** Export saves straight into Documents › OCCA › Exports (iPad: Files › On My iPad › OCCA; Mac: your Documents folder) with a File name field; a Saved screen shows the files with Show in Finder / Files and Share.
- **Improved:** A cleaner Export window for the map sheet and courses: the PDF is the default, other formats (raster, OOM .omap, DXF, IOF XML, PNG) are optional and folded away, and the longer explanations moved into ⓘ hints.
- **Improved:** Moving a start, control or finish shows a small see-through dot at its exact centre while dragging.
- **Improved:** GeoPDF exports use the official IOF CMYK colours; OOM .omap exports carry the same CMYK values.
- **Improved:** The course overprint in PDF follows the IOF rule: lower purple is placed in the colour order instead of multiply (the screen preview is unchanged).

## 1.0.0 — Unreleased

First release. Mac and iPad.

### Map making

- **New:** Georeferenced A4 map frame in UTM (WGS84): scales 1:1000-1:15000 in steps of 500, portrait or landscape, margins, corner snap, lock, unlock and reselect the area.
- **New:** Basemaps: Apple Maps Satellite, Hybrid and Standard as a saved HD image of the locked area or Live, your own GeoTIFF, one opacity control and Map data info.
- **New:** ISOM 2017-2 and ISSprOM 2019-2 symbol sets (Rev. 6) with the OCAD color hierarchy, area patterns and line decorations; import and export symbol sets (.occasym, OCAD .ocd, OOM .omap / .xmap).
- **New:** Vector tools like OCAD and OOM: bezier Pen, Freehand, Rectangle, Ellipse, Move Tool, Node Tool (sharp, smooth, smart points) and Measure Tool.
- **New:** Shape editing: follow object, auto-join, Join / Merge, fill area, cut line, split area, scale, parallel, reverse direction and precise Shift rotation.
- **New:** Multi-select with selection box, move, duplicate, delete and change the symbol of every selected object.
- **New:** Apple Pencil sketching with ISOM pen presets, stroke eraser, undo and redo.
- **New:** Contours from a DEM (built-in Terrain Tiles, GeoTIFF, ASCII Grid, GeoJSON) with interval, index and form lines; convert contours to map objects.
- **New:** North lines grid (grid or magnetic north), labeled scale bar and frame corners in UTM, decimal degrees and DMS.
- **New:** Symbol guide: the IOF omapwiki page of the active symbol in a side panel.

### Course planning

- **New:** Course Settings page: start, controls and finish, several courses sharing controls, automatic codes, lengths, climb, competitors and checks.
- **New:** Illustrated IOF 2018 control descriptions, course objects (text, shapes, images, IOF course symbols 702-715) and one-page race maps with an All controls master map.
- **New:** Import courses from OCCA projects, OCAD course setting files and OOM maps.

### Fieldwork

- **New:** Field panel: GPS position, field notes with photos and photo markup, position averaging, bearing and distance offset, quick vegetation notes and external GNSS receivers.
- **New:** Track recording on iPad Wi-Fi + Cellular, field mode with big buttons and touch lock, and a Ready check before going out.
- **New:** GPX import and export, track to line, survey coverage and a field report PDF.
- **New:** Field data between devices with .occafield files: only new tracks and notes are added, desk work is kept.

### Files and export

- **New:** .occa project files that open on both iPad and Mac (Files, Finder, AirDrop).
- **New:** Import OCAD 10-2018 (.ocd) and OOM (.omap / .xmap) maps into a project or as a new project.
- **New:** Export PNG / TIFF / JPEG with world file, georeferenced PDF, OOM .omap, DXF, IOF XML 3.0 and contours to Shapefile / KML / KMZ, optionally with the basemap underneath.

### App

- **New:** iPad and Mac with the same features and a layout for each device: touch and Apple Pencil on iPad, mouse, trackpad and keyboard shortcuts on Mac.
- **New:** Project list with previews, search and sort; splash screen; short guide for new users; light, dark or system appearance.

### License

- **New:** License keys from Jendela Cakra Digital: a Mac key (OC31-OC34) activates on a Mac and an iPad key (OC52-OC54) on an iPad; works offline for up to 30 days between checks.
- **New:** Starter on Mac (up to 3 projects at 1:4000 or 1:10000, up to 4 courses) and view-only projects on iPad without a license; a small STARTER / TRIAL label on Starter and Trial.
