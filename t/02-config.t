use strict;
use warnings;
use Test::More;

use_ok( 'CPAN::Testers::Common::Client::Config' );

my $config = CPAN::Testers::Common::Client::Config->new(
        prompt => sub { ok(1, 'prompt called') },
        warn   => sub { ok(1, 'warn called')   },
        print  => sub { ok(1, 'print called')  },
);

ok $config, 'config client spawns';

isa_ok $config,
       'CPAN::Testers::Common::Client::Config',
       'config client has the proper class';

can_ok $config,
       qw( get_config_dir get_config_filename myprompt mywarn myprint
           setup read email_from edit_report send_report send_duplicates
           transport transport_name transport_args
       );

$config->myprompt;
$config->mywarn;
$config->myprint;

ok 1, 'still here';

done_testing;
