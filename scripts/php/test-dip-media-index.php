<?php
/**
 * CLI: index a DIP/BagIt media row and print file keys (Omeka bootstrap).
 *
 * Usage: php /scripts/test-dip-media-index.php <media_id>
 */
declare(strict_types=1);

require '/var/www/html/bootstrap.php';

$mediaId = (int) ($argv[1] ?? 0);
if ($mediaId < 1) {
    fwrite(STDERR, "Usage: php test-dip-media-index.php <media_id>\n");
    exit(1);
}

$application = Omeka\Mvc\Application::init(
    require OMEKA_PATH . '/application/config/application.config.php'
);
$services = $application->getServiceManager();
$api = $services->get('Omeka\ApiManager');
$media = $api->read('media', $mediaId)->getContent();

/** @var \OmekaDipViewer\Service\DipIndexService $indexService */
$indexService = $services->get('OmekaDipViewer\Service\DipIndexService');
$s3Prefix = $indexService->resolveS3Prefix($media);
$index = $indexService->getIndex($media);

echo json_encode([
    'media_id' => $mediaId,
    'item_id' => $media->item()->id(),
    'renderer' => $media->renderer(),
    's3_prefix' => $s3Prefix,
    'package_format' => $index['package_format'] ?? null,
    'file_count' => is_array($index) ? count($index['files'] ?? []) : 0,
    'files' => array_map(static fn (array $f): array => [
        'key' => $f['key'] ?? '',
        'relative_path' => $f['relative_path'] ?? '',
    ], $index['files'] ?? []),
], JSON_PRETTY_PRINT) . "\n";
