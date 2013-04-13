package CPAN::Testers::Common::Client::PrereqCheck;
use strict;

use ExtUtils::MakeMaker 6.36;
use File::Spec;
 
_run() if ! caller();
 
sub _run {
    my %saw_mod;
    # read module and prereq string from STDIN
    local *DEVNULL;
    open DEVNULL, '>' . File::Spec->devnull; ## no critic
    # ensure actually installed, not ./inc/... or ./t/..., etc.
    local @INC = grep { $_ ne '.' } @INC;
    while ( <> ) {
        m/^(\S+)\s+([^\n]*)/;
        my ($mod, $need) = ($1, $2);
        die "Couldn't read module for '$_'" unless $mod;
        $need = 0 if not defined $need;

        # only evaluate a module once
        next if $saw_mod{$mod}++;
 
        # get installed version from file with EU::MM
        my($have, $inst_file, $dir, @packpath);
        if ( $mod eq "perl" ) {
            $have = $];
        }
        else {
            @packpath = split( /::/, $mod );
            $packpath[-1] .= '.pm';
            if (@packpath == 1 && $packpath[0] eq 'readline.pm') {
                unshift @packpath, 'Term', 'ReadLine'; # historical reasons
            }
            INCDIR:
            foreach my $dir (@INC) {
                my $pmfile = File::Spec->catfile($dir,@packpath);
                if (-f $pmfile){
                    $inst_file = $pmfile;
                    last INCDIR;
                }
            }
 
            # get version from file or else report missing
            if ( defined $inst_file ) {
                $have = MM->parse_version($inst_file);
                $have = '0' if ! defined $have || $have eq 'undef';
                # report broken if it can't be loaded
                # "select" to try to suppress spurious newlines
                select DEVNULL; ## no critic
                if ( ! _try_load( $mod, $have ) ) {
                    select STDOUT; ## no critic
                    print "$mod 0 broken\n";
                    next;
                }
                select STDOUT; ## no critic
            }
            else {
                print "$mod 0 n/a\n";
                next;
            }
        }
 
        # complex requirements are comma separated
        my ( @requirements ) = split /\s*,\s*/, $need;
 
        my $passes = 0;
        RQ:
        for my $rq (@requirements) {
            if ($rq =~ s|>=\s*||) {
                # no-op -- just trimmed string
            } elsif ($rq =~ s|>\s*||) {
                if (_vgt($have,$rq)){
                    $passes++;
                }
                next RQ;
            } elsif ($rq =~ s|!=\s*||) {
                if (_vcmp($have,$rq)) {
                    $passes++; # didn't match
                }
                next RQ;
            } elsif ($rq =~ s|<=\s*||) {
                if (! _vgt($have,$rq)){
                    $passes++;
                }
                next RQ;
            } elsif ($rq =~ s|<\s*||) {
                if (_vlt($have,$rq)){
                    $passes++;
                }
                next RQ;
            }
            # if made it here, then it's a normal >= comparison
            if (! _vlt($have, $rq)){
                $passes++;
            }
        }
        my $ok = $passes == @requirements ? 1 : 0;
        print "$mod $ok $have\n"
    }
    return;
}


sub _try_load {
  my ($module, $have) = @_;
 
  # M::I < 0.95 dies in require, so we can't check if it loads
  # Instead we just pretend that it works
  if ( $module eq 'Module::Install' && $have < 0.95 ) {
    return 1;
  }
  # loading Acme::Bleach bleaches *us*, so skip
  elsif ( $module eq 'Acme::Bleach' ) {
    return 1;
  }

  my $file = "$module.pm";
  $file =~ s{::}{/}g;
 
  return eval {require $file; 1}; ## no critic
}
 
#----------------------------------------------------#
# vcmp and friends  -- adapted from CPAN::Version.
#
# takes two versions and compares their number.
# Thanks, Andreas Koenig & Jost Krieger!
#----------------------------------------------------#
sub _vcmp {
    my ($l,$r) = @_;
    local($^W) = 0;

    return 0 if $l eq $r; # short circuit for quicker success
 
    foreach ($l,$r) {
        s/_//g;
    }
    foreach ($l,$r) {
        next unless tr/.// > 1 || /^v/;
        s/^v?/v/;
        1 while s/\.0+(\d)/.$1/; # remove leading zeroes per group
    }
    if ($l=~/^v/ <=> $r=~/^v/) {
        foreach ($l,$r) {
            next if /^v/;
            $_ = _float2vv($_);
        }
    }
    my $lvstring = "v0";
    my $rvstring = "v0";
    if ($] >= 5.006
     && $l =~ /^v/
     && $r =~ /^v/) {
        $lvstring = _vstring($l);
        $rvstring = _vstring($r);
    }

    return (
            ($l ne "undef") <=> ($r ne "undef")
            ||
            $lvstring cmp $rvstring
            ||
            $l <=> $r
            ||
            $l cmp $r
    );
}

sub _vgt {
    my ($l,$r) = @_;
    _vcmp($l,$r) > 0;
}

sub _vlt {
    my ($l,$r) = @_;
    _vcmp($l,$r) < 0;
}

sub _vstring {
    my($n) = @_;
    $n =~ s/^v// or die "_vstring() called with invalid arg [$n]";
    pack "U*", split /\./, $n;
}

# vv => visible vstring
sub _float2vv {
    my ($n) = @_;
    my ($rev) = int($n);
    $rev ||= 0;
    my ($mantissa) = $n =~ /\.(\d{1,12})/; # limit to 12 digits to limit
                                           # architecture influence
    $mantissa ||= 0;
    $mantissa .= "0" while length($mantissa) % 3;
    my $ret = "v" . $rev;
    while ($mantissa) {
        $mantissa =~ s/(\d{1,3})// or
            die "Panic: length>0 but not a digit? mantissa[$mantissa]";
        $ret .= "." . int $1;
    }
    $ret =~ s/(\.0)+/.0/; # v1.0.0 => v1.0

    return $ret;
}
 
1;
__END__
=head1 NAME
 
CPAN::Testers::Common::Client::PrereqCheck - Modulino for prerequisite tests

=head1 SYNOPSIS
 
  require CPAN::Testers::Common::Client::PrereqCheck;
  my $prereq_check = $INC{'CPAN/Testers/Common/Client/PrereqCheck.pm'};
  my $result = qx/$perl $prereq_check < $prereq_file/;
 
=head1 DESCRIPTION
 
This modulino determines whether a list of prerequisite modules are
available and, if so, their version number.  It is designed to be run
as a script in order to provide this information from the perspective of
a subprocess.
 
It reads a module name and prerequisite string pair from each line of input
and prints out the module name, 0 or 1 depending on whether the prerequisite
is satisfied, and the installed module version.  If the module is not
available, it will print "nE<sol>a" for the version.  If the module is available
but can't be loaded, it will print "broken" for the version.  Modules
without a version will be treated as being of version "0".
 
No user serviceable parts are inside.  This modulino is packaged for
internal use by CPAN::Testers::Common::Client.

=head1 SEE ALSO
 
=over
 
=item *
 
L<CPAN::Testers::Common::Client> -- main documentation
 
=back
 

