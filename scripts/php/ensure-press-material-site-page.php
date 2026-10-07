<?php
/**
 * Create/update the public Press Materials site page (browse hub for the press item set).
 *
 * Config: config/omeka-test/settings.yaml → site.press_material (+ omeka.site_slug, item_set_title)
 */
declare(strict_types=1);

use Omeka\Entity\User;

require '/var/www/html/bootstrap.php';

function yaml_scalar(string $yaml, string $key): ?string
{
    if (preg_match('/^\s*' . preg_quote($key, '/') . ':\s*(.+)$/m', $yaml, $m)) {
        return trim($m[1], " \t\"'");
    }
    return null;
}

$settingsPath = '/config/settings.yaml';
if (!is_readable($settingsPath)) {
    fwrite(STDERR, "Missing {$settingsPath}\n");
    exit(1);
}
$yaml = file_get_contents($settingsPath);
$siteSlug = yaml_scalar($yaml, 'site_slug') ?? 'hitsave-test';

$pageSlug = 'press-material';
$pageTitle = 'Press Materials';
$navLabel = $pageTitle;
$previewLimit = 12;
if (preg_match('/^\s*press_material:\s*\n(?:^\s+.+\n)*?^\s*page_slug:\s*(\S+)/m', $yaml, $m)) {
    $pageSlug = trim($m[1], " \t\"'");
}
if (preg_match('/^\s*press_material:\s*\n(?:^\s+.+\n)*?^\s*page_title:\s*(.+)$/m', $yaml, $m)) {
    $pageTitle = trim($m[1], " \t\"'");
}
if (preg_match('/^\s*press_material:\s*\n(?:^\s+.+\n)*?^\s*nav_label:\s*(.+)$/m', $yaml, $m)) {
    $navLabel = trim($m[1], " \t\"'");
}
if (preg_match('/^\s*press_material:\s*\n(?:^\s+.+\n)*?^\s*browse_limit:\s*(\d+)/m', $yaml, $m)) {
    $previewLimit = (int) $m[1];
}
$itemSetTitle = yaml_scalar($yaml, 'item_set_title') ?? 'Press and Marketing Materials';

$introHtml = <<<'HTML'
<p>We are excited to share our treasure trove of press material, promotional material, and behind-the-scenes/bonus content.</p>
<div class="col-sm-8">As we uncover, organize, and digitize more, you will see frequent updates here.</div>
<div class="col-sm-8">If you find something really interesting, please let us know in #the-archive in our <a href="https://discord.gg/9xSY2fn4zh">Discord</a>.</div>
HTML;

$application = Omeka\Mvc\Application::init(
    require OMEKA_PATH . '/application/config/application.config.php'
);
$services = $application->getServiceManager();
$entityManager = $services->get('Omeka\EntityManager');

$admin = $entityManager->getRepository(User::class)->findOneBy(['email' => 'admin@example.com']);
if (!$admin) {
    fwrite(STDERR, "Admin user not found.\n");
    exit(1);
}
$services->get('Omeka\AuthenticationService')->getStorage()->write($admin);

$api = $services->get('Omeka\ApiManager');

$sites = $api->search('sites', ['slug' => $siteSlug])->getContent();
if (!$sites) {
    fwrite(STDERR, "Site {$siteSlug} not found; run ensure-omeka-test-site.php first.\n");
    exit(1);
}
$site = $sites[0];
$siteId = $site->id();

$itemSets = $api->search('item_sets', ['title' => $itemSetTitle])->getContent();
if (!$itemSets) {
    fwrite(STDERR, "Item set \"{$itemSetTitle}\" not found; run ensure-press-item-set.php first.\n");
    exit(1);
}
$itemSetId = (int) $itemSets[0]->id();
$queryString = 'sort_by=created&sort_order=desc&item_set_id[]=' . rawurlencode((string) $itemSetId);

$existingPageId = null;
foreach ($site->pages() as $sitePage) {
    if ($sitePage->slug() === $pageSlug) {
        $existingPageId = (int) $sitePage->id();
        break;
    }
}

$pagePayload = [
    'o:site' => ['o:id' => $siteId],
    'o:title' => $pageTitle,
    'o:slug' => $pageSlug,
    'o:is_public' => true,
    'o:block' => [
        [
            'o:layout' => 'pageTitle',
            'o:data' => [],
            'o:position' => 1,
        ],
        [
            'o:layout' => 'html',
            'o:data' => ['html' => $introHtml],
            'o:position' => 2,
        ],
        [
            'o:layout' => 'lineBreak',
            'o:data' => ['break_type' => 'opaque'],
            'o:position' => 3,
        ],
        [
            'o:layout' => 'browsePreview',
            'o:data' => [
                'resource_type' => 'items',
                'query' => $queryString,
                'heading' => '',
                'limit' => $previewLimit,
                'components' => ['resource-heading', 'resource-body', 'thumbnail'],
                'link-text' => 'Browse all',
            ],
            'o:position' => 4,
        ],
    ],
];

$pageCreated = false;
if ($existingPageId) {
    try {
        $api->delete('site_pages', $existingPageId);
    } catch (Throwable $e) {
        fwrite(STDERR, "Could not replace existing page {$existingPageId}: {$e->getMessage()}\n");
    }
}
$page = $api->create('site_pages', $pagePayload)->getContent();
$pageId = (int) $page->id();
$pageCreated = true;

$navigation = $site->navigation();
if (!is_array($navigation)) {
    $navigation = [];
}

$staleNavIds = $existingPageId ? [$existingPageId] : [];
$newNavigation = [];
$hasNav = false;
foreach ($navigation as $entry) {
    if (($entry['type'] ?? '') === 'page') {
        $navPageId = (int) ($entry['data']['id'] ?? 0);
        if (in_array($navPageId, $staleNavIds, true)) {
            continue;
        }
        if ($navPageId === $pageId) {
            $hasNav = true;
        }
    }
    $newNavigation[] = $entry;
}
if (!$hasNav) {
    $newNavigation[] = [
        'type' => 'page',
        'data' => [
            'label' => $navLabel,
            'id' => $pageId,
        ],
        'links' => [],
    ];
}
if ($newNavigation !== $navigation) {
    $api->update('sites', $siteId, [
        'o:navigation' => $newNavigation,
    ], [], ['isPartial' => true]);
}

preg_match('/^\s*public_url:\s*(\S+)/m', $yaml, $urlMatch);
$publicBase = isset($urlMatch[1]) ? rtrim($urlMatch[1], '/') : '';

echo json_encode([
    'site_slug' => $siteSlug,
    'page_id' => $pageId,
    'page_slug' => $pageSlug,
    'page_created' => $pageCreated,
    'item_set_id' => $itemSetId,
    'public_page_url' => $publicBase
        ? "{$publicBase}/s/{$siteSlug}/page/{$pageSlug}"
        : "/s/{$siteSlug}/page/{$pageSlug}",
], JSON_PRETTY_PRINT) . "\n";
