package Retry::Backoff;

# DATE
# VERSION

use 5.010001;
use strict 'subs', 'vars';
use warnings;
use Log::ger;

use Time::HiRes qw(time);

use Exporter 'import';
our @EXPORT_OK = qw(retry);

sub new {
    my $class = shift;
    my %args = @_;

    my $self = {};

    $self->{strategy} = delete $args{strategy};
    unless ($self->{strategy}) {
        $self->{strategy} = 'Exponential';
        $args{initial_delay} //= 1;
        $args{max_attempts}  //= 10;
        $args{max_delay}     //= 300;
    }
    $self->{on_failure}   = delete $args{on_failure};
    $self->{on_success}   = delete $args{on_success};
    $self->{retry_if}     = delete $args{retry_if};
    $self->{non_blocking} = delete $args{non_blocking};
    $self->{attempt_code} = delete $args{attempt_code};

    my $ba_mod = "Algorithm::Backoff::$self->{strategy}";
    (my $ba_mod_pm = "$ba_mod.pm") =~ s!::!/!g;
    require $ba_mod_pm;
    $self->{_backoff} = $ba_mod->new(%args);

    bless $self, $class;
}

sub run {
    my $self = shift;

    while(1) {
        if (my $timestamp = $self->{_needs_sleeping_until}) {
            # we can't retry until we have waited enough time
            my $now = time();
            $now >= $timestamp or return;
            $self->{_needs_sleeping_until} = 0;
        }

        # run the code, capture the error
        my $error;
        my @attempt_result;
        my $attempt_result;
        my $wantarray;
        if (wantarray) {
            $wantarray = 1;
            @attempt_result = eval { $self->{attempt_code}->(@_) };
            $error = $@;
        } elsif (!defined wantarray) {
            eval { $self->{attempt_code}->(@_) };
            $error = $@;
        } else {
            $attempt_result = eval { $self->{attempt_code}->(@_) };
            $error = $@;
        }

        my $h = {
            error => $error,
            action_retry => $self,
            attempt_result =>
                ( $wantarray ? \@attempt_result : $attempt_result ),
            attempt_parameters => \@_,
        };

        if ($self->{retry_if}) {
            $error = $self->{retry_if}->($h);
        }

        my $delay;
        my $now = time();
        if ($error) {
            $self->{on_failure}->($h) if $self->{on_failure};
            $delay = $self->{_backoff}->failure($now);
        } else {
            $self->{on_success}->($h) if $self->{on_success};
            $delay = $self->{_backoff}->success($now);
        }

        if ($delay == -1) {
        } elsif ($self->{non_blocking}) {
            $self->{_needs_sleeping_until} = $now + $delay;
        } else {
            sleep $delay;
        }

        unless ($error) {
            return $wantarray ? @attempt_result : $attempt_result;
        }
    }
}


sub retry (&;@) {
    my $code = shift;
    @_ % 2
        and die "Arguments to retry must be a CodeRef, and an even number of key / values";
    my %args = @_;
    __PACKAGE__->new(attempt_code => $code, %args)->run();
}

1;
#ABSTRACT: Retry a piece of code, with backoff strategies

=for Pod::Coverage ^(new|run)$

=head1 SYNOPSIS

 use Retry::Backoff 'retry';

 # by default, will use Algorithm::Backoff::Exponential with these parameters:
 # - initial_delay =   1 (1 second)
 # - max_delay     = 300 (5 minutes)
 # - max_attempts  =  10
 retry { ... };

 # pick backoff strategy (see corresponding Algorithm::Backoff::* for
 # list of parameters)
 retry { ... } strategy=>'Constant', delay=>1, max_attempts=>10;

 #


=head1 DESCRIPTION

This module provides L</retry> to retry a piece of code if it dies. Several
backoff (delay between retries) strategies are available from
C<Algorithm::Backoff>:: modules.


=head1 FUNCTIONS

=head2 retry

Usage:

 retry { attempt-code... } %args;

Retry the attempt-code if it dies. Known arguments:

=over

=item * strategy

String. Default is C<Exponential> (with C<initial_delay>=1, C<max_delay>=300,
and C<max_attempts>=10).

=item * on_success

Coderef. Will be called if attempt-code is deemed as successful.

=item * on_failure

Coderef. Will be called if attempt-code is deemed to have failed.

=item * retry_if

Coderef. If not specified, attempt-code is deemed to have failed if it dies. If
this is specified, then the coderef will be called and if it returns true then
the attempt-code is deemed to have failed.

Coderef will be passed:

 \%h

containing these keys:

 error
 action_retry
 attempt_result
 attempt_parameters

=item * non_blocking

Boolean.

=back

The rest of the arguments will be passed to the backoff strategy module
(C<Algorithm::Backoff::*>).


=head1 SEE ALSO

Code is based on L<Action::Retry>.

Other similar modules: L<Sub::Retry>, L<Retry>.

Backoff strategies from L<Algorithm::Backoff>::* modules.

=cut