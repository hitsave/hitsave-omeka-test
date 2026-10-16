<?php
/**
 * Sync resource templates from config/omeka-test/mirror/prod-archive.json (prod pull).
 */
declare(strict_types=1);

use Omeka\Entity\User;

require '/var/www/html/bootstrap.php';
require __DIR__ . '/omeka-resource-template-sync-lib.php';

$mirrorPath = '/config/omeka-test/mirror/prod-archive.json';
if (!is_readable($mirrorPath)) {
    fwrite(STDERR, "Missing {$mirrorPath}; run scripts/shell/pull-omeka-prod-mirror.py first.\n");
    exit(1);
}

$mirror = json_decode(file_get_contents($mirrorPath), true, 512, JSON_THROW_ON_ERROR);

$application = Omeka\Mvc\Application::init(
    require OMEKA_PATH . '/application/config/application.config.php'
);
$services = $application->getServiceManager();
$admin = $services->get('Omeka\EntityManager')->getRepository(User::class)
    ->findOneBy(['email' => 'admin@example.com']);
$services->get('Omeka\AuthenticationService')->getStorage()->write($admin);

$api = $services->get('Omeka\ApiManager');
$synced = syncResourceTemplatesFromMirror($api, $mirror);

echo json_encode(['resource_templates' => $synced], JSON_PRETTY_PRINT) . "\n";
