<?php
/**
 * Apply config/omeka-test/mirror/prod-archive.json to the local test site (read-only prod pull).
 */
declare(strict_types=1);

use Omeka\Entity\User;

require '/var/www/html/bootstrap.php';
require __DIR__ . '/omeka-site-theme-lib.php';

$mirrorPath = '/config/omeka-test/mirror/prod-archive.json';
$sourcePath = '/config/omeka-test/omeka-prod-source.yaml';
if (!is_readable($mirrorPath)) {
    fwrite(STDERR, "Missing {$mirrorPath}; run scripts/pull-omeka-prod-mirror.py first.\n");
    exit(1);
}

$mirror = json_decode(file_get_contents($mirrorPath), true, 512, JSON_THROW_ON_ERROR);
$sourceYaml = is_readable($sourcePath) ? file_get_contents($sourcePath) : '';
preg_match('/target_site_slug:\s*(\S+)/', $sourceYaml, $slugMatch);
preg_match('/target_site_title:\s*(.+)$/m', $sourceYaml, $titleMatch);
$targetSlug = $slugMatch[1] ?? 'hitsave-test';
$targetTitle = isset($titleMatch[1]) ? trim($titleMatch[1], " \t\"'") : 'Hit Save! Archive (test mirror)';
$targetTheme = 'foundation';
if (preg_match('/target_theme:\s*(\S+)/', $sourceYaml, $themeMatch)) {
    $targetTheme = trim($themeMatch[1]);
}

$application = Omeka\Mvc\Application::init(
    require OMEKA_PATH . '/application/config/application.config.php'
);
$services = $application->getServiceManager();
$admin = $services->get('Omeka\EntityManager')->getRepository(User::class)
    ->findOneBy(['email' => 'admin@example.com']);
$services->get('Omeka\AuthenticationService')->getStorage()->write($admin);

$api = $services->get('Omeka\ApiManager');
$siteSettings = $services->get('Omeka\Settings\Site');
$themes = $services->get('Omeka\Site\ThemeManager');
$blockLayoutManager = $services->get('Omeka\ResourcePageBlockLayoutManager');

$sites = $api->search('sites', ['slug' => $targetSlug])->getContent();
if (!$sites) {
    $site = $api->create('sites', [
        'o:slug' => $targetSlug,
        'o:title' => $targetTitle,
        'o:theme' => $targetTheme,
        'o:is_public' => true,
        'o:navigation' => [],
        'o:item_pool' => [],
    ])->getContent();
    $siteId = $site->id();
} else {
    $siteId = $sites[0]->id();
    $api->update('sites', $siteId, [
        'o:title' => $targetTitle,
        'o:theme' => $targetTheme,
    ], [], ['isPartial' => true]);
}

ensurePressTemplate($api, $mirror['resource_template']);
$themeSettings = array_merge(
    hitsaveDefaultThemeSettings(),
    archiveThemeFamilySettings('/config/archive-theme.yml'),
    $mirror['theme_settings'] ?? []
);
applyThemeSettings($themes, $siteSettings, $blockLayoutManager, $siteId, $targetTheme, $themeSettings);

$slugToId = syncPages($api, $siteId, $mirror['site_pages'] ?? []);
$navigation = buildNavigation($mirror['site']['navigation'] ?? [], $slugToId);
$homepageSlug = $mirror['site']['homepage_slug'] ?? 'intro';
$update = ['o:navigation' => $navigation];
if (isset($slugToId[$homepageSlug])) {
    $update['o:homepage'] = ['o:id' => $slugToId[$homepageSlug]];
}
$api->update('sites', $siteId, $update, [], ['isPartial' => true]);

echo json_encode([
    'site_id' => $siteId,
    'site_slug' => $targetSlug,
    'theme' => $targetTheme,
    'resource_template' => $mirror['resource_template']['label'] ?? null,
    'pages_synced' => count($slugToId),
], JSON_PRETTY_PRINT) . "\n";

function buildNavigation(array $navigation, array $slugToId): array
{
    $out = [];
    foreach ($navigation as $entry) {
        if (($entry['type'] ?? '') === 'page') {
            $slug = $entry['page_slug'] ?? null;
            if (!$slug || !isset($slugToId[$slug])) {
                continue;
            }
            $data = $entry['data'] ?? [];
            $data['id'] = $slugToId[$slug];
            unset($entry['page_slug']);
            $entry['data'] = $data;
        }
        $out[] = $entry;
    }
    return $out;
}

function propertyId($api, string $term): ?int
{
    $rows = $api->search('properties', ['term' => $term])->getContent();
    return $rows ? (int) $rows[0]->id() : null;
}

function resourceClassId($api, string $term): ?int
{
    $rows = $api->search('resource_classes', ['term' => $term])->getContent();
    return $rows ? (int) $rows[0]->id() : null;
}

function ensurePressTemplate($api, array $spec): void
{
    $label = $spec['label'] ?? 'Press and Marketing Material';
    $existing = $api->search('resource_templates', ['label' => $label])->getContent();
    $classTerm = $spec['resource_class_term'] ?? 'dctype:Collection';
    $classId = resourceClassId($api, $classTerm);
    $props = [];
    foreach ($spec['properties'] ?? [] as $row) {
        $term = $row['term'] ?? '';
        if ($term === 'curation:location') {
            continue;
        }
        $pid = propertyId($api, $term);
        if (!$pid) {
            continue;
        }
        $dataTypes = $row['data_type'] ?? [];
        if ($dataTypes && str_starts_with((string) ($dataTypes[0] ?? ''), 'customvocab:')) {
            $dataTypes = [];
        }
        $props[] = [
            'o:property' => ['o:id' => $pid],
            'o:alternate_label' => $row['alternate_label'] ?? null,
            'o:is_required' => !empty($row['required']),
            'o:data_type' => $dataTypes,
        ];
    }
    $payload = [
        'o:label' => $label,
        'o:resource_class' => $classId ? ['o:id' => $classId] : null,
        'o:resource_template_property' => $props,
    ];
    if ($existing) {
        $api->update('resource_templates', $existing[0]->id(), $payload, [], ['isPartial' => true]);
    } else {
        $api->create('resource_templates', $payload);
    }
}

function syncPages($api, int $siteId, array $pages): array
{
    $api->update('sites', $siteId, ['o:homepage' => null], [], ['isPartial' => true]);

    $slugToId = [];
    foreach ($pages as $pageSpec) {
        $slug = $pageSpec['slug'] ?? null;
        if (!$slug) {
            continue;
        }
        $existing = $api->search('site_pages', ['site_id' => $siteId, 'slug' => $slug])->getContent();
        $payload = [
            'o:site' => ['o:id' => $siteId],
            'o:slug' => $slug,
            'o:title' => $pageSpec['title'] ?? $slug,
            'o:is_public' => $pageSpec['is_public'] ?? true,
            'o:block' => sanitizeBlocks($pageSpec['blocks'] ?? []),
        ];
        // Partial update appends o:block rows; replace the page so blocks stay idempotent.
        if ($existing) {
            $api->delete('site_pages', $existing[0]->id());
        }
        $page = $api->create('site_pages', $payload)->getContent();
        $slugToId[$slug] = $page->id();
    }
    return $slugToId;
}

function sanitizeBlocks(array $blocks): array
{
    $out = [];
    foreach ($blocks as $block) {
        $layout = $block['o:layout'] ?? '';
        if ($layout === 'browsePreview') {
            $data = $block['o:data'] ?? [];
            if (isset($data['query']) && str_contains((string) $data['query'], 'item_set_id')) {
                $data['query'] = 'sort_by=created&sort_order=desc';
            }
            $block['o:data'] = $data;
        }
        $out[] = $block;
    }
    return $out;
}
