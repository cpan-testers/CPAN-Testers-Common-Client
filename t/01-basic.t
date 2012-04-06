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
    'Your friendly CPAN Testers client version ' . $CPAN::Testers::Common::Client::VERSION,
    'got the default "via" information'
);

like(
    $client->comments,
    qr/this report is from an automated|none provided/,
    'got the default comment'
);

my $data;
ok $data = $client->populate, 'could populate';

#use DDP;

#p $data;

done_testing;
