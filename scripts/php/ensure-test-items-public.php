<?php
/**
 * Make all items and item sets public (test stack — anonymous browse / press-material page).
 */
declare(strict_types=1);

use Omeka\Entity\User;

require '/var/www/html/bootstrap.php';

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

$itemSets = 0;
foreach ($api->search('item_sets', ['limit' => 500])->getContent() as $set) {
    if (!$set->isPublic()) {
        $api->update('item_sets', $set->id(), ['o:is_public' => true], [], ['isPartial' => true]);
        $itemSets++;
    }
}

$items = 0;
$media = 0;
foreach ($api->search('items', ['limit' => 5000])->getContent() as $item) {
    $payload = [];
    if (!$item->isPublic()) {
        $payload['o:is_public'] = true;
    }
    $mediaUpdates = [];
    foreach ($item->media() as $medium) {
        if (!$medium->isPublic()) {
            $mediaUpdates[] = [
                'o:id' => $medium->id(),
                'o:is_public' => true,
            ];
        }
    }
    if ($mediaUpdates) {
        $payload['o:media'] = $mediaUpdates;
        $media += count($mediaUpdates);
    }
    if ($payload) {
        $api->update('items', $item->id(), $payload, [], ['isPartial' => true]);
        $items++;
    }
}

echo json_encode([
    'item_sets_published' => $itemSets,
    'items_updated' => $items,
    'media_published' => $media,
], JSON_PRETTY_PRINT) . "\n";
