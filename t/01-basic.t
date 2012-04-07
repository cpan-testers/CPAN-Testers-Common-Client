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



#===========================================
# second run -- passing more stuff around
#===========================================

$resource = 'cpan:///distfile/DAGOLDEN/CPAN-Reporter-0.003.tar.bz2';

ok $client = CPAN::Testers::Common::Client->new(
    resource => $resource,
    author   => 'David Golden',
    via      => 'AwesomeClient 2.0 pre-beta',
    grade    => 'fail',
    comments => 'oh, noes!',

    configure_output => 'TUPTUO ERUGIFNOC',
    build_output     => 'TUPTUO DLIUB',
    test_output      => 'ZOMG THIS TEST FAILED',

    prereqs => {
       runtime   => { requires => { 'Test::More' => 0 }  },
       build     => { requires => { 'Test::Most' => 0, 'Test::LongString' => 0 } },
       configure => { requires => { 'Test::Builder' => 1.2 } },
    },
), 'could create a new object';


ok $email = $client->email, 'got the email on the second run (auto populates)';

like $email, qr/^Dear David Golden,/, 'addressing author';
like $email, qr/created by AwesomeClient 2.0 pre-beta/, 'client label';
like $email, qr/oh, noes!/, 'tester comments';
like $email, qr/ZOMG THIS TEST FAILED/, 'test output';
like $email, qr/Test::More/, 'runtime prereq';
like $email, qr/Test::Most/, 'build prereq 1';
like $email, qr/Test::LongString/, 'build_prereq 2';
like $email, qr/Test::Builder/, 'configure_prereq';


done_testing;
