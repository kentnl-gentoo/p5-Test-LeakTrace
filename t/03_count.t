#!perl -w

use strict;
use Test::More tests => 4;

use Test::LeakTrace;

is leaked_count {
	my %a;
	my %b;

	$a{b} = 1;
	$b{a} = 2;
}, 0, 'not leaked';

sub leaked{
	my %a;
	my %b;

	$a{b} = \%b;
	$b{a} = \%a;
}

cmp_ok leaked_count(\&leaked), '>', 0;

is leaked_count(\&leaked), scalar(leaked_info \&leaked);
is leaked_count(\&leaked), scalar(leaked_refs \&leaked);
