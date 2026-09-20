---
title: "PRD: OpenClipText"
status: final
created: 2026-09-20
updated: 2026-09-20
---

# PRD: OpenClipText

## 1. Ringkasan

OpenClipText adalah manajer clipboard untuk macOS, clone pribadi dari CopyClip — dibuat untuk dipakai sendiri. Aplikasi berjalan di background, merekam setiap teks yang disalin, dan memungkinkan penempelan kembali item riwayat mana pun lewat menu bar atau shortcut global.

**Pembeda dari CopyClip:** preview hover yang di-chunk — teks besar tidak lagi menyebabkan lag saat hover.

## 2. Pengguna & Konteks

- Pengguna tunggal: pemilik aplikasi sendiri (developer, pengguna Mac aktif sehari-hari).
- Tidak dirilis publik untuk v1. Tanpa monetisasi, tanpa akun, tanpa sinkronisasi.

## 3. User Journey

**UJ-1: Salin-tempel harian** — Aku sedang kerja, salin teks bergantian dari Chrome, Terminal, dan editor. Mau menempel item sebelumnya → klik ikon menu bar (atau tekan shortcut global) → dropdown riwayat muncul instan → tekan angka untuk memilih item → item masuk clipboard → tempel dengan `⌘V`. Saat ragu item mana yang dibutuhkan, hover untuk preview — teks besar tetap responsif karena dipangkas menjadi beberapa baris pertama.

**UJ-2: Kembali ke item lama** — Aku butuh teks yang disalin beberapa jam lalu → buka riwayat → cari item dengan pencarian (atau gulir ke bawah, item terbaru di atas) → pilih → tempel.

## 4. Fitur

### 4.1 Perekaman clipboard

- **FR-1:** Setiap perubahan clipboard teks (salin/cut) direkam otomatis ke riwayat, tanpa aksi manual.
- **FR-2:** Duplikat dihindari: menyalin ulang teks yang sama memindahkan item lama ke posisi teratas, tidak menambah entri baru. Item terpin (FR-8) tidak dipindahkan.
- **FR-3:** Hanya teks yang direkam. Teks direkam sebagai string teks biasa (formatting/rich text tidak dipertahankan). Gambar dan file tidak disimpan di v1.
- **FR-4:** Riwayat bertahan antar-restart aplikasi. Kapasitas mengikuti CopyClip: ratusan item tanpa batas waktu.

### 4.2 Menu bar & tampilan riwayat

- **FR-5:** Ikon di menu bar; klik membuka dropdown riwayat dengan item terbaru di atas, teks dipangkas satu baris.
- **FR-6:** Global shortcut membuka dropdown yang sama tanpa mouse. Default `⌥⇧V` (mengikuti CopyClip), dapat diubah.
- **FR-7:** Memilih item: tombol angka `1–9` untuk item terlihat, navigasi panah + Enter, atau klik. Daftar dipaginasi per 20 item (gulir/panah lanjut ke halaman berikutnya), mengikuti perilaku CopyClip. Item terpilih langsung mengisi clipboard, siap `⌘V`.
- **FR-8:** Pin/favorit: item terpin tetap di daftar dan tidak tergeser item baru.

### 4.3 Preview yang responsif (pembeda utama)

- **FR-9:** Hover pada item menampilkan preview yang di-chunk: maksimal 10 baris pertama ATAU 500 karakter — mana pun yang tercapai lebih dulu — plus indikator "… +N baris lagi". Angka pastinya keputusan implementasi; yang di-lock: hover tidak pernah merender teks penuh.
- **FR-10:** Teks penuh hanya ditampilkan saat item dibuka sengaja (expand), bukan via hover.
- **FR-11:** Preview hover tidak pernah mem-blok UI — waktu render di-bounded untuk teks berapa pun besarnya.

### 4.4 Pengelolaan riwayat

- **FR-12:** Hapus item tunggal (menu konteks/shortcut saat item dipilih).
- **FR-13:** Hapus seluruh riwayat.
- **FR-14:** Pencarian teks dalam riwayat: mulai mengetik saat dropdown terbuka untuk memfilter daftar secara langsung.
- **FR-15:** Aplikasi tertentu dapat di-exclude dari perekaman (mis. password manager). Adopsi dari CopyClip.

## 5. Non-Functional

- **NFR-1 Performa:** dropdown terbuka < 100ms; hover preview < 50ms untuk teks hingga 1MB (jalur ekstraksi + render chunk, bukan teks penuh); perekaman clipboard tanpa kelihatan di foreground.
- **NFR-2 Startup:** berjalan saat login (login item), tanpa jendela utama.
- **NFR-3 Sumber daya:** idle CPU ~0%, memori wajar untuk cache teks (ringan; teks besar dipangkas untuk tampilan, penuh di disk).
- **NFR-4 OS:** macOS modern (13+), native menu bar, global shortcut terdaftar di sistem.

## 6. Metrik Sukses

- Preview hover bebas lag pada teks 1MB+ (pembeda utama tercapai).
- Pemakaian nyata sehari-hari oleh pemiliknya, menggantikan CopyClip sepenuhnya (aplikasi lama dihapus).
- Counter-metric: CopyClip masih terpasang/dipakai = belum sukses.

## 7. Di Luar Cakupan v1

- Gambar/file di riwayat
- Sinkronisasi iCloud/perangkat lain
- Snippet/template permanen di luar pin
- Rilis App Store, onboarding, monetisasi
- iOS / versi non-macOS

## 8. Open Items

- Tidak ada yang memblokir UX/arsitektur/epik. Detail tersisa (angka chunk pasti, jumlah item per halaman) adalah keputusan implementasi.
