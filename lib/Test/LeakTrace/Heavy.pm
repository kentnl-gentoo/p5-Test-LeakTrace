package Test::LeakTrace::Heavy;

use strict;
use warnings;
use Test::LeakTrace qw(leaktrace leaked_count leaked_info);

use Test::Builder;

my $Test = Test::Builder->new();

sub _not_leaked(&;$){
	my($block, $description) = @_;

	$block->(); # allow $block to prepare cache

	my $count = &leaked_count($block);

	$Test->ok($count == 0, $description);

	if($count){
		&leaktrace($block, -verbose);
	}

	return $count == 0;
}

sub _leaked_cmp_ok(&$$;$){
	my($block, $cmp_op, $expected, $description) = @_;

	$block->(); # allow $block to prepare cache

	$description ||= sprintf 'leaked count %-3s %s', $cmp_op, $expected;

	my $got = &leaked_count($block);
	my $result =  $Test->cmp_ok($got, $cmp_op, $expected, $description);

	if(!$result){
		&leaktrace($block, -verbose);
	}

	return $result;
}

1;

__END__

=head1 NAME

Test::LeakTrace::Heavy - Test::LeakTrace guts

=head1 DESCRIPTION

This module implements test commands for C<Test::LeakTrace>.

=cut

