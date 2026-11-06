<?php
// Runs real twilio-php and writes what it produces into t/data, so the Perl tests can compare
// against it without PHP. Usage: php tools/vectors/generate.php /path/to/twilio-php

if ($argc !== 2) {
    fwrite(STDERR, "Usage: php generate.php /path/to/twilio-php\n");
    exit(2);
}
require $argv[1] . '/src/Twilio/autoload.php';

use Twilio\TwiML\VoiceResponse;

$output = __DIR__ . '/../../t/data';

// Perl sorts attributes because its hashes have no order, so PHP's order is removed here. This
// works on the text, because parsing it again would change what twilio-php wrote: an empty
// element would collapse, and a name with a prefix would be read as a namespace.
function sortedXml(string $xml): string {
    return preg_replace_callback(
        '/<([^\s<>\/?]+)((?:\s+[^\s=]+="[^"]*")+)(\/?)>/',
        function (array $tag): string {
            preg_match_all('/\s+([^\s=]+)="([^"]*)"/', $tag[2], $found, PREG_SET_ORDER);
            usort($found, fn(array $a, array $b): int => strcmp($a[1], $b[1]));
            $attributes = array_map(fn(array $one): string => " {$one[1]}=\"{$one[2]}\"", $found);
            return '<' . $tag[1] . implode('', $attributes) . $tag[3] . '>';
        },
        $xml
    );
}

function build($parent, array $node): void {
    $child = $parent->addChild($node['name'], $node['value'] ?? null, $node['attributes'] ?? []);
    fill($child, $node);
}

function fill($element, array $node): void {
    foreach ($node['children'] ?? [] as $child) {
        if (is_string($child)) {
            $element->append($child);
        } else {
            build($element, $child);
        }
    }
}

// Each case is a tree that both languages can build with the generic methods.
$cases = json_decode(file_get_contents(__DIR__ . '/twiml-core.json'), true, 512, JSON_THROW_ON_ERROR);

foreach ($cases as &$case) {
    $response = new VoiceResponse();
    fill($response, $case);
    $case['expected'] = sortedXml((string) $response);
}
unset($case);

$flags = JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR;
file_put_contents("$output/vectors-twiml-core.json", json_encode($cases, $flags) . "\n");
echo count($cases), " TwiML core vectors\n";
