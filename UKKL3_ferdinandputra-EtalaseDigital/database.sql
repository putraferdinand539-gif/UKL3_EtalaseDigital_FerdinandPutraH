-- ============================================================================
-- ETALASE DIGITAL STELLA - DATABASE LENGKAP (1 FILE)
--
-- Import file ini di phpMyAdmin (tab Import / tab SQL). Aman untuk 3 kondisi:
--   1. Instalasi BARU            -> membuat database, semua tabel, dan akun default.
--   2. Database LAMA (siswa di `users`) -> memindahkan siswa ke tabel `students`
--      beserta project mereka (NIS & jurusan ikut terbawa bila sudah ada). Data tidak hilang.
--   3. Sudah dimigrasi sebelumnya -> tidak mengubah apa pun (boleh dijalankan ulang).
--
-- Struktur akhir:
--   users    = hanya admin & super admin
--   students = semua siswa (nama, NIS, jurusan, email, password)
--   projects = dimiliki satu akun: student_id (siswa) ATAU user_id (admin)
--
-- Untuk database lama: BACKUP dulu (phpMyAdmin -> Export) sebelum import.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS database_etalase_stella_lkpd
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE database_etalase_stella_lkpd;

SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------------
-- 1. Tabel (dibuat hanya jika belum ada)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nama VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('super_admin', 'admin') NOT NULL DEFAULT 'admin'
);

CREATE TABLE IF NOT EXISTS students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nama VARCHAR(100) NOT NULL,
    nis VARCHAR(20) NULL UNIQUE,
    jurusan ENUM('RPL', 'TKJ', 'TJAT', 'Animasi') NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS projects (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    student_id INT NULL,
    nama_project VARCHAR(150) NOT NULL,
    deskripsi TEXT NOT NULL,
    gambar VARCHAR(255) NOT NULL,
    link_project VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 2. Upgrade database LAMA (semua langkah otomatis dilewati jika tidak perlu)
-- ---------------------------------------------------------------------------
-- Deteksi kondisi
SET @old_siswa = (SELECT COUNT(*) FROM information_schema.COLUMNS
                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users'
                    AND COLUMN_NAME = 'role' AND COLUMN_TYPE LIKE '%siswa%');
SET @has_nis   = (SELECT COUNT(*) FROM information_schema.COLUMNS
                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'nis');
SET @no_sid    = (SELECT COUNT(*) = 0 FROM information_schema.COLUMNS
                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'projects' AND COLUMN_NAME = 'student_id');
SET @uid_notnull = (SELECT COUNT(*) FROM information_schema.COLUMNS
                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'projects'
                    AND COLUMN_NAME = 'user_id' AND IS_NULLABLE = 'NO');

-- 2a. Pindahkan siswa dari users ke students (bawa NIS & jurusan jika ada)
SET @sql = IF(@old_siswa > 0,
  IF(@has_nis > 0,
    'INSERT INTO students (nama, nis, jurusan, email, password) SELECT nama, nis, jurusan, email, password FROM users WHERE role = ''siswa'' ORDER BY id',
    'INSERT INTO students (nama, email, password) SELECT nama, email, password FROM users WHERE role = ''siswa'' ORDER BY id'),
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 2b. projects: tambah kolom student_id (+ relasi) dan user_id boleh kosong
SET @sql = IF(@no_sid, 'ALTER TABLE projects ADD COLUMN student_id INT NULL AFTER user_id', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = IF(@no_sid, 'ALTER TABLE projects ADD CONSTRAINT fk_projects_student FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = IF(@uid_notnull > 0, 'ALTER TABLE projects MODIFY user_id INT NULL', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 2c. Alihkan kepemilikan project siswa ke akun siswa barunya
SET @sql = IF(@old_siswa > 0,
  'UPDATE projects p JOIN users u ON u.id = p.user_id AND u.role = ''siswa'' JOIN students s ON s.email = u.email SET p.student_id = s.id, p.user_id = NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 2d. users hanya admin & super admin
SET @sql = IF(@old_siswa > 0, 'DELETE FROM users WHERE role = ''siswa''', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = IF(@old_siswa > 0, 'ALTER TABLE users MODIFY role ENUM(''super_admin'', ''admin'') NOT NULL DEFAULT ''admin''', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = IF(@has_nis > 0, 'ALTER TABLE users DROP COLUMN jurusan, DROP COLUMN nis', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------------------------------------
-- 3. Akun default (password: password123) - HANYA untuk instalasi baru
--    (diisi hanya jika tabel users masih kosong). Segera ganti setelah login pertama.
-- ---------------------------------------------------------------------------
INSERT INTO users (nama, email, password, role)
SELECT * FROM (
    SELECT 'Super Admin Stella' AS nama, 'superadmin@stella.sch.id' AS email,
           '$2y$10$7C8r/agxCXnosP8mnSlZbOsWoUaW06UUJtuIFkUHuShVNBJ2pz0S.' AS password, 'super_admin' AS role
    UNION ALL
    SELECT 'Admin Stella', 'admin@stella.sch.id',
           '$2y$10$7C8r/agxCXnosP8mnSlZbOsWoUaW06UUJtuIFkUHuShVNBJ2pz0S.', 'admin'
) AS seed
WHERE (SELECT COUNT(*) FROM users) = 0;

INSERT INTO students (nama, nis, jurusan, email, password)
SELECT * FROM (
    SELECT 'Siswa Contoh' AS nama, '2024001' AS nis, 'RPL' AS jurusan, 'siswa@stella.sch.id' AS email,
           '$2y$10$7C8r/agxCXnosP8mnSlZbOsWoUaW06UUJtuIFkUHuShVNBJ2pz0S.' AS password
) AS seed
WHERE (SELECT COUNT(*) FROM students) = 0 AND (SELECT COUNT(*) FROM projects) = 0;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------------
-- Ringkasan hasil (cek angkanya masuk akal)
-- ---------------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM users)    AS jumlah_staff,
       (SELECT COUNT(*) FROM students) AS jumlah_siswa,
       (SELECT COUNT(*) FROM projects WHERE student_id IS NOT NULL) AS project_siswa,
       (SELECT COUNT(*) FROM projects WHERE user_id IS NOT NULL)    AS project_staff,
       (SELECT COUNT(*) FROM projects WHERE user_id IS NULL AND student_id IS NULL) AS project_tanpa_pemilik;
/