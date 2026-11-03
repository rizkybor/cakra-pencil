# Cakra Pencil

Aplikasi iPad untuk membuat basemap orienteering ter-georeferensi: frame A4 di atas citra Apple Maps,
sketsa Apple Pencil dengan tebal garis dalam mm, export raster + world file yang langsung pas di OCAD/OOM.

PRD: https://claude.ai/artifact/AcTDDByDiSos6Z1mAgxBRy

## Status: fondasi G1

| Area | Sudah | Belum (berikutnya) |
| --- | --- | --- |
| Proyek (FR-1) | Proyek baru (nama, skala, dpi), CRS UTM otomatis, frame A4 Portrait/Landscape, ganti skala live, margin, snap pojok, kunci/buka kunci, info frame, paket `.cakra` | Multi-sheet/A3, EPSG non-UTM (butuh PROJ) |
| Halaman utama | Kartu proyek dengan pratinjau citra + vektor, cari, urutkan, ganti nama, duplikat, bagikan, hapus | Folder/tag proyek |
| Tampilan | Pilih area dengan frame tetap di tengah, peta dibatasi ke area terkunci, pencarian dengan saran, rotasi 2 jari, zoom +/− (sampai ±2 mm/pt), kompas digital (ikut arah hadap iPad), opacity basemap, grid garis utara (grid/magnetik, jarak, warna, opacity, tebal) | Mode Lapangan |
| Lapangan (FR-5) | Radar posisi GPS: lingkar akurasi, denyut radar, kerucut arah pandang, badge akurasi, tampil/sembunyi | Rekam track GPX, catatan foto, averaging |
| Imagery (FR-2) | Apple Maps satelit/hybrid/standar | Import foto + world file, GeoTIFF, GCP, export citra |
| Sketsa (FR-3) | Pensil tebal mm konstan, preset ISOM, penghapus stroke, undo/redo, Pencil gambar/jari navigasi, double-tap Pencil, ketuk 2/3 jari | Penghapus piksel, lasso, engine Metal |
| Vektor (FR-4) | Pen tool bezier, Rectangle, Ellipse, Pilih & edit titik/handle (sudut ↔ halus), panel layer (tampil/sembunyi, kunci, urutan, ganti nama, duplikat, hapus) | Snapping, split/join, reverse |
| Simbol (FR-4.2) | Pustaka set simbol dari .ocd (ISOM 2017-2, ISSprOM 2019-2, sekolah), aktif/nonaktif per set dan per simbol, menggambar dengan simbol | Simbol titik, pola area |
| Import | OCAD 11–2018 (.ocd): garis + area dengan kurva, georeferensi, warna, kode simbol | Objek titik, teks, lubang area; .omap/.xmap |
| Export (FR-6) | PNG/TIFF/JPEG 300/600/900 dpi + .pgw/.tfw/.jgw + .prj, .omap (kurva bezier asli) dan DXF R12, PDF vektor ter-georeferensi (Geospatial PDF), grid ikut export (601.0), cek sebelum export, Share Sheet | Render ber-strip via libtiff, Shapefile, GeoJSON, GPX, ZIP; uji buka di OOM 0.9.x dan OCAD |
| Penyimpanan | JSON atomik + Data Protection, autosave debounce di background | SQLite + GRDB + R*Tree (PRD) |

Kode simbol di export: objek yang digambar dengan simbol (atau diimpor dari OCAD) membawa kode ISOM aslinya,
mis. `101.0 Contour` di .omap dan layer `101_0_CONTOUR` di DXF. Sketsa pensil dan objek tanpa simbol memakai kode
netral `990.x` per warna + tebal. Contoh hasil export ada di [samples/](samples/).

RTK (FR-7) dan kontur (FR-8) belum dikerjakan.

Shortcut alat: H navigasi, A pilih, N pensil, E penghapus, P pen tool, M rectangle, L ellipse.
Di pen tool: Return = selesai garis, Delete = hapus titik terakhir, Esc = batal.

## Struktur

```
CakraPencil.xcodeproj         Target app iPadOS 17 (folder tersinkron, tanpa daftar file manual)
CakraPencil/                  SwiftUI + UIKit
  DesignSystem/Tokens.swift   Token warna pastel, spacing, radius, gaya tombol
  Projects/                   Daftar proyek, proyek baru, repositori .cakra
  Workspace/                  Model workspace, MKMapView + frame + tinta Pencil, panel
  Export/                     Export sheet
Packages/CakraCore/           Logika murni, dites di macOS
  Geodesy/                    UTM WGS84 (deret Krüger), zona, WKT .prj
  Sheet/                      Ukuran kertas/tanah/piksel, frame north-up, snap
  Georef/                     World file
  Sketch/                     Stroke (mm), preset pena ISOM
  Export/                     Raster exporter + cek export
  Project/                    Model proyek, paket .cakra
```

## Menjalankan

```sh
# Tes core (UTM, tabel ukuran frame PRD, world file, roundtrip export ≤ 1 px, budget export 900 dpi)
cd Packages/CakraCore && swift test

# App: buka di Xcode, pilih simulator iPad atau iPad fisik, Run
open CakraPencil.xcodeproj
```

Di simulator tidak ada Apple Pencil. Nyalakan tombol tangan di dock pena supaya satu jari ikut menggambar.

Build DEBUG menerima argumen launch `-cp-open-first` untuk membuka proyek terbaru (screenshot/UI test).
