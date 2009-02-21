package Test::LeakTrace::Script;

use strict;

use Test::LeakTrace ();

INIT{
	Test::LeakTrace::_start(1);
}

END{
	my $verbose = $ENV{PERL_LEAKTRACE_VERBOSE} || $ENV{LEAKTRACE_VERBOSE};
	Test::LeakTrace::_finish($verbose);
	return;
}

1;
__END__

=head1 NAME

Test::LeakTrace::Script - A LeakTrace interface for whole scripts

=head1 SYNOPSIS

	$ perl -MTest::LeakTrace::Script script.pl

=cut

