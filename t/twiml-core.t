use 5.016;
use warnings;
use utf8;

use JSON::PP ();
use Test::More;

use Twilio::TwiML::GenericNode;

my $DECLARATION = qq{<?xml version="1.0" encoding="UTF-8"?>\n};

subtest 'the same output as twilio-php' => sub {
  my $vectors = read_vectors('t/data/vectors-twiml-core.json');
  ok(@{$vectors} > 10, 'vectors were read');

  for my $vector (@{$vectors}) {
    my $response = Twilio::TwiML::GenericNode->new('Response');
    fill($response, $vector);
    my $expected = $vector->{expected};
    utf8::encode($expected);

    is($response->as_xml, $expected, $vector->{description});
  }
};

subtest 'nest and append return different things' => sub {
  my $response = response();
  my $child    = Twilio::TwiML::GenericNode->new('Say', 'Hi');

  is($response->nest($child), $child, 'nest gives the child');

  my $back = $response->append('text');
  is($back, $response, 'append gives the element');
};

subtest 'add_child' => sub {
  my $response = response();
  my $child    = $response->add_child('Thing', 'text', { a => 1 });

  isa_ok($child, 'Twilio::TwiML::GenericNode');
  $child->add_child('Inner');
  is(body($response), '<Response><Thing a="1">text<Inner/></Thing></Response>', 'written');
};

subtest 'set_attribute' => sub {
  my $response = response();
  my $back     = $response->set_attribute(a => 'one');

  is($back, $response, 'it returns the element');
  $response->set_attribute(a => 'two');
  is(body($response), '<Response a="two"/>', 'the last value stays');
};

subtest 'the attributes passed in are copied' => sub {
  my %attributes = (a => 1);
  my $element    = Twilio::TwiML::GenericNode->new('Thing', undef, \%attributes);
  $element->set_attribute(b => 2);

  is_deeply(\%attributes, { a => 1 }, 'the caller keeps its hash');
};

subtest 'attribute values' => sub {
  my @cases = (
    ['a true reference',  \1,                'true'],
    ['a false reference', \0,                'false'],
    ['a JSON true',       JSON::PP::true(),  'true'],
    ['a JSON false',      JSON::PP::false(), 'false'],
    ['a list',            ['a', 'b', 'c'],   'a b c'],
    ['an empty list',     [],                q{}],
    ['a number',          20,                '20'],
    ['zero',              0,                 '0'],
    ['an empty string',   q{},               q{}],
  );

  for my $case (@cases) {
    my ($name, $value, $expected) = @{$case};
    my $element = Twilio::TwiML::GenericNode->new('T', undef, { a => $value });
    is(body($element), qq{<T a="$expected"/>}, $name);
  }
};

subtest 'an attribute with no value is left out' => sub {
  my $element = Twilio::TwiML::GenericNode->new('T', undef, { a => undef, b => 1 });
  is(body($element), '<T b="1"/>', 'only the other one');
};

subtest 'an element converts to its document' => sub {
  my $response = response();

  is("$response", $response->as_xml, 'in a string');
  ok($response, 'it is true');
  like($response->as_xml, qr/\A\Q$DECLARATION\E<Response\/>\n\z/, 'declaration and final newline');
};

subtest 'text arrives as characters or as bytes' => sub {
  my $characters = "código";
  my $bytes      = $characters;
  utf8::encode($bytes);

  my $from_characters = Twilio::TwiML::GenericNode->new('Say', $characters);
  my $from_bytes      = Twilio::TwiML::GenericNode->new('Say', $bytes);

  is($from_characters->as_xml, $from_bytes->as_xml, 'the same document');
  ok(!utf8::is_utf8($from_characters->as_xml), 'in bytes');
};

subtest 'text can be a number or an object that converts' => sub {
  my $element = Twilio::TwiML::GenericNode->new('Say', 0);
  is(body($element), '<Say>0</Say>', 'zero is text');
};

done_testing;

sub response {
  return Twilio::TwiML::GenericNode->new('Response');
}

sub body {
  my ($element) = @_;
  return $element->as_xml =~ s/\A\Q$DECLARATION\E//r =~ s/\n\z//r;
}

sub fill {
  my ($element, $node) = @_;

  for my $child (@{ $node->{children} // [] }) {
    if (ref $child) {
      fill($element->add_child($child->{name}, $child->{value}, $child->{attributes}), $child);
    }
    else {
      $element->append($child);
    }
  }
  return;
}

sub read_vectors {
  my ($file) = @_;

  open my $handle, '<:raw', $file or die "Cannot read $file: $!\n";
  my $content = do { local $/ = undef; <$handle> };
  close $handle or die "Cannot read $file: $!\n";
  return JSON::PP->new->utf8->decode($content);
}
