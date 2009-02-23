#!perl -w
use strict;
use Time::HiRes qw(time);
our $t;
BEGIN{	$t = time(); }
END{	printf "spent %.02f sec.\n", time() - $t; }

use Devel::LeakTrace;

use ExtUtils::MakeMaker (); # a large module

{
	my %hash;
	for(1 .. 1000){
		$hash{$_}++;
	}

	my %a;
	my %b;

	$a{b} = \%a;
	$b{a} = \%b;
}

