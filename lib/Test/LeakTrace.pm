package Test::LeakTrace;

use 5.008_001;
use strict;
use warnings;
use Carp ();

our $VERSION = '0.02';

use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

use Exporter qw(import);;
our @EXPORT = qw(
	leaktrace leaked_refs leaked_info leaked_count
	not_leaked leaked_cmp_ok
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
			scalar _finish(); # cleanup
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
	my($block, $callback) = @_;

	$callback = -verobse unless defined $callback;

	_do_leaktrace($block, 'leaktrace', 1, $callback);
	return;
}

1;
__END__

=head1 NAME

Test::LeakTrace - Traces memory leaks (EXPERIMENTAL)

=head1 VERSION

This document describes Test::LeakTrace version 0.02.

=head1 SYNOPSIS

	use Test::LeakTrace;

	# simple report
	leaktrace{
		# ...
	};

	# with verbose output
	leaktrace{
		# ...
	} -verbose;

	# with callback
	leaktrace{
		# ...
	} sub{ 
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

	# script interface like Devel::LeakTrace
	use Test::LeakTrace::Script;
	# ...

	$ LEAKTRACE_VERBOSE=1 perl -MTest::LeakTrace::Script script.pl

=head1 DESCRIPTION

C<Test::LeakTrace> traces memory leakes.

(TODO)

=head1 INTERFACE

=head2 Exported functions

=over 4

=item leaktrace { BLOCK }

=item leaktrace { BLOCK } -verbose

=item leaktrace { BLOCK } \&callback

=item leaked_refs { BLOCK }

=item leaked_info { BLOCK }

=item leaked_count { BLOCK }

=item not_leaked { BLOCK } ?$description

Checks that I<BLOCK> does not leaks SVs. This is a test function
using C<Test::Builder>.

Note that I<BLOCK> is called more than once. This is because
I<BLOCK> might prepare caches which are not memory leaks.

=item leaked_cmp_ok { BLOCK } $op, ?$description

Checks that I<BLOCK> leakes a specific number of SVs. This is a test
function using C<Test::Builder>.

Note that I<BLOCK> is called more than once. This is because
I<BLOCK> might prepare caches which are not memory leaks.

=back

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

=head1 AUTHOR

Goro Fuji E<lt>gfuji(at)cpan.orgE<gt>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, Goro Fuji. Some rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
