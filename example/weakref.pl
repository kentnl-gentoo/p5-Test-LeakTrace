#!perl -w

use strict;
use Test::LeakTrace::Script -verbose;

use Scalar::Util qw(weaken);

{
	my %a;
	my %b;

	$a{b} = \%b;
	$b{a} = \%a;

	weaken $a{b};
	weaken $b{a};
}

print "done.\n";
