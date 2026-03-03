<?php
declare(strict_types=1);

header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store, no-cache, must-revalidate');
header('Content-Type: application/json; charset=utf-8');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    http_response_code(405);
    echo json_encode(['found' => false]);
    exit;
}

// type=executives&slug=nishant-hada → looks up in executives.csv
$type = trim($_GET['type'] ?? '');
$slug = trim($_GET['slug'] ?? '');

if ($type === '' || !preg_match('/^[a-z]+(-[a-z]+)*$/', $type)) {
    echo json_encode(['found' => false]);
    exit;
}

if ($slug === '' || !preg_match('/^[a-zA-Z]+(-[a-zA-Z]+)+$/', $slug)) {
    echo json_encode(['found' => false]);
    exit;
}

$dataDir = getenv('CUECARD_DATA_DIR');
if (!$dataDir) {
    $dataDir = '/var/www/cuecard-data';
}

$csvFile = rtrim($dataDir, '/') . '/' . $type . '.csv';
if (!file_exists($csvFile) || !is_readable($csvFile)) {
    echo json_encode(['found' => false]);
    exit;
}

$handle = fopen($csvFile, 'r');
if (!$handle) {
    echo json_encode(['found' => false]);
    exit;
}

// Read header row
$headers = fgetcsv($handle);
if (!$headers) {
    fclose($handle);
    echo json_encode(['found' => false]);
    exit;
}
$headers = array_map(function($h) { return strtolower(trim($h)); }, $headers);

$normalized = strtolower($slug);
$match = null;

while (($row = fgetcsv($handle)) !== false) {
    $entry = [];
    foreach ($headers as $i => $key) {
        $entry[$key] = trim($row[$i] ?? '');
    }

    // Build slug from row: "firstname-lastname" (lowercase)
    $parts = [$entry['firstname'] ?? ''];
    if (!empty($entry['lastname'])) {
        $parts[] = $entry['lastname'];
    }
    $rowSlug = strtolower(implode('-', $parts));

    if ($rowSlug === $normalized) {
        $match = $entry;
        break;
    }
}

fclose($handle);

if ($match) {
    $match['found'] = true;
    echo json_encode($match);
} else {
    echo json_encode(['found' => false]);
}
