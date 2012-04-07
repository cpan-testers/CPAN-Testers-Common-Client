use strict;
use warnings;
use Test::More;
use CPAN::Testers::Common::Client;

my $resource = 'cpan:///distfile/RJBS/CPAN-Metabase-Fact-0.001.tar.gz';

my $client = CPAN::Testers::Common::Client->new(
    resource => $resource,
    grade    => 'pass',
);
ok $client, 'client spawns';

isa_ok $client, 'CPAN::Testers::Common::Client', 'client has the proper class';

is $client->author, 'RJBS', 'got the proper author from resource';

is $client->distname, 'CPAN-Metabase-Fact-0.001', 'got proper distname';

is(
    $client->via,
    'your friendly CPAN Testers client version ' . $CPAN::Testers::Common::Client::VERSION,
    'got the default "via" information'
);

like(
    $client->comments,
    qr/this report is from an automated|none provided/,
    'got the default comment'
);

my $data;
ok $data = $client->populate, 'could populate';
is ref $data, 'HASH', 'got back a hash reference';

my @facts = qw(
        TestSummary TestOutput TesterComment
        Prereqs InstalledModules
        PlatformInfo PerlConfig TestEnvironment
        LegacyReport
    );

foreach my $fact (@facts) {
  ok exists $data->{$fact}, "found data for '$fact' fact";
}

my $data2;
ok $data2 = $client->metabase_data, 'got metabase_data';
is_deeply $data, $data2, 'metabase_data() returns the same (cached) data structure';

ok my $email = $client->email, 'could retrieve the email';

ok length $email, 'email is not empty';

foreach my $section ( 'TESTER COMMENTS', 'PROGRAM OUTPUT',
                      'PREREQUISITES', 'ENVIRONMENT AND OTHER CONTEXT'
) {
    like $email, qr/$section/, "standard email section $section is shown";
}

$client = CPAN::Testers::Common::Client->new(
    resource => $resource,
    grade    => 'pass',
);

done_testing;
