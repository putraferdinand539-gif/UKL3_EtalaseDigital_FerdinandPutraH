-- ============================================================================
-- MIGRASI: pisahkan siswa ke tabel `students`
-- Jalankan SEKALI di phpMyAdmin: pilih database_etalase_stella_lkpd -> tab SQL -> Go.
--
-- Yang dilakukan (data lama TIDAK hilang):
--   1. Membuat tabel `students` (nama, nis, jurusan, email, password).
--   2. Memindahkan semua akun siswa dari `users` ke `students`
--      (NIS & jurusan ikut terbawa jika kolomnya sudah ada di `users`).
--   3. Project milik siswa dipindah kepemilikannya: projects.student_id
--      (project milik admin/super admin tetap memakai projects.user_id).
--   4. Menghapus akun siswa dari `users` -> `users` hanya berisi admin & super admin.
-- Aman dijalankan baik sebelum maupun sesudah migrasi_nis_jurusan.sql lama.
-- ============================================================================

USE database_etalase_stella_lkpd;

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Tabel siswa
CREATE TABLE students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nama VARCHAR(100) NOT NULL,
    nis VARCHAR(20) NULL UNIQUE,
    jurusan ENUM('RPL', 'TKJ', 'TJAT', 'Animasi') NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 2. Pindahkan siswa (ikut membawa nis/jurusan bila kolomnya ada di users)
SET @has_nis = (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'nis');
SET @sql = IF(@has_nis > 0,
    'INSERT INTO students (nama, nis, jurusan, email, password) SELECT nama, nis, jurusan, email, password FROM users WHERE role = ''siswa'' ORDER BY id',
    'INSERT INTO students (nama, email, password) SELECT nama, email, password FROM users WHERE role = ''siswa'' ORDER BY id');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 3. Project: kolom pemilik siswa + user_id boleh kosong
ALTER TABLE projects ADD COLUMN student_id INT NULL AFTER user_id;
ALTER TABLE projects MODIFY user_id INT NULL;
ALTER TABLE projects ADD CONSTRAINT fk_projects_student
    FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

UPDATE projects p
    JOIN users u    ON u.id = p.user_id AND u.role = 'siswa'
    JOIN students s ON s.email = u.email
SET p.student_id = s.id, p.user_id = NULL;

-- 4. users = hanya admin & super admin
DELETE FROM users WHERE role = 'siswa';
ALTER TABLE users MODIFY role ENUM('super_admin', 'admin') NOT NULL DEFAULT 'admin';

SET @sql = IF(@has_nis > 0, 'ALTER TABLE users DROP COLUMN jurusan, DROP COLUMN nis', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET FOREIGN_KEY_CHECKS = 1;

-- Ringkasan hasil (cek angkanya masuk akal)
SELECT (SELECT COUNT(*) FROM users)    AS jumlah_staff,
       (SELECT COUNT(*) FROM students) AS jumlah_siswa,
       (SELECT COUNT(*) FROM projects WHERE student_id IS NOT NULL) AS project_siswa,
       (SELECT COUNT(*) FROM projects WHERE user_id IS NOT NULL)    AS project_staff,
       (SELECT COUNT(*) FROM projects WHERE user_id IS NULL AND student_id IS NULL) AS project_tanpa_pemilik;
