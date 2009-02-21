package Test::LeakTrace::Heavy;

use strict;
use warnings;
use Test::LeakTrace ();

use Test::Builder;

package Test::LeakTrace;

my $Test = Test::Builder->new();

sub not_leaked(&;$){
	my($block, $description) = @_;

	my @info = &leaked_info($block);

	$Test->ok(@info == 0, $description);

	if(@info){
		require Data::Dumper;

		foreach my $si(@info){
			my($ref, $file, $line) = @{$si};
			$Test->diag("leaked at $file line $line");

			my $ddx = Data::Dumper->new([$ref]);
			$ddx->Indent(1);
			$Test->diag($ddx->Dump());
		}
	}

	return @info == 0;
}


sub leaked_cmp_ok(&$$;$){
	my($block, $cmp_op, $expected, $description) = @_;

	$description ||= sprintf 'leaked count %-3s %s', $cmp_op, $expected;

	my $got = &leaked_count($block);
	return $Test->cmp_ok($got, $cmp_op, $expected, $description);
};

1;

__END__

=head1 NAME

Test::LeakTrace::Heavy - Test::LeakTrace guts

=cut

