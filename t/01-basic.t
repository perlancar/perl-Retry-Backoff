#!perl

use 5.010001;
use strict;
use warnings;
use Test::More 0.98;

use Retry::Backoff 'retry';

subtest basic => sub {
    my $n = 0;
    retry { $n++ < 1 and die } initial_delay=>0.1;
    is($n, 2);
};

#XXX
#subtest "param:strategy" => sub {
#};

subtest "param:retry_if" => sub {
    my $n = 0;
    retry { } initial_delay=>0.1, retry_if => sub { $n++ < 1 };
    is($n, 2);
};

subtest "param:on_success" => sub {
    my $n = 0;
    retry { $n++ < 1 and die } initial_delay=>0.1, on_success => sub { $n = 10 };
    is($n, 10);
};

subtest "param:on_failure" => sub {
    my $n = 0;
    my $m = 0;
    retry { $n++ < 1 and die } initial_delay=>0.1, on_failure => sub { $m++ };
    is($n, 2);
    is($m, 1);
};

#XXX
#subtest "param:non_blocking" => sub {
#};

done_testing;
