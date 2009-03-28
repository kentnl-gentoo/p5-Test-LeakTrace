package Test::LeakTrace::Heavy;

use strict;
use warnings;
use Test::LeakTrace ();

use Test::Builder;

my $Test = Test::Builder->new();

sub _leaks_cmp_ok{
	my($block, $cmp_op, $expected, $description) = @_;

	# calls to prepare cache in $block
	$block->();


	my $got    = &Test::LeakTrace::leaked_count($block);

	my $desc = sprintf 'leaks %s %-2s %s', $got, $cmp_op, $expected;
	if(defined $description){
		$description .= " ($desc)";
	}
	else{
		$description = $desc;
	}

	my $result = $Test->cmp_ok($got, $cmp_op, $expected, $description);

	if(!$result){
		open local(*STDERR), '>', \(my $content = '');
		$block->(); # re-call it because open *STDERR changes the run-time environment

		&Test::LeakTrace::leaktrace($block, -verbose);
		$Test->diag($content);
	}

	return $result;
}

1;

__END__

=head1 NAME

Test::LeakTrace::Heavy - Test::LeakTrace guts

=head1 SYNOPSIS

	use Test::LeakTrace qw(:test);

=head1 DESCRIPTION

This module implements test commands for C<Test::LeakTrace>.

See L<Test::LeakTrace>.

=cut

