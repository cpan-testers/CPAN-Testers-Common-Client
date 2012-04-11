use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'CPAN::Testers::Common::Client',
    AUTHOR              => 'Breno G. de Oliveira <garu@cpan.org>',
    VERSION_FROM        => 'lib/CPAN/Testers/Common/Client.pm',
    ABSTRACT_FROM       => 'lib/CPAN/Testers/Common/Client.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Devel::Platform::Info' => 0,
        'Probe::Perl'           => 0,
        'Carp'                  => 0,
        'Capture::Tiny'         => 0,
        'File::Spec'            => 0,
        'Config::Perl::V'       => 0,
        'Metabase::Resource'    => 0,
        'ExtUtils::MakeMaker'   => 6.36,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'CPAN-Testers-Common-Client-*' },
);
