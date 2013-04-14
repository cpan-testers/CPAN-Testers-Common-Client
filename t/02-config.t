use strict;
use warnings;
use Test::More;

use_ok( 'CPAN::Testers::Common::Client::Config' );

my $config = CPAN::Testers::Common::Client::Config->new(
        myprompt => sub { ok(1, 'prompt called') },
        mywarn   => sub { ok(1, 'warn called') },
);

ok $config, 'config client spawns';

isa_ok $config,
       'CPAN::Testers::Common::Client::Config',
       'config client has the proper class';

can_ok $config,
       qw( get_config_dir get_config_filename )
;

ok 1, 'still here';

done_testing;
