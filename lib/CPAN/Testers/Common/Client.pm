# TODO: several resources per client?
package CPAN::Testers::Common::Client;
use warnings;
use strict;

use Devel::Platform::Info;
use Probe::Perl;
use Config::Perl::V;
use Module::InstalledVersion;
use Carp ();

our $VERSION = '0.01';

sub new {
    my ($class, %params) = @_;
    my $self  = bless {}, $class;

    Carp::croak 'Please specify a resource' unless %params and $params{resource};
    $self->resource( $params{resource} );

    Carp::croak 'Please specify a grade for the resource' unless $params{grade};
    $self->grade( $params{grade} );

    if ( $params{author} ) {
        $self->author( $params{author} );
    }
    else {
        # no author provided, let's try to use
        # the PAUSE id of the resource
        if ( $params{resource} =~ m{/(\w+)/[^/]$/} ) {
            $self->author( $1 );
        }
    }

    $self->via( exists $params{via}
                ? $params{via}
                : "Your friendly CPAN Testers client version $VERSION"
              );

    $self->comments( exists $params{comments}
                     ? $params{comments}
                     : $ENV{AUTOMATED_TESTING}
                     ? "this report is from an automated smoke testing program\nand was not reviewed by a human for accuracy"
                     : 'none provided'
                   );

    if ( $params{prereqs} ) {
        $self->{_meta}{prereqs} = $params{prereqs}
    }
    elsif ( $params{build_dir} ) {
        $self->_get_prereqs( $params{build_dir} );
    }

    return $self;
}

sub _get_prereqs {
    my ($self, $dir) = @_;
    my $meta;

    foreach my $meta_file ( qw( META.json META.yml META.yaml ) ) {
        my $meta_path = File::Spec->catfile( $dir, $meta_file );
        if (-e $meta_path) {
            $meta = eval { Parse::CPAN::Meta->load_file( $dir ) };
            last if $meta;
        }
    }

    if ($meta and $meta->{meta-spec}{version} < 2) {
        $self->{_meta}{prereqs} = $meta->{prereqs};
    }
    return;
}

sub comments {
    my ($self, $comments) = @_;
    $self->{_comment} = $comment if $comment;
    return $self->{_comment};
}

sub via {
    my ($self, $via) = @_;
    $self->{_via} = $via if $via;
    return $self->{_via};
}


sub author {
    my ($self, $author) = @_;
    $self->{_author} = $author if $author;
    return $self->{_author};
}

sub distname {
    my ($self, $distname) = @_;
    $self->{_distname} = $distname if $distname;

    # no distname provided, let's try
    # to figure out from the resource
    if ( !$self->{_distname} ) {
        my $dist = $self->resource;
        $self->{_distname} = File::Basename::basename(
            $dist,
            qr/\.(?:tar\.(bz2|gz|Z)|t(?:gz|bz)|zip)/
        );
    }

    return $self->{_distname};
}

#TODO: required
sub grade {
    my ($self, $grade) = @_;
    $self->{_grade} = $grade if $grade;
    return $self->{_grade};
}

#TODO: required
sub resource {
    my ($self, $resource) = @_;

    if ($resource) {
        $self->{_resource} = $resource;

        #FIXME: decouple?
        $self->report(
            CPAN::Testers::Report->open(
                resource => $resource,
            )
        );
    }

    return $self->{_resource};
}

sub report {
    my ($self, $report) = @_;
    if ($report) {
        Carp::croak 'report must be a CPAN::Testers::Report object'
            unless ref $report and ref $report eq 'CPAN::Testers::Report';

        $self->{_report} = $report;
    }
    return $self->{_report};
}

sub populate {
    my $self = shift;
    my $report = $self->report;
    Carp::croak 'please specify a resource before populating'
        unless $report;

    # some data is repeated between facts, so we keep a 'cache'
    $self->{_config}   = Config::Perl::V::myconfig();
    $self->{_platform} = Devel::Platform::Info->new->get_info();

    my @facts = qw(
        TestSummary TestOutput TesterComment
        Prereqs InstalledModules
        PlatformInfo PerlConfig TestEnvironment
    );

    foreach my $fact ( @facts ) {
        my $populator = '_populate_' . lc $fact;
        $self->{_data}{$fact} = $self->$populator->();
    }

    # this has to be last, as it also composes the email
    $self->{_data}{LegacyReport} = $self->_populate_legacyreport;
}


#===========================================#
# below are the functions that populate     #
# the object with data, and their auxiliary #
# functions.                                #
#===========================================#

sub _populate_platforminfo {
    my $self = shift;
    return $self->{_platform};
}


sub _populate_perlconfig {
    my $self = shift;
    return @{ $self->{_config} }{build,config};
}

sub _populate_testenvironment {

    return {
        environment_vars => _get_env_vars(),
        special_vars     => _get_special_vars(),
    };
}

sub _get_env_vars {
    # Entries bracketed with "/" are taken to be a regex; otherwise literal
    my @env_vars= qw(
        /PERL/
        /LC_/
        /AUTHOR_TEST/
        LANG
        LANGUAGE
        PATH
        SHELL
        COMSPEC
        TERM
        TEMP
        TMPDIR
        AUTOMATED_TESTING
        INCLUDE
        LIB
        LD_LIBRARY_PATH
        PROCESSOR_IDENTIFIER
        NUMBER_OF_PROCESSORS
    );

    my %env_found = ();
    foreach my $var ( @env_vars ) {
        if ( $var =~ m{^/(.+)/$} ) {
            my $re = $1;
            foreach my $found ( grep { /$re/ } keys %ENV ) {
                $env_found{$found} = $ENV{$found} if exists $ENV{$found};
            }
        }
        else {
            $env_found{$var} = $ENV{$var} if exists $ENV{$var};
        }
    }

    return \%env_found;
}

sub _get_special_vars {
    my %special_vars = (
        EXECUTABLE_NAME => $^X,
        UID             => $<,
        EUID            => $>,
        GID             => $(,
        EGID            => $),
    );

    if ( $^O eq 'MSWin32' && eval 'require Win32' ) { ## no critic
        $special_vars{'Win32::GetOSName'}    = Win32::GetOSName();
        $special_vars{'Win32::GetOSVersion'} = join( ', ', Win32::GetOSVersion() );
        $special_vars{'Win32::FsType'}       = Win32::FsType();
        $special_vars{'Win32::IsAdminUser'}  = Win32::IsAdminUser();
    }
    return \%special_vars;
}

sub _populate_prereqs {
    my $self = shift;
    
    return {
        configure_requires => $self->{_meta}{configure_requires},
        build_requires     => $self->{_meta}{build_requires},
        requires           => $self->{_meta}{requires},
    };
}

sub _populate_testercomment {
    my $self = shift;
    return $self->comments;
}

# TODO: this is different than what's currently being done
# in CPAN::Reporter::_version_finder().
####
sub _populate_installedmodules {
    my $self = shift;

    my @toolchain_mods= qw(
        CPAN
        CPAN::Meta
        Cwd
        ExtUtils::CBuilder
        ExtUtils::Command
        ExtUtils::Install
        ExtUtils::MakeMaker
        ExtUtils::Manifest
        ExtUtils::ParseXS
        File::Spec
        JSON
        JSON::PP
        Module::Build
        Module::Signature
        Parse::CPAN::Meta
        Test::Harness
        Test::More
        YAML
        YAML::Syck
        version
    );

    my $installed = {};
    foreach my $mod (@toolchain_mods) {
        my $m = Module::InstalledVersion->new( $mod );
        $installed->{$_} = $m->{version} if $m->{version};
    }

    return $installed; 
}

sub _populate_legacyreport {
    my $self = shift;
    Carp::croak 'grade missing for LegacyReport'
        unless $self->grade;

    return {
        %{ $self->TestSummary },
        textreport => $self->textreport
    }
}

sub _populate_testsummary {
    my $self = shift;

    return {
        grade        => $self->grade,
        osname       => $self->{_platform}{osname},
        osversion    => $self->{_platform}{osvers},
        archname     => $self->{_platform}{archname},
        perl_version => $self->{_config}{version},
    }
}

sub _populate_testoutput {
    my $self = shift;
    return {
        configure => $self->{_build}{configure},
        build     => $self->{_build}{build},
        test      => $self->{_build}{test},
    };
}


#--------------------------------------------------------------------------#
# _version_finder
#
# module => version pairs
#
# This is done via an external program to show installed versions exactly
# the way they would be found when test programs are run.  This means that
# any updates to PERL5LIB will be reflected in the results.
#
# File-finding logic taken from CPAN::Module::inst_file().  Logic to
# handle newer Module::Build prereq syntax is taken from
# CPAN::Distribution::unsat_prereq()
#
#--------------------------------------------------------------------------#
 
my $version_finder = $INC{'CPAN/Testers/Common/Client/PrereqCheck.pm'};
 
sub _version_finder {
    my %prereqs = @_;
 
    my $perl = Probe::Perl->find_perl_interpreter();
    my @prereq_results;
 
    my $prereq_input = _temp_filename( 'CPAN-Reporter-PI-' );
    my $fh = IO::File->new( $prereq_input, "w" )
        or die "Could not create temporary '$prereq_input' for prereq analysis: $!";
    $fh->print( map { "$_ $prereqs{$_}\n" } keys %prereqs );
    $fh->close;
 
    my $prereq_result = capture { system( $perl, $version_finder, '<', $prereq_input ) };
 
    unlink $prereq_input;
 
    my %result;
    for my $line ( split "\n", $prereq_result ) {
        next unless length $line;
        my ($mod, $met, $have) = split " ", $line;
        unless ( defined($mod) && defined($met) && defined($have) ) {
            $CPAN::Frontend->mywarn(
                "Error parsing output from CPAN::Reporter::PrereqCheck:\n" .
                $line
            );
            next;
        }
        $result{$mod}{have} = $have;
        $result{$mod}{met} = $met;
    }
    return \%result;
}
 



42;
__END__

=head1 NAME

CPAN::Testers::Common::Client - Common class for CPAN::Testers clients


=head1 SYNOPSIS

    use CPAN::Testers::Common::Client;

    my $client = CPAN::Testers::Common::Client->new(
          resource => 'cpan:///distfile/RJBS/Data-UUID-1.217.tar.gz',
          grade    => 'pass',
    );

    # what you should send to CPAN Testers, via Metabase
    my $metabase_data = $client->populate;
    my $email_body    = $client->email;

Although the recommended is to construct your object passing as much information as possible:

    my $client = CPAN::Testers::Common::Client->new(
          resource         => 'cpan:///distfile/RJBS/Data-UUID-1.217.tar.gz',
          grade            => 'pass',
          comments         => 'this is an auto-generated report. Cheers!',
          configure_output => '...',
          build_output     => '...',
          test_output      => '...',

          # same as in a META.yml 2.0 structure
          prereqs => {
              runtime => {
                requires => {
                  'File::Basename' => '0',
                },
                recommends => {
                  'ExtUtils::ParseXS' => '2.02',
                },
              },
              build => {
                requires => {
                  'Test::More' => '0',
                },
              },
              # etc.
          },
          # alternatively, if the dist is expanded in a local dir and has a Meta 2.0 {json,yml} file
          # you can just point us to the build_dir and we'll extract the prereqs ourselves:
          # build_dir => '/tmp/Data-UUID-1.217/'
    );

=head1 DESCRIPTION


=head1 DIAGNOSTICS

=over 4

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=back


=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/garu/CPAN-Testers-Common-Client>

  git clone https://github.com/garu/CPAN-Testers-Common-Client.git


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
C<bug-cpan-testers-common-client@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Breno G. de Oliveira  C<< <garu@cpan.org> >>


=head1 ACKNOWLEDGMENTS

This module was created at the L<http://2012.qa-hackathon.org|2012 Perl QA Hackathon>, so a big
THANK YOU is in order to all the companies and organisations that supported it, namely the
L<http://www.cite-sciences.fr/|Cité des Sciences>, L<http://www.diabolocom.com/|Diabolocom>,
L<http://www.dijkmat.nl/|Dijkmat>, L<http://www.duckduckgo.com/|DuckDuckGo>,
L<http://www.dyn.com/|Dyn>, L<http://freeside.biz/|Freeside>, L<http://www.hederatech.com/|Hedera>,
L<http://www.jaguar-network.com/|Jaguar>, L<http://www.shadow.cat/|ShadowCat>,
L<http://www.splio.com/|Splio>, L<http://www.teclib.com/|TECLIB'>, L<http://weborama.com/|Weborama>,
L<http://www.enlightenedperl.org/|EPO>, L<http://www.perl-magazin.de/|$foo Magazin> and
L<http://www.mongueurs.net/|Mongueurs de Perl>.

Also, this module could never be done without the help of L<https://metacpan.org/author/DAGOLDEN|David Golden>,
L<https://metacpan.org/author/BARBIE|Barbie> and L<https://metacpan.org/author/MIYAGAWA|Tatsuhiko Miyagawa>.

All bugs and mistakes are my own.


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2012, Breno G. de Oliveira C<< <garu@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
