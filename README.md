# Identitas Pokok

Proyek pengembangan identitas pokok kebun. **Belum siap operasional:** migrasi, pengujian akun lapangan, kamera, GPS, antrean offline dan kapasitas harus diverifikasi sebelum data produksi atau pencetakan massal.

## Pengembangan

Jalankan `npm ci`, `npm test`, lalu `npm run build`. Folder `dist/` berisi aplikasi statis. Database menggunakan akun dan peta Marking yang telah ada; file `supabase/migration.sql` menyiapkan tabel dan fungsi terpisah. Tinjau dan cadangkan database sebelum memasang migrasi.

Batch barcode disimpan sebagai rentang; tiap kode diterbitkan sebagai `IP1:<UUID batch>:<nomor>`. Cetak dan uji beberapa sampel sebelum mencetak banyak. Sesi sensus dibuka ketika online. Saat offline, antrean hanya tersimpan di browser HP sampai disinkronkan; data browser tidak boleh dihapus. GPS HP tidak menjamin ketepatan posisi satu meter. Selesaikan sesi hanya setelah seluruh petugas menyinkronkan.
