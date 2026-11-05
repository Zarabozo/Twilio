use 5.016;
use warnings;

use ExtUtils::MakeMaker 6.64;

WriteMakefile(
  NAME               => 'Twilio',
  AUTHOR             => 'Francisco Zarabozo <zarabozo@cpan.org>',
  VERSION_FROM       => 'lib/Twilio.pm',
  ABSTRACT_FROM      => 'lib/Twilio.pm',
  LICENSE            => 'mit',
  MIN_PERL_VERSION   => '5.016',
  CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => '6.64' },
  TEST_REQUIRES      => { 'Test::More'          => '0.98' },
  PREREQ_PM          => {},
  test               => { RECURSIVE_TEST_FILES => 1 },
  clean              => { FILES                => 'Twilio-* cover_db' },
  META_MERGE         => {
    'meta-spec'    => { version => 2 },
    dynamic_config => 0,
    no_index       => { directory => ['t', 'xt'] },
    prereqs        => {
      develop => {
        requires => {
          'Perl::Critic'        => '0',
          'Perl::Tidy'          => '0',
          'Test::Pod'           => '1.52',
          'Test::Pod::Coverage' => '1.10',
        },
      },
    },
    resources => {
      license    => ['https://opensource.org/license/mit'],
      homepage   => 'https://github.com/Zarabozo/Twilio',
      bugtracker => { web => 'https://github.com/Zarabozo/Twilio/issues' },
      repository => {
        type => 'git',
        url  => 'https://github.com/Zarabozo/Twilio.git',
        web  => 'https://github.com/Zarabozo/Twilio',
      },
    },
  },
);
