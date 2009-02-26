package Test::LeakTrace;

use 5.008_001;
use strict;
use warnings;
use Carp ();

our $VERSION = '0.05';

use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

use Exporter qw(import);
our @EXPORT = qw(
	leaktrace leaked_refs leaked_info leaked_count
	not_leaked leaked_cmp_ok
);

our %EXPORT_TAGS = (
	all  => \@EXPORT,
	test => [qw(not_leaked leaked_cmp_ok)],
	util => [qw(leaktrace leaked_refs leaked_info leaked_count)],
);

sub not_leaked(&;$){
	require Test::LeakTrace::Heavy;

	goto \&Test::LeakTrace::Heavy::_not_leaked;
}
sub leaked_cmp_ok(&$$;$){
	require Test::LeakTrace::Heavy;

	goto &Test::LeakTrace::Heavy::_leaked_cmp_ok;
}

sub _do_leaktrace{
	my($block, $name, $need_stateinfo, $mode) = @_;

	if(!defined($mode) && !defined wantarray){
		Carp::croak("Useless use of $name() in void context");
	}

	{
		local $SIG{__DIE__} = 'DEFAULT';

		_start($need_stateinfo);

		eval{
			$block->();
		};
		if($@){
			_finish(-silent);
			die $@;
		}
	}

	return _finish($mode);
}

sub leaked_refs(&){
	my($block) = @_;
	return _do_leaktrace($block, 'leaked_refs', 0);
}

sub leaked_info(&){
	my($block) = @_;
	return _do_leaktrace($block, 'leaked_refs', 1);
}


sub leaked_count(&){
	my($block) = @_;
	return scalar _do_leaktrace($block, 'leaked_count', 0);
}

sub leaktrace(&;$){
	my($block, $mode) = @_;

	$mode = -simple unless defined $mode;
	_do_leaktrace($block, 'leaktrace', 1, $mode);
	return;
}

1;
__END__

=head1 NAME

Test::LeakTrace - Traces memory leaks

=head1 VERSION

This document describes Test::LeakTrace version 0.05.

=head1 SYNOPSIS

	use Test::LeakTrace;

	# simple report
	leaktrace{
		# ...
	};

	# verbose output
	leaktrace{
		# ...
	} -verbose;

	# with callback
	leaktrace{
		# ...
	} sub {
		my($ref, $file, $line) = @_;
		warn "leaked $ref from $file line\n";
	};

	my @refs = leaked_refs{
		# ...
	};
	my @info = leaked_info{
		# ...
	};

	my $count = leaked_count{
		# ...
	};

	# standard test interface
	use Test::LeakTrace;

	not_leaked{
		# ...
	} "description";

	leaked_cmp_ok{
		# ...
	} '<', 10;

=head1 DESCRIPTION

C<Test::LeakTrace> provides several functions that trace memory leaks.
This module scans arenas, the memory allocation system,
so it can detect any leaked SVs in given blocks.

TODO: writeing the document

=head1 INTERFACE

=head2 Exported functions

=head3 leaked_info { BLOCK }

Executes I<BLOCK> and returns a list of leaked SVs and places where the SVs come from.

=head3 leaked_refs { BLOCK }

Executes I<BLOCK> and returns a list of leaked SVs.

=head3 leaked_count { BLOCK }

Executes I<BLOCK> and returns the number of leaked SVs.

=head3 leaktrace { BLOCK } ?($mode | \&callback)

Executes I<BLOCK> and reports leaked SVs to C<*STDERR>.

Defined I<$mode>s are:

=over 4

=item -simple

Default. Reports the leaked SV identity (type and address), filename and line number.

=item -sv_dump

In addition to B<-simple>, dumps the sv content using C<sv_dump()>,
which also implements C<Devel::Peek::Dump()>.

=item -lines

In addition to B<-simple>, prints suspicious source lines.

=item -verbose

Both B<-sv_dump> and B<-lines>.

=back

=head3 not_leaked { BLOCK } ?$description

Tests that I<BLOCK> does not leaks SVs. This is a test function
using C<Test::Builder>.

Note that I<BLOCK> is called more than once. This is because
I<BLOCK> might prepare caches which are not memory leaks.

=head3 leaked_cmp_ok { BLOCK } $cmp_op, $number, ?$description

Tests that I<BLOCK> leakes a specific number of SVs. This is a test
function using C<Test::Builder>.

Note that I<BLOCK> is called more than once. This is because
I<BLOCK> might prepare caches which are not memory leaks.

=head2 Script interface

Like C<Devel::LeakTrace> C<Test::LeakTrace::Script> is provided for whole scripts.

The arguments of C<use Test::LeakTrace::Script> directive is the same as C<leaktrace()>.

	$ TEST_LEAKTRACE=-sv_dump perl -MTest::LeakTrace::Script script.pl
	$ perl -MTest::LeakTrace::Script=-verbose script.pl

	#!perl
	# ...

	use Test::LeakTrace::Script sub{
		my($ref, $file, $line) = @_;
		# ...
	};

	# ...

=head1 EXAMPLES

=head2 Testing modules

Here is a test script template that checks memory leaks.

	#!perl -w
	use strict;
	use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };
	use Test::More HAS_LEAKTRACE ? (tests => 1) : (skip_all => 'require Test::LeakTrace');
	use Test::LeakTrace;

	use Some::Module;

	leaked_cmp_ok{
		my $o = Some::Module->new();
		$o->something();
		$o->something_else();
	} '<', 1;

=head1 DEPENDENCIES

Perl 5.8.1 or later, and a C compiler.

=head1 BUGS

No bugs have been reported.

Please report any bugs or feature requests to the author.

=head1 SEE ALSO

L<Devel::LeakTrace>.

L<Devel::LeakTrace::Fast>.

L<Test::TraceObject>.

L<Test::Weak>.

For guts:

L<perlguts>.

L<perlhack>.

F<sv.c>.

=head1 AUTHOR

Goro Fuji E<lt>gfuji(at)cpan.orgE<gt>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, Goro Fuji. Some rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
