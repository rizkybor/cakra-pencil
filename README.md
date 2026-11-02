# Cakra Pencil

Aplikasi iPad untuk membuat basemap orienteering ter-georeferensi: frame A4 di atas citra Apple Maps,
sketsa Apple Pencil dengan tebal garis dalam mm, export raster + world file yang langsung pas di OCAD/OOM.

PRD: https://claude.ai/artifact/AcTDDByDiSos6Z1mAgxBRy

## Status: fondasi G1

| Area | Sudah | Belum (berikutnya) |
| --- | --- | --- |
| Proyek (FR-1) | Proyek baru (nama, skala, dpi), CRS UTM otomatis, frame A4 Portrait/Landscape, geser frame, ganti skala live, margin, snap pojok, kunci/buka kunci, info frame, paket `.cakra` | Multi-sheet/A3, EPSG non-UTM (butuh PROJ) |
| Imagery (FR-2) | Apple Maps satelit/hybrid/standar | Import foto + world file, GeoTIFF, GCP |
| Sketsa (FR-3) | Pena tebal mm konstan, preset ISOM, penghapus stroke, undo/redo, Pencil gambar/jari navigasi, double-tap Pencil, ketuk 2/3 jari | Layer sketsa, penghapus piksel, lasso, engine Metal |
| Export (FR-6) | PNG/TIFF/JPEG 300/600/900 dpi + .pgw/.tfw/.jgw + .prj, cek sebelum export, Share Sheet | Render ber-strip via libtiff, vektor (DXF/SHP/GeoJSON/.omap), GPX, ZIP |
| Penyimpanan | JSON atomik + Data Protection, autosave debounce di background | SQLite + GRDB + R*Tree (PRD) |

Vektor (FR-4), survei lapangan (FR-5), RTK (FR-7), dan kontur (FR-8) belum dikerjakan.

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
