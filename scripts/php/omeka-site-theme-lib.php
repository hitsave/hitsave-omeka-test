<?php
declare(strict_types=1);

/** Shared HitSaveArchive site theme settings (test bootstrap + prod mirror apply). */

function hitsaveDefaultResourcePageBlocks(): array
{
    return [
        'items' => [
            'full_width_main' => ['mediaList'],
            'main' => ['values', 'itemSets'],
            'right' => ['mediaList'],
        ],
    ];
}

function hitsaveDefaultThemeSettings(): array
{
    return [
        'nav_layout' => 'dropdown',
        'nav_show_levels' => 1,
        'nav_depth' => 0,
        'truncate_body_property' => 'ellipsis',
        'footer' => (
            'Run by Hit Save!, a 501(c)(3) non-profit dedicated to the preservation '
            . 'of video games, their history, and related physical and digital materials.'
        ),
        'resource_page_blocks' => hitsaveDefaultResourcePageBlocks(),
    ];
}

function archiveThemeHomepagePage(string $path): array
{
    $out = ['slug' => 'intro', 'title' => 'Introduction'];
    if (!is_readable($path)) {
        return $out;
    }
    $yaml = file_get_contents($path);
    if (preg_match('/^\s*homepage:\s*\n(?:^\s+.+\n)*?^\s*slug:\s*(\S+)/m', $yaml, $m)) {
        $out['slug'] = trim($m[1], " \t\"'");
    }
    if (preg_match('/^\s*homepage:\s*\n(?:^\s+.+\n)*?^\s*hero_title:\s*(.+)$/m', $yaml, $m)) {
        $out['title'] = trim($m[1], " \t\"'");
    }
    return $out;
}

/** Public intro page + o:homepage for HitSaveArchive discovery hub (no prod mirror required). */
function ensureSiteHomepageHub($api, int $siteId, string $archiveThemePath): array
{
    $spec = archiveThemeHomepagePage($archiveThemePath);
    $slug = $spec['slug'];
    $title = $spec['title'];

    $existing = $api->search('site_pages', ['site_id' => $siteId, 'slug' => $slug])->getContent();
    if ($existing) {
        $pageId = (int) $existing[0]->id();
        $created = false;
    } else {
        $page = $api->create('site_pages', [
            'o:site' => ['o:id' => $siteId],
            'o:slug' => $slug,
            'o:title' => $title,
            'o:is_public' => true,
            'o:block' => [],
        ])->getContent();
        $pageId = (int) $page->id();
        $created = true;
    }

    $sites = $api->search('sites', ['id' => $siteId])->getContent();
    $site = $sites[0] ?? null;
    $currentHomeId = $site && $site->homepage() ? (int) $site->homepage()->id() : 0;
    $homepageUpdated = false;
    if ($currentHomeId !== $pageId) {
        $api->update('sites', $siteId, [
            'o:homepage' => ['o:id' => $pageId],
        ], [], ['isPartial' => true]);
        $homepageUpdated = true;
    }

    return [
        'page_id' => $pageId,
        'page_slug' => $slug,
        'page_created' => $created,
        'homepage_updated' => $homepageUpdated,
    ];
}

function archiveThemeFamilySettings(string $path): array
{
    if (!is_readable($path)) {
        return [];
    }
    $yaml = file_get_contents($path);
    $map = [
        'org_url' => 'hitsave_org_url',
        'preserve_url' => 'hitsave_preserve_url',
        'support_url' => 'hitsave_support_url',
        'get_involved_url' => 'hitsave_get_involved_url',
        'archive_label' => 'hitsave_archive_label',
    ];
    $out = [];
    foreach ($map as $yamlKey => $settingKey) {
        if (preg_match('/^\s*' . preg_quote($yamlKey, '/') . ':\s*(.+)$/m', $yaml, $m)) {
            $out[$settingKey] = trim($m[1], " \t\"'");
        }
    }
    if (preg_match('/^\s*color_mode:\s*(\S+)/m', $yaml, $m)) {
        $mode = strtolower(trim($m[1], " \t\"'"));
        if (in_array($mode, ['dark', 'light'], true)) {
            $out['hitsave_color_mode'] = $mode;
        }
    }
    if (preg_match('/^\s*logo_url:\s*([^\r\n]*)/m', $yaml, $m)) {
        $url = trim($m[1], " \t\"'");
        if ($url !== '' && strtolower($url) !== 'null' && preg_match('#^(https?://|/)#', $url)) {
            $out['hitsave_logo_url'] = $url;
        }
    }
    if (preg_match('/^\s*hero_title:\s*(.+)$/m', $yaml, $m)) {
        $out['hitsave_hero_title'] = trim($m[1], " \t\"'");
    }
    if (preg_match('/^\s*hero_tagline:\s*(.+)$/m', $yaml, $m)) {
        $out['hitsave_hero_tagline'] = trim($m[1], " \t\"'");
    }
    if (preg_match('/^\s*slug:\s*(\S+)/m', $yaml, $m)) {
        $out['hitsave_homepage_slug'] = trim($m[1]);
    }
    if (preg_match('/^\s*truncate_body_property:\s*(\S+)/m', $yaml, $m)) {
        $style = trim($m[1], " \t\"'");
        if (in_array($style, ['full', 'fadeout', 'ellipsis'], true)) {
            $out['truncate_body_property'] = $style;
        }
    }
    $out['hitsave_hide_legacy_intro'] = '1';
    return $out;
}

function applyThemeSettings($themes, $siteSettings, $blockLayoutManager, int $siteId, string $themeName, array $settings): void
{
    $theme = $themes->getTheme($themeName);
    if (!$theme) {
        throw new RuntimeException("Theme not installed: {$themeName}");
    }
    $key = $theme->getSettingsKey();
    $current = $siteSettings->get($key, null, $siteId) ?: [];
    $merged = array_merge($current, [
        'nav_layout' => $settings['nav_layout'] ?? 'dropdown',
        'nav_show_levels' => $settings['nav_show_levels'] ?? 1,
        'nav_depth' => $settings['nav_depth'] ?? 0,
        'footer' => $settings['footer'] ?? '',
        'hitsave_color_mode' => $settings['hitsave_color_mode'] ?? null,
        'hitsave_logo_url' => $settings['hitsave_logo_url'] ?? null,
        'hitsave_org_url' => $settings['hitsave_org_url'] ?? null,
        'hitsave_preserve_url' => $settings['hitsave_preserve_url'] ?? null,
        'hitsave_support_url' => $settings['hitsave_support_url'] ?? null,
        'hitsave_get_involved_url' => $settings['hitsave_get_involved_url'] ?? null,
        'hitsave_archive_label' => $settings['hitsave_archive_label'] ?? null,
        'hitsave_hero_title' => $settings['hitsave_hero_title'] ?? null,
        'hitsave_hero_tagline' => $settings['hitsave_hero_tagline'] ?? null,
        'hitsave_homepage_slug' => $settings['hitsave_homepage_slug'] ?? null,
        'hitsave_hide_legacy_intro' => $settings['hitsave_hide_legacy_intro'] ?? null,
        'truncate_body_property' => $settings['truncate_body_property'] ?? null,
    ]);
    foreach (array_keys($merged) as $settingKey) {
        if ($merged[$settingKey] === null) {
            unset($merged[$settingKey]);
        }
    }
    if (!isset($settings['hitsave_logo_url'])) {
        unset($merged['hitsave_logo_url']);
    }
    if (!empty($settings['resource_page_blocks'])) {
        $merged['resource_page_blocks'] = $blockLayoutManager->standardizeResourcePageBlocks(
            $settings['resource_page_blocks']
        );
    }
    $siteSettings->set($key, $merged, $siteId);
}
