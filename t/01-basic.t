use strict;
use warnings;
use Test::More;

my $resource = 'cpan:///distfile/RJBS/CPAN-Metabase-Fact-0.001.tar.gz';

my $client = CPAN::Testers::Common::Client->new(
    resource => $resource,
);
ok $client, 'client spawns';

isa_ok $client, 'CPAN::Testers::Common::Client', 'client has the proper class';

is $client->resource, $resource, 'getting resource';

$resource = 'cpan:///distfile/DAGOLDEN/Metabase-Fact-0.021.tar.gz';

my $res = $client->resource( $resource );
is $res, $client, 'resource() should return the main object';
is $client->resource, $resource, 'setting resource';

done_testing;
