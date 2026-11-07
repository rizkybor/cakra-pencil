# COCA — Cakra Orienteering CAD Application

Aplikasi CAD peta orienteering untuk **iPad dan Mac**: gambar, edit, dan cetak peta ISOM/ISSprOM di atas
citra satelit atau basemap GeoTIFF sendiri. Frame peta ter-georeferensi (UTM), simbol IOF dari set OCAD
dengan Color Hierarchy, alat vektor ala OCAD/OOM (pen bezier, Move/Node/Measure, ikuti objek, gabung),
sketsa Apple Pencil, kontur dari DEM, Course Planner IOF, serta export raster + world file, GeoPDF, OMAP,
dan file proyek `.coca` yang bisa dibuka di iPad maupun Mac.

> Nama lama: Cakra Pencil. Repo, target Xcode, modul Swift, dan bundle id (`id.cakrapencil.app`) tetap;
> file `.cpencil` lama tetap bisa dibuka.

- **Platform:** iPadOS 17+ (iPad, Apple Pencil) dan macOS 14+ lewat **Mac Catalyst** (antarmuka "Optimize for Mac").
  Fiturnya sama di kedua device; tata letak menyesuaikan device (lihat [iPad dan Mac](#ipad-dan-mac)).
- **Lisensi:** proprietary, © 2026 Rizky Ajie Kurniawan — lihat [LICENSE](LICENSE).

## iPad dan Mac

| | iPad | Mac (Mac Catalyst) |
| --- | --- | --- |
| Alat | Rail alat di kiri (dua kolom bila layar pendek), dock pena dan bar objek di bawah | Pita toolbar menempel di atas: alat + kontrol peta + pena satu baris, bar objek di baris berikutnya, kompas di pojok kanan |
| Panel kanan | Panel melayang | Menempel penuh di sisi kanan |
| Ukuran | Tombol 44 pt, huruf ukuran iPad | Tombol 36 pt, huruf lebih kecil (`CP.fs`) |
| Input | Sentuh, Apple Pencil (hover, double-tap), keyboard opsional | Mouse/trackpad: geser 2 jari = geser peta, pinch / ⌘ + scroll = zoom, Shift untuk pilih banyak dan rotasi presisi |
| Lain-lain | Kompas mengikuti arah hadap iPad | Tanpa kompas digital, judul jendela tersembunyi, ukuran jendela minimum 1100 × 760 |

Logika bersama ada di `CakraCore` dan model; percabangan tampilan memakai `CP.isMac`.

## Status: fondasi G1

| Area | Sudah | Belum (berikutnya) |
| --- | --- | --- |
| Proyek (FR-1) | Proyek baru (nama, skala, dpi), skala 1:1000–1:15000 berjenjang 500, CRS UTM otomatis, frame A4 Portrait/Landscape, ganti skala live, margin, snap pojok, kunci/buka kunci, info frame, paket `.cakra` | Multi-sheet/A3, EPSG non-UTM (butuh PROJ) |
| Halaman utama | Kartu proyek dengan pratinjau citra + vektor (proyek yang belum dikunci areanya: kartu "Area belum dipilih", tanpa foto), cari, urutkan, ganti nama, duplikat, simpan file `.coca`, buka file, hapus | Folder/tag proyek |
| Tampilan | Pilih area dengan frame tetap di tengah, peta dibatasi ke area terkunci, pencarian dengan saran, rotasi 2 jari, zoom +/− (sampai ±2 mm/pt), tombol **Lihat seluruh peta** (⌘0: frame + semua objek, sketsa, dan lintasan), zoom ke frame, kompas digital (ikut arah hadap iPad) — kontrol peta menyatu di panel tools kiri (dua kolom bila layar landscape tidak cukup tinggi), opacity basemap, grid garis utara (grid/magnetik, jarak, warna, opacity, tebal) | Mode Lapangan |
| Lapangan (FR-5) | Radar posisi GPS: lingkar akurasi, denyut radar, kerucut arah pandang, badge akurasi, tampil/sembunyi | Rekam track GPX, catatan foto, averaging |
| Imagery (FR-2) | Apple Maps satelit/hybrid/standar, basemap gambar GeoTIFF (lihat baris di bawah), satu kontrol opacity untuk basemap yang sedang dipakai | Import foto + world file, GCP, export citra |
| Sketsa (FR-3) | Pensil tebal mm konstan, preset ISOM, penghapus stroke, undo/redo, Pencil gambar/jari navigasi, double-tap Pencil, ketuk 2/3 jari | Penghapus piksel, lasso, engine Metal |
| Vektor (FR-4) | Pen tool bezier (ketuk dua kali = selesai, lanjutkan garis dari ujungnya), gambar bebas, Rectangle, Ellipse, snap ke titik objek lain, Node Tool (A): edit titik/handle, tarik garis di antara dua titik = lengkungkan segmen itu (titik ujung diam, sudut tetap sudut); titik aktif → Convert to Sharp / Smooth / Smart (smart = handle otomatis yang ikut menyesuaikan saat titik atau tetangganya digeser; ketuk dua kali titik = sharp ↔ smooth), rotasi 0–360°, panel layer (tampil/sembunyi, kunci, urutan, ganti nama, duplikat, hapus) | Edit banyak titik sekaligus |
| Simbol (FR-4.2) | Pustaka set simbol dari .ocd (ISOM 2017-2, ISSprOM 2019-2, sekolah; set ISSprOM bawaan), aktif/nonaktif per set dan per simbol, daftar/grid 6 kolom, simbol titik/garis/area dengan alat yang sesuai, tebal IOF (garis ganda, putus-putus, ujung), area isi penuh seperti OCAD/OOM, ganti simbol objek (titik ↔ titik, garis ↔ area; satu objek atau semua objek bersimbol sama) | Pola arsir area, simbol bersambung (pagar, tebing) |
| Kontur (FR-8) | Kontur bawaan (AWS Terrain Tiles, disimpan di proyek untuk offline), upload DEM GeoTIFF/ASCII Grid atau garis kontur GeoJSON, panel interval/indeks/form line/smoothing/tampilan, peringatan interval, info relief, opacity naik/turun, jadikan objek vektor, ikut export (101.0/102.0/103.0), export kontur saja ke Shapefile/KML/KMZ | Label elevasi, hillshade |
| Gabung, ikuti objek, isi area | Seperti OCAD/OOM: ujung garis yang ditempel ke ujung garis bersimbol sama dan area yang sisinya ditempel ke area bersimbol sama langsung digabung (selalu aktif, tanpa tombol); tombol **Join** untuk garis (celah ≤ 2 mm di kertas) dan **Gabungkan** untuk area (bersentuhan/tumpang tindih) muncul di depan bar saat objek bersimbol sama bertemu, juga saat beberapa objek dipilih (⌘J; hanya digabung dengan sesama objek terpilih). **Ikuti objek** (selalu aktif, tanpa tombol): ketuk pertama lalu ketuk kedua di objek yang sama = bentuknya diikuti, lintas jenis (simbol garis mengikuti garis atau area, simbol area mengikuti area atau garis; garis tertutup diikuti lewat sisi terpendek seperti area; garis yang menumpuk tepat di tepi area dianggap objek yang sama); kursor menempel ke garis tepi objek yang ada di semua alat gambar (pen, gambar bebas, rectangle/ellipse, simbol titik); pen tool yang diketuk dua kali berurutan di objek yang sama menyalin bentuk di antaranya (termasuk sampai ujung objek; garis yang menumpuk tidak ikut digabung), kembali ke titik awal dengan simbol garis = garis tertutup (bukan area), gambar bebas yang menyusuri objek mengikuti bentuknya; panduan tampil saat Apple Pencil hover. **Isi area**: garis terpilih diisi simbol area baru di bawahnya, garisnya tetap | Area berlubang (hasil gabung yang membentuk cincin hanya menyimpan tepi luar); area tumpang tindih yang digabung kehilangan kurva bezier |
| Pilih banyak & duplikat | Move Tool (V): ketuk = pilih objek utuh (tanpa titik), tarik = pindah, **pegangan rotasi** di atas objek terpilih (tarik = putar di titik tengahnya; **Shift** = presisi: sisi lurus menempel sejajar/tegak lurus ke garis lurus objek lain di dekatnya atau utara grid, dalam 4°, sisi acuan disorot; selain itu kelipatan 15°), ketuk dua kali objek terpilih = masuk Node Tool; klik lalu tarik di tempat kosong = kotak pilih (ganti pilihan; geser peta dengan dua jari atau alat Navigasi), ketuk kosong = lepas semua; Shift + ketuk / Shift + kotak = tambah ke pilihan, ⌘A = pilih semua (tanpa tombol). Objek terpilih digeser bersama, **Duplikat** (⌘D: salinan 3 mm di kertas ke kanan bawah, tepat di atas aslinya, langsung terpilih) dan **Hapus N objek** — masing-masing satu langkah undo | Edit titik/bentuk, ganti simbol, dan rotasi hanya untuk satu objek; objek terkunci/tersembunyi tidak ikut kotak pilih |
| Geser view | Alat Navigasi (H): tarik satu jari/klik-tarik; di semua alat: dua jari, **scroll trackpad/mouse** (arah seperti scroll di Mac), pinch trackpad = zoom di titik kursor, **⌘ + scroll** = zoom | Scroll/pinch trackpad belum teruji otomatis (XCUITest iOS tidak bisa mengirim scroll); arah dicek manual di Mac |
| Simpan & buka file proyek | **Simpan file** (⌘S di bar atas peta kerja, atau menu kartu proyek) → satu file `.coca` berisi seluruh proyek (objek, sketsa, lintasan + gambarnya, kontur, DEM, pratinjau; LZFSE). **Buka file** (⌘O di daftar proyek), atau buka `.coca` (atau `.cpencil` lama) dari Files / Finder / AirDrop. Format sama di iPad dan Mac, jadi file dari satu device bisa diimpor di device lain. Proyek yang sudah ada tidak ditimpa: id sama → salinan "(impor)" | Belum ada sinkronisasi otomatis (iCloud); file disimpan/dipindah manual |
| Pilih ulang area | Tab Peta → **Pilih ulang area**: area lama disimpan (juga di file proyek); selama area baru belum dikunci, basemap/citra tetap tampil dan tombol **Batal** (Esc) mengembalikan area, skala, orientasi, margin, dan snap sebelumnya lalu mengunci lagi | — |
| Basemap gambar (GeoTIFF) | Saat **Pilih area peta**: tombol **Lewati — upload basemap** → pilih GeoTIFF, zona UTM diambil dari gambar, frame (skala/orientasi terpilih) di tengah gambar, area langsung dikunci, gambar jadi basemap. Atau kapan saja di tab **Peta** → **Import basemap GeoTIFF…**: citra/peta yang sudah di-georeferensi (tag GeoTIFF; UTM WGS84 zona mana pun atau WGS84 lat/lon) tampil di peta kerja di bawah objek. Saat dipakai (**Pakai**), pilihan Satelit/Hybrid/Standar nonaktif dan citra Apple disembunyikan (kecuali saat pilih area); Opacity + Sembunyikan/30/60/100% berlaku untuk basemap yang sedang dipakai; zoom ke gambar, ganti, hapus. Gambar yang tidak menyentuh frame → tawaran **Pindahkan frame ke gambar** (bisa di-undo). Berkas disalin ke paket proyek (ikut file .coca dan duplikat). Gambar besar: versi ≤ 2048 px saat zoom jauh, resolusi penuh saat zoom dekat | Belum ikut export; GeoTIFF terputar (ModelTransformation), world file (.tfw) dan CRS selain UTM/WGS84 belum didukung; area di luar frame tertutup seperti citra satelit |
| Measure Tool | Alat Ukur (R): tarik dari titik ke titik → jarak lapangan (m), panjang di kertas (mm pada skala peta), dan azimut grid; ujung menempel ke simbol titik, sudut, dan tepi objek. Esc / Hapus ukuran = hapus | Azimut grid UTM (belum dikoreksi deklinasi magnetik); satu segmen lurus, belum polyline |
| Color Hierarchy (Symbol Layering) | Tumpukan warna mengikuti urutan Color Table OCAD dari set simbol (bawaan: ISSprOM 2019-2): warna yang lebih atas di tabel otomatis menimpa warna di bawahnya, apa pun urutan menggambarnya — mis. hitam di atas biru, biru di atas cokelat, cokelat (kontur) di atas hijau dan kuning, isi jalan di atas tepi hitamnya. Berlaku di peta, export PNG/TIFF/JPEG, GeoPDF, dan .omap (urutan warna = priority OOM); ketuk objek memilih yang terlihat paling atas. Objek berwarna sama mengikuti urutan panel Layer; sketsa tanpa simbol di atas semua | Urutan panel Layer hanya berpengaruh di antara objek berwarna sama; di peta kontur hasil generate/impor digambar di atas semua objek (export sudah tepat urutan warnanya); set simbol impor lama perlu diimpor ulang agar ikut urutan warnanya |
| Tooltip | Semua tombol ikon (panel tools, bar objek, dock pena, bar atas, panel Course/Layer/Kontur) menampilkan nama dan pintasan keyboardnya saat kursor mouse/trackpad diarahkan | Di layar sentuh tanpa pointer tooltip tidak tampil (nama tetap dibacakan VoiceOver) |
| Edit bentuk (OCAD) | Reshape: geser/hapus titik, sudut ↔ halus, **tambah titik** (ketuk dua kali di garis objek terpilih, bentuk kurva tetap). Menu **Edit bentuk**: **Potong garis** (ketuk satu titik) / **Belah area** (ketuk dua titik di tepi), **Skala** (slider 10–400% atau tombol, tebal garis tetap), **Paralel** (salin/geser sejajar ke kiri, kanan, atau kedua sisi; area: dalam/luar), **Balik arah garis**; Rotasi tetap di tombol Rotasi, Join lewat tombol Join | Potong area dengan garis bebas (baru garis lurus antar dua titik); offset paralel kurva tajam memakai miter sederhana |
| Course planner | Halaman Course tersendiri (tombol Course di workspace) seperti Purple Pen: latar hanya peta hasil gambar (tanpa citra) dengan intensitas peta, import peta OCAD/OOM (.ocd, .omap, .xmap) sebagai latar, rail Start/Kontrol/Finish, panel Lintasan · Kontrol · Deskripsi · Laporan. Nama lintasan bisa diketik langsung di kartu lintasan. Nama penyelenggara dicetak rata tengah di bawah nama acara pada deskripsi. Banyak lintasan (urutan/score) berbagi kontrol dan start/finish, kode otomatis 31–255 (lewati kode ambigu) + nomori ulang, tarik untuk memindah, atur urutan, panjang + leg, tanjakan, peserta, beban per kontrol dan leg bersama, pemeriksaan, deskripsi IOF 2018 bergambar kolom A–H (simbol C–H, garis tebal setelah C dan F, baris finish navigasi; opsi gaya teks; warna hitam atau ungu seperti kontrol; ikon simbol di pemilih), ukuran simbol standar IOF yang bisa diubah (global dan per kontrol), pratinjau PDF sebelum export, peta lomba satu halaman (deskripsi di pojok pilihan atau posisi bebas yang ditarik di miniatur peta, batas baris per kolom: baris berlebih pindah ke kolom di sampingnya; opsi halaman deskripsi terpisah), tab **Objek**: teks (multi-baris, ukuran huruf mm/pt, tebal, miring), persegi/ellipse (opsional isi ungu transparan), garis, dan gambar JPG/PNG (maks. 10 MB, 8000 px, 10 gambar; diperkecil ke 2000 px; PNG transparan tetap) yang bisa ditarik, warna bebas (warna cepat + pemilih warna), tampil di semua lintasan atau beberapa lintasan pilihan, ikut ke PDF dan PNG; **Semua kontrol** (master: kode kontrol, tanpa leg) bisa dipratinjau dan di-export sebagai PDF/PNG beserta deskripsi kontrol urut kode, export IOF XML 3.0 + PDF peta lomba + PNG ber-world file | Lembar deskripsi di dalam peta, titik penyeberangan/area terlarang, variasi (butterfly/forking), relay |
| Import | OCAD 11–2018 (.ocd) dan OOM (.omap/.xmap): garis + area dengan kurva, georeferensi, warna, kode simbol, putus-putus | Objek titik OOM, teks, lubang area |
| Export (FR-6) | PNG/TIFF/JPEG 300/600/900 dpi + .pgw/.tfw/.jgw + .prj, .omap (kurva bezier asli) dan DXF R12, PDF vektor ter-georeferensi (Geospatial PDF), grid ikut export (601.0), cek sebelum export, Share Sheet | Render ber-strip via libtiff, Shapefile, GeoJSON, GPX, ZIP; uji buka di OOM 0.9.x dan OCAD |
| Penyimpanan | JSON atomik + Data Protection, autosave debounce di background | SQLite + GRDB + R*Tree |

Kode simbol di export: objek yang digambar dengan simbol (atau diimpor dari OCAD) membawa kode ISOM aslinya,
mis. `101.0 Contour` di .omap dan layer `101_0_CONTOUR` di DXF. Sketsa pensil dan objek tanpa simbol memakai kode
netral `990.x` per warna + tebal.

RTK (FR-7) belum dikerjakan.

Shortcut alat: H navigasi, V Move Tool, A Node Tool, R Measure Tool, N pensil, E penghapus, T simbol titik,
P pen tool, F gambar bebas, M rectangle, L ellipse. Di pen tool: Return = selesai garis, Delete = hapus titik
terakhir, Esc = batal.

Shortcut perintah: ⌘Z / ⇧⌘Z undo/redo, ⌘A pilih semua, ⌘D duplikat, ⌘J join/gabungkan, ⌘0 seluruh peta,
⌘= / ⌘− zoom, ⌘S simpan file `.coca`, ⌘E export, ⌘K Course Planner; di daftar proyek ⌘N proyek baru, ⌘O buka file.

## Struktur

```
CakraPencil.xcodeproj         Target app "COCA" (iPadOS 17 + Mac Catalyst), folder tersinkron (tanpa daftar file manual)
Config/CakraPencil-Info.plist Tipe file proyek .coca (UTI id.cakrapencil.project), digabung dengan Info.plist hasil Xcode
CakraPencil/                  SwiftUI + UIKit (modul Swift tetap "CakraPencil")
  App/                        Entry point, jendela Mac, snapshot debug
  DesignSystem/Tokens.swift   Token warna, spacing, ukuran huruf/tombol per device, gaya tombol
  Projects/                   Daftar proyek, proyek baru, repositori .cakra, file .coca
  Workspace/                  Model workspace, MKMapView + frame + tinta Pencil + lapisan vektor, panel, Course Planner
  Symbols/                    Pustaka set simbol (.ocd) dan panel simbol
  Export/                     Export sheet
  Resources/SymbolSets/       Set simbol ISSprOM 2019-2 bawaan (.ocd)
  CakraPencilMac.entitlements Sandbox Mac (jaringan, file pilihan user, lokasi)
CakraPencilUITests/           XCUITest (iPad simulator)
Packages/CakraCore/           Logika murni (iOS + macOS), dites dengan `swift test`
  Geodesy/                    UTM WGS84 (deret Krüger), zona, WKT .prj
  Sheet/                      Ukuran kertas/tanah/piksel, frame north-up, snap, preset skala
  Georef/                     World file
  Sketch/                     Stroke (mm), preset pena ISOM
  Vector/                     Objek bezier, simbol, gabung, ikuti objek, edit bentuk, Color Hierarchy, rotasi presisi, ukur
  Contour/                    DEM (GeoTIFF/ASCII Grid/Terrain Tiles), generate kontur, export kontur
  Course/                     Course Planner, overprint, deskripsi IOF, IOF XML
  Import/                     Pembaca OCAD (.ocd) dan OOM (.omap/.xmap)
  Export/                     Raster, GeoPDF, OMAP/DXF
  Project/                    Model proyek, paket .cakra, file .coca, basemap GeoTIFF
  Support/                    Format angka Indonesia, identitas aplikasi (AppInfo)
Tools/                        Skrip pembuat logo
```

## Menjalankan

```sh
# Tes core (UTM, tabel ukuran frame, world file, roundtrip export ≤ 1 px, budget export 900 dpi)
cd Packages/CakraCore && swift test

# App: buka di Xcode, pilih simulator iPad / iPad fisik, atau "My Mac (Mac Catalyst)", lalu Run
open CakraPencil.xcodeproj

# Build Mac (Release) dan pasang di /Applications/COCA.app (ditandatangani "Sign to Run Locally")
xcodebuild build -project CakraPencil.xcodeproj -scheme CakraPencil -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath .build/mac
ditto .build/mac/Build/Products/Release-maccatalyst/COCA.app /Applications/COCA.app
```

Build Mac ini hanya jalan di Mac yang membangunnya. Untuk Mac lain perlu Developer ID + notarisasi (Apple Developer
Program); untuk Mac App Store sandbox sudah disiapkan di `CakraPencilMac.entitlements`.

Di simulator tidak ada Apple Pencil. Nyalakan tombol tangan di dock pena supaya satu jari ikut menggambar.

Build DEBUG menerima argumen launch untuk screenshot/UI test, antara lain: `-cp-open-first`, `-cp-open-project <nama>`,
`-cp-inspector-tab <Layer|Simbol|Kontur|Peta>`, `-cp-use-symbol <nomor>`, `-cp-select-first`, `-cp-open-course`,
`-cp-reselect-area`, `-cp-import-basemap <file>`, `-cp-skip-area-basemap <file>`, `-cp-save-file <nama>`,
`-cp-import-file <file>`, `-cp-force-shift`, dan `-cp-snapshot <nama>` (simpan gambar jendela ke Documents app —
dipakai untuk memeriksa tata letak Mac tanpa izin rekam layar; UI test di Mac butuh signing dengan Team).

UI test (XCUITest, target `CakraPencilUITests`, iPad simulator): hapus proyek, export kontur saja, menggambar mirip
OCAD/OOM, ganti simbol, rotasi (termasuk Shift + putar presisi), pilih banyak + duplikat, Move/Node/Measure Tool,
Convert to Sharp/Smooth/Smart, gabung (Join/Gabungkan), ikuti objek lintas jenis, Color Hierarchy, dan course planner.
Sebagian tes memakai proyek uji "Uji Vektor" di simulator.

```sh
xcodebuild test -project CakraPencil.xcodeproj -scheme CakraPencil \
  -destination 'platform=iOS Simulator,name=iPad Air (5th generation)' -only-testing:CakraPencilUITests
```

Uji performa: jalankan app dengan `-cp-open-project "Uji Performa" -cp-perf` (build Debug, atau Release dengan
`SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG` agar angkanya seperti app terpasang). App menambah 600 stroke + 200 objek,
mengukur rotasi, pan, zoom, drag, dan hitung ulang kontur, lalu Course Planner (60 kontrol + 6 lintasan): overprint,
beban, pemeriksaan, PDF peta lomba, IOF XML, halaman Course (rotasi/pan/zoom, tarik kontrol, ubah panel). Hasil di
`Documents/perf.txt`; data lintasan dikembalikan di akhir (backup proyek uji bila tidak ingin stroke/objek bertambah).
Opsi: `-cp-course-tab Laporan` (tab panel), `-cp-course-no-panel` (tanpa panel).

Hasil terakhir (simulator iPad Air, Release): peta workspace dan halaman Course 60 fps tanpa hitch; tarik kontrol 60 fps;
PDF peta lomba 625 objek 30 ms; IOF XML 1,5 ms; buka halaman Course 0,3 s; ubah data lintasan 23–54 ms per perubahan.

## Lisensi

Proprietary — © 2026 Rizky Ajie Kurniawan. Seluruh hak dilindungi. Kode dan aplikasi ini tidak boleh dipakai,
disalin, diubah, atau dibagikan tanpa izin tertulis. Data dan komponen pihak ketiga (set simbol ISSprOM BOF,
citra Apple Maps, data elevasi Terrain Tiles) tunduk pada ketentuannya masing-masing. Lihat [LICENSE](LICENSE).
