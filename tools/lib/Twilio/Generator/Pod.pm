package Twilio::Generator::Pod;

use 5.016;
use warnings;

use Text::Wrap ();

our $VERSION = '2.001';

my $POD_WIDTH = 80;
my $TWILIO    = 'https://www.twilio.com';

# The Markdown that appears in Twilio's descriptions.
my $CODE  = qr/`[^`]*`/;
my $LINK  = qr/\[[^\]]*\]\([^)\s]*\)/;
my $BOLD  = qr/[*][*].+?[*][*]/;
my $TOKEN = qr/($CODE|$LINK|$BOLD)/;

my %ESCAPE = ('<' => 'E<lt>', '>' => 'E<gt>');

sub document {
  my ($model) = @_;
  return join "\n", _top($model), _list($model), _page($model), _context($model),
    _instance($model), _answer_classes($model), _constructors(), end();
}

sub end {
  return "=head1 LICENSE\n",
    "Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.\n", "=cut\n";
}

# Everything from the spec passes through here, so that nothing in it can be read as POD.
sub text {
  my ($markdown) = @_;

  my $plain = ($markdown // q{}) =~ s/\s+/ /gr;
  $plain =~ s/\A\s+|\s+\z//g;
  return join q{}, map { _token($_) } split $TOKEN, $plain;
}

sub _token {
  my ($piece) = @_;

  if (my ($code) = $piece =~ /\A`([^`]*)`\z/) { return _code($code) }
  if (my ($label, $url) = $piece =~ /\A\[([^\]]*)\]\(([^)\s]*)\)\z/) { return _link($label, $url) }
  if (my ($bold) = $piece =~ /\A[*][*](.+)[*][*]\z/) { return 'B<' . text($bold) . '>' }
  return $piece =~ s/([<>])/$ESCAPE{$1}/gr;
}

sub _code {
  my ($code) = @_;
  return $code =~ /[<>]/ ? "C<< $code >>" : "C<$code>";
}

sub _link {
  my ($label, $url) = @_;

  # L<> reads up to the first bar as the label.
  my $shown  = text($label) =~ s/[|]/E<verbar>/gr;
  my $target = $url =~ m{\A/} ? "$TWILIO$url" : $url;
  return length $target ? "L<$shown|$target>" : $shown;
}

sub _paragraph {
  my ($text) = @_;

  # A URL must stay in one piece, and the default for a long word is to cut it.
  local $Text::Wrap::columns  = $POD_WIDTH;
  local $Text::Wrap::huge     = 'overflow';
  local $Text::Wrap::unexpand = 0;
  return Text::Wrap::wrap(q{}, q{}, $text) . "\n";
}

sub _sentence {
  my (@items) = @_;
  return $items[0] // q{} if @items < 2;

  my $final_item = pop @items;
  return join(q{, }, @items) . " and $final_item";
}

sub _top {
  my ($model) = @_;

  my @classes = map { $model->{class}{$_} =~ s/.*:://r } _classes_in_file($model);
  push @classes, map { $_->{name} } @{ $model->{answer_classes} // [] };
  my $names   = _sentence(map { "C<$_>" } @classes);
  my $about   = text($model->{description});
  my @example = _synopsis($model);

  return join "\n", "=encoding UTF-8\n", "=head1 NAME\n",
    "$model->{module} - The $model->{name} resource\n",
    @example ? ("=head1 SYNOPSIS\n", join(q{}, @example)) : (), "=head1 DESCRIPTION\n",
    length $about ? _paragraph($about) : (),
    _paragraph("This file holds $names. Methods that make a request throw "
      . 'L<Twilio::Exceptions::RestException> on an error response.');
}

sub _classes_in_file {
  my ($model) = @_;

  my @classes;
  push @classes, 'list'     if $model->{list};
  push @classes, 'page'     if defined $model->{records_key};
  push @classes, 'context'  if $model->{context};
  push @classes, 'instance' if $model->{has_instance};
  return @classes;
}

sub _synopsis {
  my ($model) = @_;

  my $list    = $model->{calls}{list};
  my $context = $model->{calls}{context};
  my $name    = "\$$model->{variable}";

  my @lines;
  if (my $side = $model->{list}) {
    push @lines, "  my $name = $list->create(" . _call_arguments($side->{create}) . ");\n"
      if $side->{create};
    push @lines, "  my $name = $list->fetch;\n"                           if $side->{fetch};
    push @lines, "  for my $name ($list->read({}, 20)) {\n    ...\n  }\n" if $side->{read};
    push @lines, "  my $name = $list->update(" . _call_arguments($side->{update}) . ");\n"
      if $side->{update};
    push @lines, "  $list->delete;\n" if $side->{delete};
  }
  if (my $side = $model->{context}) {
    push @lines, "  my $name = $context->create(" . _call_arguments($side->{create}) . ");\n"
      if $side->{create};
    push @lines, "  my $name = $context->fetch;\n" if $side->{fetch};
    push @lines, "  $context->$_(" . _call_arguments($side->{$_}) . ");\n"
      for grep { $side->{$_} } qw(patch update);
    push @lines, "  $context->delete;\n" if $side->{delete};
  }
  return if !@lines;
  return "  my \$client = Twilio::Rest::Client->new(\$account_sid, \$auth_token);\n\n", @lines;
}

sub _call_arguments {
  my ($operation) = @_;

  my @required = map { "\$$_->{name}" } @{ $operation->{required} // [] };
  return join q{, }, @required, $operation->{json} ? '\%body' : (),
    @{ $operation->{options} // [] } ? '\%options' : ();
}

sub _list {
  my ($model) = @_;
  my $side = $model->{list} or return q{};

  my $call = $model->{calls}{list};
  my @pod  = (
    "=head1 $model->{name}List\n",
    _paragraph("Returned by C<< $call >>. See also L<Twilio::ListResource>.")
  );

  push @pod, _body_method($model, 'create', $call, $side->{create}) if $side->{create};
  push @pod, _fetch_method($model, $call, $side->{fetch})           if $side->{fetch};
  push @pod, _reading($model, $call)                                if $side->{read};
  push @pod, _body_method($model, 'update', $call, $side->{update}) if $side->{update};
  push @pod, _delete_method($model, $call, $side->{delete})         if $side->{delete};
  if (my $own = ($model->{context} // {})->{own}) {
    push @pod, "=head2 get_context\n", "  my \$context = $call->get_context(\$$own);\n",
      "Returns a C<$model->{name}Context>, and makes no request.\n";
  }
  push @pod, map { _child($_) } @{ $side->{children} // [] };
  return join "\n", @pod;
}

sub _method_intro {
  my ($operation, $result) = @_;

  my $about = text($operation->{description});
  my $ends  = $about =~ /[.!?]\z/ ? q{} : q{.};
  return _paragraph(join q{ }, grep { length } (length $about ? "$about$ends" : q{}), $result);
}

sub _body_method {
  my ($model, $verb, $call, $operation) = @_;

  my $arguments = _call_arguments($operation);
  return join "\n", "=head2 $verb\n", "  my \$$model->{variable} = $call->$verb($arguments);\n",
    _method_intro($operation, _returns($model, $operation)),
    _arguments('required', $operation->{required}), _json_fields($operation->{json}),
    _arguments('options', $operation->{options});
}

# A JSON body is a hash reference with Twilio's own names, so its fields are listed as they are.
sub _json_fields {
  my ($json) = @_;
  return () if !$json;

  my $kind = $json->{required} ? 'It' : 'It can be left out. When given, it';
  my @intro =
    _paragraph("C<%body> is sent as JSON. $kind takes the names Twilio's API documentation uses.");
  return @intro if !@{ $json->{fields} };

  my @items = map { _json_field($_) } @{ $json->{fields} };
  return @intro, "Its fields are:\n", "=over\n", @items, "=back\n";
}

sub _fetch_method {
  my ($model, $call, $operation) = @_;

  my @options = @{ $operation->{options} };
  my $list    = @options ? '(\%options)' : q{};
  return join "\n", "=head2 fetch\n", "  my \$$model->{variable} = $call->fetch$list;\n",
    _method_intro($operation, _returns($model, $operation)),
    _arguments('options', \@options);
}

# Under the v1.0 standard, an answer can be another object than the resource, like
# Knowledge's UpdateKnowledge, which acknowledges with 202 what it does not finish at once.
sub _returns {
  my ($model, $operation) = @_;

  my $result = $operation->{result} or return 'Returns true.';
  my @others = map { [$_->{class} =~ s/.*:://r, $_->{codes}] } @{ $result->{others} };
  my $final  = $result->{instance} ? "$model->{name}Instance" : (pop @others)->[0];
  return "Returns a C<$final>." if !@others;

  my @chosen =
    map { "a C<$_->[0]> when Twilio answers " . _sentence(@{ $_->[1] }) =~ s/ and / or /r } @others;
  return 'Returns ' . join(q{, }, @chosen) . ", and a C<$final> otherwise.";
}

sub _json_field {
  my ($field) = @_;
  my $note = $field->{required} ? 'Required. ' : q{};
  return "=item C<$field->{name}>\n",
    _paragraph($note . _or_nothing(text($field->{description}), _choices($field->{enum})));
}

sub _arguments {
  my ($kind, $arguments) = @_;
  return () if !@{$arguments};

  my $sigil = $kind eq 'required' ? q{$} : q{};
  my @items = map { ("=item C<$sigil$_->{name}>\n", _argument_text($_)) } @{$arguments};
  return "The $kind are:\n" =~ s/required are/required values are/r, "=over\n", @items, "=back\n";
}

sub _argument_text {
  my ($argument) = @_;

  my @notes = (text($argument->{description}));
  push @notes, _choices($argument->{enum});
  push @notes, 'An array reference.' if $argument->{array};
  push @notes,
    'A string, or an object with an C<epoch> method. See L<Twilio::Serialize/iso8601_date_time>.'
    if ($argument->{writer} // q{}) =~ /date/;
  push @notes, 'A hash or array reference, or a string of JSON.'
    if ($argument->{writer} // q{}) eq 'json_object';
  return _paragraph(_or_nothing(@notes));
}

sub _or_nothing {
  my (@notes) = @_;
  my @found = grep { length } @notes;
  return @found ? join q{ }, @found : 'No description in the specification.';
}

sub _choices {
  my ($enum) = @_;
  return q{} if !$enum || !@{$enum};

  my @choices = map { _code($_) } @{$enum};
  return "Must be $choices[0]." if @choices == 1;

  my $final_choice = pop @choices;
  return 'One of ' . join(q{, }, @choices) . " or $final_choice.";
}

sub _reading {
  my ($model, $call) = @_;

  my $operation = $model->{list}{read};
  my @required  = @{ $operation->{required} // [] };
  my $taken     = join q{}, map { "\$$_->{name}, " } @required;
  my @kept =
    @required
    ? _paragraph('The required values are kept with the options, so C<page> takes them there.')
    : ();
  return join "\n", "=head2 read\n",
    "  my \@records = $call->read($taken\\%options, \$limit, \$page_size);\n",
    _method_intro($operation, 'Returns the records as a list, fetching as many pages as it needs.'),
    _arguments('required', \@required), @kept,
    _arguments('options', $operation->{filters}), "=head2 stream\n",
    "  my \$stream = $call->stream($taken\\%options, \$limit, \$page_size);\n",
    "Takes the same arguments as L</read>, and returns a L<Twilio::Stream>.\n", "=head2 page\n",
    _page_pod($model, $call), "=head2 get_page\n",
    "  my \$page = $call->get_page(\$url);\n", "Fetches the page at a URL given by Twilio.\n";
}

sub _page_pod {
  my ($model, $call) = @_;

  return ("  my \$page = $call->page(\\%options, \$page_size, \$page_token, \$page_number);\n",
    "Fetches one page, and returns a L<Twilio::Page>.\n")
    if !$model->{v1_standard};
  return (
    "  my \$page = $call->page(\\%options, \$page_size, \$page_token);\n",
    "Fetches one page, and returns a L<Twilio::TokenPaginationPage>. This API pages by token, "
      . "so there is no page number.\n"
  );
}

sub _child {
  my ($child) = @_;

  my @pod = ("=head2 $child->{mount}\n");
  if ($child->{singleton}) {
    push @pod, "  my \$context = \$object->$child->{mount};\n";
  }
  else {
    push @pod, "  my \$list = \$object->$child->{mount};\n";
    push @pod, "  my \$context = \$object->$child->{mount}(\$$child->{own});\n"
      if defined $child->{own};
  }
  return join "\n", @pod, "See L<$child->{module}>.\n";
}

sub _page {
  my ($model) = @_;
  return q{} if !defined $model->{records_key};

  return join "\n", "=head1 $model->{name}Page\n",
    "A L<Twilio::Page> of C<$model->{name}Instance> objects.\n", "=head2 records_key\n",
    "=head2 build_instance\n",                                   "Used by L<Twilio::Page>.\n";
}

sub _context {
  my ($model) = @_;
  my $side = $model->{context} or return q{};

  my $call = $model->{calls}{context};
  my @pod  = (
    "=head1 $model->{name}Context\n",
    _paragraph(
      "Returned by C<< $call >>. It makes no request until one of these methods is called.")
  );

  push @pod, _body_method($model, 'create', $call, $side->{create}) if $side->{create};
  push @pod, _fetch_method($model, $call, $side->{fetch})           if $side->{fetch};
  push @pod, _body_method($model, $_, $call, $side->{$_}) for grep { $side->{$_} } qw(patch update);
  push @pod, _delete_method($model, $call, $side->{delete}) if $side->{delete};
  push @pod, map { _child($_) } @{ $side->{children} // [] };
  return join "\n", @pod;
}

sub _delete_method {
  my ($model, $call, $delete) = @_;

  my @options = @{ $delete->{options} // [] };
  my $list    = @options ? '(\%options)' : q{};
  return join "\n", "=head2 delete\n", "  $call->delete$list;\n",
    _method_intro($delete, _returns($model, $delete)), _arguments('options', \@options);
}

sub _instance {
  my ($model) = @_;
  return q{} if !$model->{has_instance};

  my @pod = ("=head1 $model->{name}Instance\n", "See also L<Twilio::InstanceResource>.\n");
  if ($model->{context}) {
    my @methods =
      map { "C<$_>" } grep { $model->{context}{$_} } qw(create fetch patch update delete);
    push @methods, map { "C<$_->{mount}>" } @{ $model->{context}{children} // [] };
    push @pod,
      _paragraph('It has ' . _sentence(@methods) . ', which work as they do on the context.')
      if @methods;
  }
  push @pod, _field_list($model->{fields});
  return join "\n", @pod;
}

sub _field_list {
  my ($fields) = @_;
  return () if !@{$fields};
  return "Its fields are:\n", "=over\n",
    (map { ("=item $_->{method}\n", _field_text($_)) } @{$fields}), "=back\n";
}

sub _answer_classes {
  my ($model) = @_;

  my @pod;
  for my $answer (@{ $model->{answer_classes} // [] }) {
    my $methods = _sentence(map { "C<$_>" } @{ $answer->{methods} });
    push @pod, join "\n", "=head1 $answer->{name}\n",
      _paragraph("Returned by $methods, for an answer that is not a $model->{name}. "
        . 'See also L<Twilio::InstanceResource>.'),
      _field_list($answer->{fields});
  }
  return @pod;
}

sub _field_text {
  my ($field) = @_;

  my $reader = $field->{reader} // q{};
  my @notes  = (text($field->{description}), _choices($field->{enum}));
  push @notes, 'A L<Time::Piece> object in UTC. See L<Twilio::Deserialize/date_time>.'
    if $reader eq 'date_time';
  push @notes, 'A L<Twilio::Base::PhoneNumberCapabilities> object.'
    if $reader eq 'phone_number_capabilities';
  return _paragraph(_or_nothing(@notes));
}

sub _constructors {
  return "=head1 CONSTRUCTORS\n", "=head2 new\n",
    _paragraph(
    'Objects here come from the methods above, so there is no need to call C<new> directly.');
}

1;
