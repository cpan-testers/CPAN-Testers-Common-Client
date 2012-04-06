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


done_testing;
