package Test::LeakTrace;

use 5.008_001;
use strict;
use warnings;
use Carp ();

our $VERSION = '0.01';

use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
	leaktrace leaked_refs leaked_info leaked_count
);
our @EXPORT_FAIL = qw(not_leaked leaked_cmp_ok);

push @EXPORT, @EXPORT_FAIL;

sub export_fail{
	require Test::LeakTrace::Heavy;
	return;
}

sub leaked_refs(&){
	my($block) = @_;

	if(not defined wantarray){
		Carp::craok('Useless use of leaked_refs() in void context');
	}

	_start(0);

	{
		local $@;
		local $SIG{__DIE__};

		eval{
			$block->();
		};
		if($@){
			warn $@;
		}
	}

	return _finish();
}

sub leaked_info(&){
	my($block) = @_;

	if(not defined wantarray){
		Carp::craok('Useless use of leaked_info() in void context');
	}

	_start(1);

	{
		local $@;
		local $SIG{__DIE__};

		eval{
			$block->();
		};
		if($@){
			warn $@;
		}
	}

	return _finish();
}


sub leaked_count(&){
	my($block) = @_;
	return scalar &leaked_refs($block);
}

sub leaktrace(&;$){
	my($block, $callback) = @_;

	_start(1);

	{
		local $@;
		local $SIG{__DIE__};

		eval{
			$block->();
		};
		if($@){
			warn $@;
		}
	}

	_finish($callback);
	return;
}

1;
__END__

=head1 NAME

Test::LeakTrace - Traces memory leaks (EXPERIMENTAL)

=head1 VERSION

This document describes Test::LeakTrace version 0.01.

=head1 SYNOPSIS

	use Test::LeakTrace;

	# simple report
	leaktrace{
		# ...
	};
	# verbose report
	leaktrace{
		# ...
	} -verbose;
	# with callback
	leaktrace{
		my($ref, $file, $line) = @_;
		warn "leaked $ref at $file line\n";
	}

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

=item not_leaked { BLOCK }

=item leaked_cmp_ok { BLOCK }

=back

=head1 DEPENDENCIES

Perl 5.8.1 or later.

=head1 BUGS

No bugs have been reported.

Please report any bugs or feature requests to the author.

=head1 SEE ALSO

L<Devel::LeakTrace>.

L<Devel::LeakTrace::Fast>.

=head1 AUTHOR

Goro Fuji E<lt>gfuji(at)cpan.orgE<gt>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, Goro Fuji. Some rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
