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

    $self->resource( $params{resource} ) if $params{resource};
    $self->grade( $params{grade} )       if $params{grade};
    $self->comments( $params{comments} ) if $params{comments};

    if ( $params{prereqs} ) {
        $self->{_meta}{prereqs} = $params{prereqs}
    }
    elsif ( $params{build_dir} ) {
        $self->_get_prereqs( $params{build_dir} );
    }

    $self->{_config}   = Config::Perl::V::myconfig();
    $self->{_platform} = Devel::Platform::Info->new->get_info();

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

    my @facts = qw(
        LegacyReport TestSummary TestOutput TesterComment
        Prereqs InstalledModules
        PlatformInfo PerlConfig TestEnvironment
    );

    foreach my $fact ( @facts ) {
        my $populator = '_populate_' . lc $fact;
        $self->{_data}{$fact} = $self->$populator->();
    }
}


#=======================================

sub _populate_platforminfo {
    my $self = shift;
    return $self->{_platform};
}


sub _populate_perlconfig {
    my $self = shift;
    return @{ $self->{_config} }{build,config};
}

# TODO:
# AUTOMATED_TESTING = 1
#    LANG = en_US.UTF-8
#    LANGUAGE = en_US:en
#    PATH = /usr/lib/ccache:/home/sand/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:/usr/local/perl/bin:/usr/X11/bin:/sbin:/usr/sbin
#    PERL5LIB = 
#    PERL5OPT = 
#    PERL5_CPANPLUS_IS_RUNNING = 31223
#    PERL5_CPAN_IS_RUNNING = 31223
#    PERL_AUTOINSTALL = --defaultdeps
#    PERL_EXTUTILS_AUTOINSTALL = --defaultdeps
#    PERL_MM_USE_DEFAULT = 1
#    SHELL = /bin/bash
#    TERM = screen
#
#Perl special variables (and OS-specific diagnostics, for MSWin32):
#
#    $^X = /home/sand/src/perl/repoperls/installed-perls/perl/perl-5.10.1/2b65c/bin/perl
#    $UID/$EUID = 1001 / 1001
#    $GID = 1001 1001
#    $EGID = 1001 1001

sub _populate_testenvironment {
    return {
        environment_vars => {
          PERL5LIB  => $ENV{PERL5LIB},
          TEMP      => $ENV{TEMP},
        },
        special_vars => {
          'EXECUTABLE_NAME' => $^X,
          'UID'             => $<,
        },
    };
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

CPAN::Testers::Common::Client - Standard client for CPAN::Testers


=head1 SYNOPSIS

    use CPAN::Testers::Common::Client;

  
=head1 DESCRIPTION


=head1 DIAGNOSTICS

=over 4

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=back


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
C<bug-cpan-testers-common-client@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Breno G. de Oliveira  C<< <garu@cpan.org> >>


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
