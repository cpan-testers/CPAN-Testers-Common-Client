package CPAN::Testers::Common::Client::Config;
use strict;
use warnings;

use Carp               ();
use File::Glob         ();
use File::Spec    3.19 ();
use File::HomeDir 0.58 ();
use File::Path    qw( mkpath );
use IPC::Cmd;

sub new {
    my ($class, %args) = @_;
    my $prompt_ref = _set_prompt($args{myprompt});
    my $warn_ref   = _set_warn($args{mywarn});

    #--------------------------------------------------------------------------#
    # config_spec -- returns configuration options information
    #
    # Keys include
    #   default     --  recommended value, used in prompts and as a fallback
    #                   if an options is not set; mandatory if defined
    #   prompt      --  short prompt for EU::MM prompting
    #   info        --  long description shown before prompting
    #   validate    --  CODE ref; return normalized option or undef if invalid
    #--------------------------------------------------------------------------#

    my %option_specs = (
    email_from => {
        default => '',
        prompt => 'What email address will be used to reference your reports?',
        info => <<'HERE',
CPAN Testers requires a valid email address to identify senders
in the body of a test report. Please use a standard email format
like: "John Doe" <jdoe@example.com>
HERE
    },
    smtp_server => {
        default => undef, # (deprecated)
        prompt  => "[DEPRECATED] It's safe to remove this from your config file.",
    },
    edit_report => {
        default => 'default:ask/no pass/na:no',
        prompt => 'Do you want to review or edit the test report?',
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
Before test reports are sent, you may want to review or edit the test
report and add additional comments about the result or about your system
or Perl configuration.  By default, we will ask after each report is
generated whether or not you would like to edit the report. This option
takes "grade:action" pairs.
HERE
    },
    send_report => {
        default => 'default:ask/yes pass/na:yes',
        prompt => 'Do you want to send the report?',
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
By default, we will prompt you for confirmation that the test report
should be sent before actually doing it. This gives the opportunity to
skip sending particular reports if you need to (e.g. if you caused the
failure). This option takes "grade:action" pairs.
HERE
    },
    transport => {
        default  => 'Metabase uri https://metabase.cpantesters.org/api/v1/ id_file metabase_id.json',
        prompt   => 'Which transport system will be used to transmit the reports?',
        validate => \&_validate_transport,
        info     => <<'HERE',
CPAN Testers gets your reports over HTTPS using Metabase. This option lets
you set a different uri, transport mechanism and metabase profile path. If you
are receiving HTTPS errors, you may change the uri to use plain HTTP, though
this is not recommended. Unless you know what you're doing, just accept
the default value.
HERE
    },
    send_duplicates => {
        default => 'default:no',
        prompt => 'This report is identical to a previous one. Send it anyway?',
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
CPAN Testers records tests grades for each distribution, version and
platform. By default, duplicates of previous results will not be sent at
all, regardless of the value of the "send_report" option. This option takes
"grade:action" pairs.
HERE
    },
    send_PL_report => {
        prompt => 'Do you want to send the PL report?',
        default => undef,
        validate => \&_validate_grade_action_pair,
    },
    send_make_report => {
        prompt => 'Do you want to send the make/Build report?',
        default => undef,
        validate => \&_validate_grade_action_pair,
    },
    send_test_report => {
        prompt => 'Do you want to send the test report?',
        default => undef,
        validate => \&_validate_grade_action_pair,
    },
    send_skipfile => {
        prompt => "What file has patterns for things that shouldn't be reported?",
        default => undef,
        validate => \&_validate_skipfile,
    },
    cc_skipfile => {
        prompt => "What file has patterns for things that shouldn't CC to authors?",
        default => undef,
        validate => \&_validate_skipfile,
    },
    command_timeout => {
        prompt => 'If no timeout is set by CPAN, halt system commands after how many seconds?',
        default => undef,
        validate => \&_validate_seconds,
    },
    email_to => {
        default => undef,
    },
    editor => {
        default => undef,
    },
    debug => {
        default => undef,
    },
    retry_submission => {
        default => undef,
    },
    );

    return bless {
        _warn   => $warn_ref,
        _prompt => $prompt_ref,
        _specs  => \%option_specs,
    }, $class;
}

sub config_spec { return $_[0]->{_spec} }

sub myprompt { return $_[0]->{_prompt} }
sub mywarn   { return $_[0]->{_warn}   }

sub _set_prompt {
    my $prompt = shift;
    
    return $prompt
        if $prompt and ref $prompt and ref $prompt eq 'CODE';

    eval { require IO::Prompt::Tiny };
    Carp::croak 'please provide a prompt coderef or install IO::Prompt::Tiny'
        if $@;

    return \&IO::Prompt::Tiny::prompt;
}

sub _set_warn {
    my $warn = shift;

    return $warn
        if $warn and ref $warn and ref $warn eq 'CODE';
    
    return \&CORE::warn;
}


sub get_config_dir {
    if ( defined $ENV{PERL_CPAN_REPORTER_DIR} &&
         length  $ENV{PERL_CPAN_REPORTER_DIR}
    ) {
        return $ENV{PERL_CPAN_REPORTER_DIR};
    }

    my $conf_dir = File::Spec->catdir(File::HomeDir->my_home, ".cpanreporter");

    if ($^O eq 'MSWin32') {
      my $alt_dir = File::Spec->catdir(File::HomeDir->my_documents, ".cpanreporter");
      $conf_dir = $alt_dir if -d $alt_dir && ! -d $conf_dir;
    }

    return $conf_dir;
}

sub get_config_filename {
    if (  defined $ENV{PERL_CPAN_REPORTER_CONFIG} &&
          length  $ENV{PERL_CPAN_REPORTER_CONFIG}
    ) {
        return $ENV{PERL_CPAN_REPORTER_CONFIG};
    }
    else {
        return File::Spec->catdir( get_config_dir, 'config.ini' );
    }
}

#--------------------------------------------------------------------------#
# normalize_id_file
#--------------------------------------------------------------------------#

sub normalize_id_file {
    my ($self, $id_file) = @_;

    # Windows does not use ~ to signify a home directory
    if ( $^O eq 'MSWin32' && $id_file =~ m{^~/(.*)} ) {
        $id_file = File::Spec->catdir(File::HomeDir->my_home, $1);
    }
    elsif ( $id_file =~ /~/ ) {
        $id_file = File::Spec->canonpath(File::Glob::bsd_glob( $id_file ));
    }
    unless ( File::Spec->file_name_is_absolute( $id_file ) ) {
        $id_file = File::Spec->catfile(
            $self->get_config_dir, $id_file
        );
    }
    return $id_file;
}




sub generate_profile {
    my ($self, $id_file, $config) = @_;

    my $cmd = IPC::Cmd::can_run('metabase-profile');
    return unless $cmd;

    # XXX this is an evil assumption about email addresses, but
    # might do for simple cases that users might actually provide

    my @opts = ("--output" => $id_file);
    my $email = $config->{email_from};

    if ($email =~ /\A(.+)\s+<([^>]+)>\z/ ) {
        push @opts, "--email"   => $2;
        my $name = $1;
        $name =~ s/\A["'](.*)["']\z/$1/;
        push ( @opts, "--name"    => $1)
            if length $name;
    }
    else {
        push @opts, "--email"   => $email;
    }

    # XXX profile 'secret' is really just a generated API key, so we
    # can create something fairly random for the user and use that
    push @opts, "--secret"      => sprintf("%08x", rand(2**31));

    return scalar IPC::Cmd::run(
        command => [ $cmd, @opts ],
        verbose => 1,
    );
}

sub grade_action_prompt {
    return << 'HERE';

Some of the following configuration options require one or more "grade:action"
pairs that determine what grade-specific action to take for that option.
These pairs should be space-separated and are processed left-to-right. See
CPAN::Testers::Common::Client::Config documentation for more details.

    GRADE   :   ACTION  ======> EXAMPLES
    -------     -------         --------
    pass        yes             default:no
    fail        no              default:yes pass:no
    unknown     ask/no          default:ask/no pass:yes fail:no
    na          ask/yes
    default

HERE
}

my @valid_actions = qw{ yes no ask/yes ask/no ask };
sub is_valid_action {
    my ($self, $action) = @_;
    return grep { $action eq $_ } @valid_actions;
}


my @valid_grades = qw{ pass fail unknown na default };
sub is_valid_grade {
    my ($self, $grade) = @_;
    return grep { $grade eq $_ } @valid_grades;
}

#--------------------------------------------------------------------------#
# _validate
#
# anything is OK if there is no validation subroutine
#--------------------------------------------------------------------------#

sub _validate {
    my ($self, $name, $value) = @_;
    my $specs = $self->config_spec;
    return 1 if ! exists $specs->{$name}{validate};
    return $specs->{$name}{validate}->($self, $name, $value);
}

#--------------------------------------------------------------------------#
# _validate_grade_action
# returns hash of grade => action
# returns undef
#--------------------------------------------------------------------------#

sub _validate_grade_action_pair {
    my ($self, $name, $option) = @_;
    $option ||= "no";

    my %ga_map; # grade => action

    PAIR: for my $grade_action ( split q{ }, $option ) {
        my ($grade_list,$action);

        if ( $grade_action =~ m{.:.} ) {
            # parse pair for later check
            ($grade_list, $action) = $grade_action =~ m{\A([^:]+):(.+)\z};
        }
        elsif ( _is_valid_action($grade_action) ) {
            # action by itself
            $ga_map{default} = $grade_action;
            next PAIR;
        }
        elsif ( _is_valid_grade($grade_action) ) {
            # grade by itself
            $ga_map{$grade_action} = "yes";
            next PAIR;
        }
        elsif( $grade_action =~ m{./.} ) {
            # gradelist by itself, so setup for later check
            $grade_list = $grade_action;
            $action = "yes";
        }
        else {
            # something weird, so warn and skip
            $self->mywarn(
                "\nignoring invalid grade:action '$grade_action' for '$name'.\n\n"
            );
            next PAIR;
        }

        # check gradelist
        my %grades = map { ($_,1) } split( "/", $grade_list);
        for my $g ( keys %grades ) {
            if ( ! _is_valid_grade($g) ) {
                $self->mywarn(
                    "\nignoring invalid grade '$g' in '$grade_action' for '$name'.\n\n"
                );
                delete $grades{$g};
            }
        }

        # check action
        if ( ! _is_valid_action($action) ) {
            $self->mywarn(
                "\nignoring invalid action '$action' in '$grade_action' for '$name'.\n\n"
            );
            next PAIR;
        }

        # otherwise, it all must be OK
        $ga_map{$_} = $action for keys %grades;
    }

    return scalar(keys %ga_map) ? \%ga_map : undef;
}

sub _validate_transport {
    my ($self, $name, $option, $config) = @_;
    my $transport = '';

    if ( $option =~ /^(\w+(?:::\w+)*)\s?/ ) {
        $transport = $1;
        my $full_class = "Test::Reporter::Transport::$transport";
        eval "use $full_class ()";
        if ($@) {
            $self->mywarn(
                "\nerror loading $full_class. Please install the missing module or choose a different transport mechanism.\n\n"
            );
        }
    }
    else {
        $self->mywarn(
            "\nPlease provide a transport mechanism.\n\n"
        );
        return;
    }

    # we do extra validation for Metabase and offer to create the profile
    if ( $transport eq 'Metabase' ) {
        unless ( $option =~ /\buri\s+\S+/ ) {
            $self->mywarn(
                "\nPlease provide a target uri.\n\n"
            );
            return;
        }

        unless ( $option =~ /\bid_file\s+(\S.+?)\s*$/ ) {
            $self->mywarn(
                "\nPlease specify an id_file path.\n\n"
            );
            return;
        }

        my $id_file = _normalize_id_file($1);

        # Offer to create if it doesn't exist
        if ( ! -e $id_file )  {
            my $answer = $self->myprompt(
                "\nWould you like to run 'metabase-profile' now to create '$id_file'?", "y"
            );
            if ( $answer =~ /^y/i ) {
                return _generate_profile( $id_file, $config );
            }
            else {
                $self->mywarn( <<"END_ID_FILE" );
You can create a Metabase profile by typing 'metabase-profile' in your
command prompt and moving the resulting file to the location you specified.
If you did not specify an absolute path, put it in your .cpanreporter
directory.  You will need to do this before continuing.
END_ID_FILE
                return;
            }
        }
        # Warn and fail validation if there but not readable
        elsif (
            not (     -r $id_file
                  or  -r File::Spec->catdir( get_config_dir(), $id_file)
                )
        ) {
            $self->mywarn(
                "'$id_file' was not readable.\n\n"
            );
            return;
        }
    } # end Metabase

    return 1;
}

sub _validate_seconds {
    my ($name, $option) = @_;
    return unless defined($option) && length($option)
        && ($option =~ /^\d/) && $option >= 0;
    return $option;
}

sub _validate_skipfile {
    my ($name, $option) = @_;
    return unless $option;
    my $skipfile = File::Spec->file_name_is_absolute( $option )
                 ? $option : File::Spec->catfile( _get_config_dir(), $option );
    return -r $skipfile ? $skipfile : undef;
}


1;
__END__

=head1 NAME

CPAN::Testers::Common::Client::Config - auxiliary functions for setting up
CPAN Testers clients

=head1 WARNING!!!

This is a *very* early module and an EXPERIMENTAL one for that matter.
The API B<WILL CHANGE>. We're still moving stuff around, so please only
use it if you understand and accept the consequences.

If you have any questions, please contact the author.

=head1 FUNCTIONS

=head2 get_config_dir()

The base directory in which your 'C<config.ini>' and other files reside.
Defaults to the '.cpantesters' directory  under your home directory
(if you're using Linux or OS X) or under the 'my documents' folder
(if you're running Windows).

=head2 get_config_filename()

Returns the full path for the 'C<config.ini>' file.

=head2 config_spec()

Return the full config specification structure, containing available keys and
their associated data, including validators and (suggested) default values.

=head2 generate_profile( $id_file, $config )

This function runs 'C<metabase-profile>' automatically for you. It receives as
arguments C<$id_file>, which is the name of the target metabase id file; and
C<$config>, which is a hashref of the user's 'C<config.ini>' file.

=head2 grade_action_prompt()

Describes grade:action pairs

=head2 is_valid_action( $action_str )

Returns true when an action string is valid for grade:action pairs.

=head2 is_valid_grade( $grade_str )

Returns true when a grade string is valid for grade_action pairs.

=head2 CONFIGURATION AND ENVIRONMENT

=over 4

=item * PERL_CPAN_REPORTER_DIR

Overrides the value for C<get_config_dir()>.

=item * PERL_CPAN_REPORTER_CONFIG

Overrides the value for C<get_config_filename()>.

=back

