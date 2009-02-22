#!perl -w

use strict;
use Test::More tests => 2;

use Test::LeakTrace qw(leaked_info);
use autouse 'Data::Dumper' => 'Dumper';

my @info = leaked_info{
	my %a = (foo => 42);
	my %b = (bar => 3.14);

	$b{a} = \%a;
	$a{b} = \%b;
};

cmp_ok(scalar(@info), '>', 1)
	or diag(Dumper(\@info));

my($si) = grep {
		my $ref = $_->[0];
		ref($ref) eq 'REF' and ref(${$ref}) eq 'HASH' and exists ${$ref}->{a}
	} @info;
is_deeply $si->[1], __FILE__, 'state info'
	or diag(Dumper \@info);

