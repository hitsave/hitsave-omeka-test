<?php
declare(strict_types=1);

function omekaPropertyId($api, string $term): ?int
{
    $rows = $api->search('properties', ['term' => $term])->getContent();
    return $rows ? (int) $rows[0]->id() : null;
}

function omekaResourceClassId($api, string $term): ?int
{
    $rows = $api->search('resource_classes', ['term' => $term])->getContent();
    return $rows ? (int) $rows[0]->id() : null;
}

function syncResourceTemplate($api, array $spec): int
{
    $label = $spec['label'] ?? 'Resource template';
    $existing = $api->search('resource_templates', ['label' => $label])->getContent();
    $classTerm = $spec['resource_class_term'] ?? null;
    $classId = $classTerm ? omekaResourceClassId($api, $classTerm) : null;
    $props = [];
    foreach ($spec['properties'] ?? [] as $row) {
        $term = $row['term'] ?? '';
        if ($term === 'curation:location') {
            continue;
        }
        $pid = omekaPropertyId($api, $term);
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
            'o:is_private' => !empty($row['private']),
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
        return (int) $existing[0]->id();
    }
    $created = $api->create('resource_templates', $payload)->getContent();
    return (int) $created->id();
}

function syncResourceTemplatesFromMirror($api, array $mirror): array
{
    $specs = $mirror['resource_templates'] ?? [];
    if (!$specs && isset($mirror['resource_template'])) {
        $specs = [$mirror['resource_template']];
    }
    $synced = [];
    foreach ($specs as $spec) {
        $id = syncResourceTemplate($api, $spec);
        $synced[] = ['label' => $spec['label'] ?? '', 'test_id' => $id];
    }
    return $synced;
}
