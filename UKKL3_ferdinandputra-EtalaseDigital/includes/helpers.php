<?php
/** Hanya izinkan link http/https (mencegah javascript: dsb). */
function valid_http_url(string $url): bool {
    if (!filter_var($url, FILTER_VALIDATE_URL)) {
        return false;
    }
    $scheme = strtolower((string) parse_url($url, PHP_URL_SCHEME));
    return in_array($scheme, ['http', 'https'], true);
}

/**
 * Validasi & simpan gambar project. Mengembalikan nama file baru,
 * atau null (dan mengisi $error) jika gagal.
 */
function save_project_image(array $file, string $uploadDir, ?string &$error): ?string {
    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        $error = "Pilih gambar karya digital terlebih dahulu!";
        return null;
    }
    if ($file['size'] > 2 * 1024 * 1024) {
        $error = "Ukuran berkas gambar tidak boleh lebih dari 2MB!";
        return null;
    }

    $allowed = [IMAGETYPE_JPEG => 'jpg', IMAGETYPE_PNG => 'png', IMAGETYPE_WEBP => 'webp'];
    $info    = @getimagesize($file['tmp_name']);
    if ($info === false || !isset($allowed[$info[2]])) {
        $error = "Format gambar harus berupa JPG, JPEG, PNG, atau WEBP!";
        return null;
    }

    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0755, true);
    }

    $newName = uniqid('project_', true) . '.' . $allowed[$info[2]];
    if (!move_uploaded_file($file['tmp_name'], rtrim($uploadDir, '/\\') . '/' . $newName)) {
        $error = "Gagal mengunggah berkas gambar ke server.";
        return null;
    }
    return $newName;
}

function delete_project_image(string $uploadDir, string $fileName): void {
    $path = rtrim($uploadDir, '/\\') . '/' . basename($fileName);
    if ($fileName !== '' && is_file($path)) {
        unlink($path);
    }
}

/** Hapus file gambar dari daftar nama file. */
function delete_project_images(array $files): void {
    foreach ($files as $f) {
        delete_project_image(UPLOAD_DIR, $f);
    }
}

/**
 * Hapus akun staff (tabel `users`; hanya jika rolenya ada di $allowedRoles)
 * beserta file gambar project miliknya.
 */
function delete_staff_with_files(PDO $pdo, int $id, array $allowedRoles): bool {
    $stmt = $pdo->prepare("SELECT role FROM users WHERE id = :id");
    $stmt->execute([':id' => $id]);
    $user = $stmt->fetch();
    if (!$user || !in_array($user['role'], $allowedRoles, true)) {
        return false;
    }

    $imgs = $pdo->prepare("SELECT gambar FROM projects WHERE user_id = :id");
    $imgs->execute([':id' => $id]);
    $files = $imgs->fetchAll(PDO::FETCH_COLUMN);

    $pdo->prepare("DELETE FROM users WHERE id = :id")->execute([':id' => $id]);
    delete_project_images($files);
    return true;
}

/** Hapus akun siswa (tabel `students`) beserta file gambar project miliknya. */
function delete_student_with_files(PDO $pdo, int $id): bool {
    $exists = $pdo->prepare("SELECT 1 FROM students WHERE id = :id");
    $exists->execute([':id' => $id]);
    if (!$exists->fetchColumn()) {
        return false;
    }

    $imgs = $pdo->prepare("SELECT gambar FROM projects WHERE student_id = :id");
    $imgs->execute([':id' => $id]);
    $files = $imgs->fetchAll(PDO::FETCH_COLUMN);

    $pdo->prepare("DELETE FROM students WHERE id = :id")->execute([':id' => $id]);
    delete_project_images($files);
    return true;
}

/** Email dipakai bersama oleh staff & siswa untuk login, jadi harus unik di KEDUA tabel. */
function email_taken(PDO $pdo, string $email): bool {
    foreach (['users', 'students'] as $table) {
        $stmt = $pdo->prepare("SELECT 1 FROM $table WHERE email = :email LIMIT 1");
        $stmt->execute([':email' => $email]);
        if ($stmt->fetchColumn()) {
            return true;
        }
    }
    return false;
}

/** True jika error PDO adalah duplikat (email sudah terdaftar). */
function is_duplicate_error(PDOException $e): bool {
    return ($e->errorInfo[1] ?? 0) === 1062;
}

/* ---------- NIS & Jurusan siswa ---------- */

/** Pilihan jurusan yang tersedia (juga dipakai untuk validasi di server). */
const JURUSAN_LIST = ['RPL', 'TKJ', 'TJAT', 'Animasi'];

/** Validasi NIS & jurusan. Mengembalikan pesan error, atau '' jika valid. */
function validate_nis_jurusan(string $nis, string $jurusan): string {
    if (!preg_match('/^[0-9]{4,20}$/', $nis)) {
        return "NIS harus berupa angka (4-20 digit)!";
    }
    if (!in_array($jurusan, JURUSAN_LIST, true)) {
        return "Pilih jurusan yang tersedia (" . implode(', ', JURUSAN_LIST) . ")!";
    }
    return '';
}

/** Pesan error untuk data duplikat: membedakan email dan NIS. */
function duplicate_message(PDOException $e, string $fallback): string {
    if (!is_duplicate_error($e)) {
        return $fallback;
    }
    // Contoh pesan MySQL: "Duplicate entry 'x' for key 'users.nis'"
    $key = preg_match("/for key '([^']+)'/", $e->errorInfo[2] ?? '', $m) ? $m[1] : '';
    return substr($key, -3) === 'nis' ? "NIS sudah terdaftar!" : "Email sudah terdaftar!";
}
