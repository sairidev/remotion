# Remotion Egg (Docker + Pterodactyl)

Image Docker dan egg untuk menjalankan [Remotion](https://www.remotion.dev) di
**Pterodactyl / Pelican**. Semua dikendalikan lewat **menu bernomor** (ketik angka + Enter,
tanpa tombol panah), dan tetap bisa dipakai di Docker biasa.

Image di-build di GitHub Actions dan sudah berisi Node.js 22, Chrome Headless Shell, font,
serta project template lengkap dengan `node_modules`. Server panel hanya menarik image dan
menyalin template, tanpa `npm install` atau download Chrome.

## Isi repo

| Path | Fungsi |
|---|---|
| `docker/Dockerfile` | Image runtime (Node 22 + library Chrome + template siap pakai) |
| `docker/entrypoint.sh` | Menyiapkan environment, menampilkan banner, menjalankan startup command |
| `docker/menu.sh` | Menu bernomor (`remotion-menu`) |
| `docker/lib.sh` | Fungsi bersama: warna, banner, info sistem |
| `docker/egg-remotion.json` | Egg Pterodactyl siap import |
| `template/` | Project Remotion bawaan yang disalin ke server saat pertama menyala |
| `.github/workflows/docker-publish.yml` | Build dan push image ke `ghcr.io` |

## Cara pasang

1. Buat repo GitHub bernama `remotion`, upload semua isi folder ini, push ke branch `main`.
2. Tunggu workflow **Docker** di tab Actions selesai. Image muncul di
   `ghcr.io/<username>/remotion:latest` (username huruf kecil).
3. Buka halaman package di GitHub, ubah visibility menjadi **Public** supaya panel bisa menariknya.
4. Edit `docker/egg-remotion.json`: ganti `GANTI_USERNAME` dengan username GitHub.
5. Di panel: **Nests > Import Egg**, pilih `egg-remotion.json`.
6. Buat server dengan egg itu. Saran minimum: RAM 2 GB, disk 3 GB, 1 port (allocation).

## Menu

```
Menu Remotion
  1) Jalankan Remotion Studio   (web editor, port <SERVER_PORT>)
  2) Render video
  3) Render gambar (still)
  4) Lihat daftar komposisi
  5) Hasil render
  6) Kelola project            (install, upgrade, reset)
  7) Info sistem
  8) Buka shell
  0) Keluar (matikan server)
```

- Saat Studio atau render sedang berjalan, ketik `0` + Enter untuk menghentikannya dan kembali ke menu.
- Render video: pilih komposisi dengan nomor, lalu pilih format (MP4 H.264, MP4 H.265, WebM, GIF, ProRes).
- Hasil render tersimpan di `out/`. Unduh lewat File Manager atau SFTP panel.
- Project ada di folder server (`/home/container`). Edit `src/` lewat File Manager, SFTP, atau Studio.
- Kalau menu utama tidak dijawab dalam 30 detik, Studio menyala otomatis. Jadi server yang
  restart sendiri tidak berhenti di menu.

## Environment variable

| Variabel | Fungsi | Default |
|---|---|---|
| `SERVER_PORT` / `PORT` | Port Remotion Studio | `3000` |
| `AUTO_ACTION` | `studio` atau `menu`: aksi saat menu utama tidak dijawab | `studio` |
| `MENU_TIMEOUT` | Detik menunggu sebelum aksi otomatis, `0` = tunggu terus | `30` |
| `SHOW_IP` | `true` menampilkan IP publik di banner | `false` |
| `REMOTION_ENTRY` | Entry point project, kosong = deteksi otomatis | kosong |
| `RENDER_CONCURRENCY` | Jumlah tab Chrome saat render (`2`, `50%`) | otomatis |
| `RENDER_EXTRA_ARGS` | Flag tambahan untuk `remotion render` (mis. `--crf 18 --scale 0.5`) | kosong |
| `REMOTION_BROWSER_EXECUTABLE` | Path Chrome sendiri | bawaan Remotion |
| `PLAIN_OUTPUT` | `1` log baris per baris, `0` progress bar | `1` |

## Docker biasa

```bash
docker build -f docker/Dockerfile -t remotion-egg .

# interaktif, menu bernomor
docker run -it --rm -p 3000:3000 -v "$PWD/data:/home/container" remotion-egg

# detached: Studio langsung menyala
docker run -d -p 3000:3000 -v "$PWD/data:/home/container" remotion-egg
```

## Catatan penting

- **Remotion Studio tidak punya login.** Siapa pun yang tahu `IP:port` bisa membuka, mengubah
  project, dan menjalankan render. Matikan Studio saat tidak dipakai (ketik `0`), atau taruh
  di belakang reverse proxy yang memakai password.
- File sementara (bundle, frame, profil Chrome) ditaruh di `.tmp/` dalam folder server, karena
  `/tmp` di Pterodactyl hanya 100 MB. Folder ini dibersihkan setiap server menyala.
- Render butuh RAM. Kalau proses mati di tengah jalan, kecilkan `RENDER_CONCURRENCY` (mis. `1`).
- Lisensi Remotion gratis untuk perorangan dan tim kecil. Perusahaan dengan lebih dari 3 orang
  perlu lisensi berbayar, cek https://www.remotion.dev/license.

## Update

Update image = push ke `main` atau buat tag `vX.Y.Z`, lalu restart server di panel agar image
terbaru ditarik. Project yang sudah ada di server tidak ikut berubah. Untuk menaikkan versi
Remotion di project, pakai menu **6 > 3 (Upgrade Remotion)**. Untuk menaikkan versi di template,
ubah `template/package.json` lalu jalankan `npm install` di folder `template/` supaya
`package-lock.json` ikut ter-update.
