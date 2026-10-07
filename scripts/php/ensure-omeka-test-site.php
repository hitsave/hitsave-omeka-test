<?php
/**
 * Ensure the public test site exists with HitSaveArchive theme and DIP item layout.
 * Reads slug/title/theme from /config/settings.yaml.
 */
declare(strict_types=1);

use Omeka\Entity\User;

require '/var/www/html/bootstrap.php';
require __DIR__ . '/omeka-site-theme-lib.php';

$settingsPath = '/config/settings.yaml';
if (!is_readable($settingsPath)) {
    fwrite(STDERR, "Missing {$settingsPath}\n");
    exit(1);
}

$yaml = file_get_contents($settingsPath);
preg_match('/^\s*site_slug:\s*(\S+)/m', $yaml, $slugMatch);
preg_match('/^\s*site_title:\s*(.+)$/m', $yaml, $titleMatch);
preg_match('/^\s*theme:\s*(\S+)/m', $yaml, $themeMatch);
$slug = $slugMatch[1] ?? 'hitsave-test';
$title = isset($titleMatch[1]) ? trim($titleMatch[1], " \t\"'") : 'Hit Save! Archive (test)';
$theme = $themeMatch[1] ?? 'HitSaveArchive';

$application = Omeka\Mvc\Application::init(
    require OMEKA_PATH . '/application/config/application.config.php'
);
$services = $application->getServiceManager();
$admin = $services->get('Omeka\EntityManager')->getRepository(User::class)
    ->findOneBy(['email' => 'admin@example.com']);
if (!$admin) {
    fwrite(STDERR, "Admin user not found.\n");
    exit(1);
}
$services->get('Omeka\AuthenticationService')->getStorage()->write($admin);

$api = $services->get('Omeka\ApiManager');
$themes = $services->get('Omeka\Site\ThemeManager');
$siteSettings = $services->get('Omeka\Settings\Site');
$blockLayoutManager = $services->get('Omeka\ResourcePageBlockLayoutManager');

$existing = $api->search('sites', ['slug' => $slug])->getContent();
$created = false;
if ($existing) {
    $siteId = $existing[0]->id();
    $api->update('sites', $siteId, [
        'o:title' => $title,
        'o:theme' => $theme,
    ], [], ['isPartial' => true]);
} else {
    $site = $api->create('sites', [
        'o:slug' => $slug,
        'o:title' => $title,
        'o:theme' => $theme,
        'o:is_public' => true,
        'o:navigation' => [],
        'o:item_pool' => [],
    ])->getContent();
    $siteId = $site->id();
    $created = true;
}

$themeSettings = array_merge(
    hitsaveDefaultThemeSettings(),
    archiveThemeFamilySettings('/config/archive-theme.yml')
);
applyThemeSettings($themes, $siteSettings, $blockLayoutManager, $siteId, $theme, $themeSettings);

$homepage = ensureSiteHomepageHub($api, $siteId, '/config/archive-theme.yml');

echo json_encode([
    'site_id' => $siteId,
    'slug' => $slug,
    'theme' => $theme,
    'created' => $created,
    'resource_page_blocks' => hitsaveDefaultResourcePageBlocks(),
    'homepage' => $homepage,
], JSON_PRETTY_PRINT) . "\n";
