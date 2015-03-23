use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

use_ok( 'CPAN::Testers::Common::Client::Config' );

my $td = tempdir(File::Spec->catdir('t', 'cf XXXX'), CLEANUP => 1);
to_file(File::Spec->catfile($td, 'config.ini'), <<'EOF');
edit_report=default:ask/no pass/na:no
email_from=bogus@cpan.org
send_report=default:ask/yes pass/na:yes
transport=Metabase uri https://metabase.cpantesters.org/api/v1/ id_file metabase_id.json
EOF
my $id_file = File::Spec->catfile($td, 'metabase_id.json');
to_file($id_file, '[]');
$ENV{PERL_CPAN_REPORTER_DIR} = $td;

sub to_file {
    my ($file, $text) = @_;
    open my $fh, '>', $file or die "$file: $!";
    print $fh $text;
    close $fh;
}

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

for my $method (qw(myprompt mywarn myprint read)) {
    eval { $config->$method };
    is $@, '', $method;
}

my %args = @{ $config->transport_args };
is_deeply \%args, {
        'uri',
        'https://metabase.cpantesters.org/api/v1/',
        'id_file',
        $id_file,
}, 'transport_args content';

done_testing;
