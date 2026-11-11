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
  PREREQ_PM          => {
    'Carp'            => '0',
    'Digest::SHA'     => '0',
    'HTTP::Tiny'      => '0.076',
    'IO::Socket::SSL' => '1.968',
    'JSON::PP'        => '0',
    'MIME::Base64'    => '0',
    'Mozilla::CA'     => '0',
    'Net::SSLeay'     => '1.49',
    'overload'        => '0',
    'parent'          => '0',
    'POSIX'           => '0',
    'Scalar::Util'    => '0',
    'Time::Local'     => '0',
    'Time::Piece'     => '0',
  },
  test       => { RECURSIVE_TEST_FILES => 1 },
  clean      => { FILES                => 'Twilio-* cover_db' },
  META_MERGE => {
    'meta-spec'    => { version => 2 },
    dynamic_config => 0,
    no_index       => { directory => ['t', 'xt'] },
    prereqs        => {

      # Crypt::OpenSSL::RSA signs for Public Key Client Validation only. 0.33 and 0.34 work
      # too; 0.35 to 0.37 refused the PKCS#1 v1.5 padding that RS256 needs.
      runtime => { recommends => { 'Cpanel::JSON::XS' => '0', 'Crypt::OpenSSL::RSA' => '0.38' } },
      develop => {
        requires => {
          'Perl::Critic'        => '0',
          'Perl::Tidy'          => '20260826',
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
