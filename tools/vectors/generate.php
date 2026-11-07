<?php
// Runs real twilio-php and writes what it produces into t/data, so the Perl tests can compare
// against it without PHP. Usage: php tools/vectors/generate.php /path/to/twilio-php

if ($argc !== 2) {
    fwrite(STDERR, "Usage: php generate.php /path/to/twilio-php\n");
    exit(2);
}
require $argv[1] . '/src/Twilio/autoload.php';

use Twilio\Security\RequestValidator;
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

// These two names are wrong in twilio-php, whose tests do not cover them: twilio-python and
// Twilio's documentation use the corrected ones, and so does tools/extract-twiml.pl.
function corrected(string $xml): string {
    return str_replace([' for_="', ' xml:Lang="'], [' for="', ' xml:lang="'], $xml);
}

// Each element, with every attribute and child, so nothing depends on the extraction being right.
$elements = json_decode(file_get_contents(__DIR__ . '/../twiml-elements.json'), true, 512, JSON_THROW_ON_ERROR);
$vectors = [];
foreach ($elements as $name => $element) {
    // The autoloader reads an underscore as a directory, so it cannot find Echo_.
    require_once $argv[1] . '/src/Twilio/TwiML/' . str_replace('::', '/', $element['php_class']) . '.php';
    $class = 'Twilio\\TwiML\\' . str_replace('::', '\\', $element['php_class']);
    $arguments = $element['value'] !== null ? ["text of $name"] : [];
    $object = new $class(...$arguments);

    $vector = ['class' => $name, 'arguments' => $arguments, 'attributes' => [], 'setters' => [], 'children' => []];
    foreach ($element['attributes'] as $attribute) {
        $text = 'v_' . $attribute['name'];
        if ($attribute['type'] === 'boolean') {
            // A setter takes a string, so PHP would turn true into "1". The attributes array
            // writes "true", which is what Twilio documents.
            $object->{$attribute['setter']}('true');
            $given = 1;
        } elseif ($attribute['type'] === 'list') {
            $object->{$attribute['setter']}("$text second");
            $given = [$text, 'second'];
        } else {
            $object->{$attribute['setter']}($text);
            $given = $text;
        }
        $vector['attributes'][$attribute['name']] = $given;
        $vector['setters'][$attribute['method']] = $given;
    }
    foreach ($element['children'] as $child) {
        $childArguments = $child['value'] !== null ? ['text of ' . $child['method']] : [];
        if ($child['has_attributes']) {
            $childArguments[] = ['extra' => 'one'];
        }
        $object->{$child['php_method']}(...$childArguments);
        $vector['children'][] = ['method' => $child['method'], 'arguments' => $childArguments];
    }
    $vector['attributes'] = (object) $vector['attributes'];
    $vector['setters'] = (object) $vector['setters'];
    $vector['expected'] = sortedXml(corrected((string) $object));
    $vectors[] = $vector;
}

$flags = JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR;
file_put_contents("$output/vectors-twiml-core.json", json_encode($cases, $flags) . "\n");
echo count($cases), " TwiML core vectors\n";
file_put_contents("$output/vectors-twiml-elements.json", json_encode($vectors, $flags) . "\n");
echo count($vectors), " TwiML element vectors\n";

// What the request validator must produce.
$cases = json_decode(file_get_contents(__DIR__ . '/request-validator.json'), true, 512, JSON_THROW_ON_ERROR);
$validator = new RequestValidator($cases['token']);

foreach ($cases['signatures'] as &$case) {
    $case['data'] = (object) $case['data'];
    $case['expected'] = $validator->computeSignature($case['url'], (array) $case['data'], $case['algorithm'] ?? null);
}
unset($case);

foreach ($cases['validations'] as &$case) {
    $signer = new RequestValidator($case['signed_token'] ?? $cases['token']);
    $signature = $signer->computeSignature($case['signed'], $case['signed_data'] ?? [], $case['signed_algorithm'] ?? null);
    $case['signature'] = $signature;
    $case['expected'] = $validator->validate($signature, $case['url'], $case['data'] ?? [], $case['algorithm'] ?? null);
}
unset($case);

foreach ($cases['bodies'] as &$case) {
    $case['expected'] = RequestValidator::computeBodyHash($case['body']);
}
unset($case);

foreach ($cases['body_validations'] as &$case) {
    $url = 'https://a.test/x?foo=1&bodySHA256=' . RequestValidator::computeBodyHash($case['url_body']);
    $case['url'] = $url;
    $case['signature'] = $validator->computeSignature($url);
    $case['expected'] = $validator->validate($case['signature'], $url, $case['body']);
}
unset($case);

$cases['settings_headers'] = array_map(
    fn(string $header): array => ['header' => $header, 'expected' => RequestValidator::getSignatureAlgorithm($header)],
    $cases['settings_headers']
);

file_put_contents("$output/vectors-request-validator.json", json_encode($cases, $flags) . "\n");
echo count($cases['signatures']) + count($cases['validations']) + count($cases['bodies'])
    + count($cases['body_validations']) + count($cases['settings_headers']), " request validator vectors\n";
