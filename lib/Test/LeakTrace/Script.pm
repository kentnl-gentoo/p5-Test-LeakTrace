package Test::LeakTrace::Script;

use strict;

use Test::LeakTrace ();

my $Mode = $ENV{PERL_LEAKTRACE_VERBOSE};
$Mode = $ENV{LEAKTRACE_VERBOSE} unless defined $Mode;

sub import{
	shift;

	$Mode = shift if @_;
}

INIT{
	Test::LeakTrace::_start(1);
}

END{
	Test::LeakTrace::_finish($Mode);
	return;
}

1;
__END__

=head1 NAME

Test::LeakTrace::Script - A LeakTrace interface for whole scripts

=head1 SYNOPSIS

	$ perl -MTest::LeakTrace::Script script.pl

	$ perl -MTest::LeakTrace::Script=-verbose script.pl

	#!perl
	use Test::LeakTrace::Script sub{
		my($svref, $file, $line) = @_;

		warn "leaked $svref from $file line $line.\n";
	};

=cut

