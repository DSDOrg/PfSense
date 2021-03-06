# ----------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42)
# <tobez@tobez.org> wrote this file.  As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return.   Anton Berezin
# ----------------------------------------------------------------------------
#
# $Id: Override.pm 16 2009-02-21 14:06:04Z godegisel $
#
package BSDPAN::Override;
#
# The pod documentation for this module is at the end of this file.
#
use strict;
use Carp;
use BSDPAN;
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(override);

my %overridden;		# a cache to detect multiple overrides

sub import {
	my $pkg = caller;
	croak("BSDPAN::Override can only operate for other BSDPAN modules")
	    unless $pkg =~ s/^BSDPAN:://;

	# make sure the BSDPAN module will not stay on the way
	my @oinc = @INC;
	my $bsdpan_path = BSDPAN->path;
	my @ninc;
	for my $inc_component (@INC) {
		push @ninc, $inc_component
			unless BSDPAN->canonical_path($inc_component) eq $bsdpan_path;
	}
	@INC = @ninc;
	my $pm = $pkg;
	$pm =~ s|::|/|g;
	delete $INC{"$pm.pm"};

	# try to load the original module
	# XXX be careful with nested `use' and `require'
	eval "require $pkg;" or die("Cannot load $pkg: $@");

	# restore the original @INC
	@INC = @oinc;

	# do the traditional `sub import' job
	BSDPAN::Override->export_to_level(1, @_);

	# and prepare `sub import' functionality for the original module
	my $pkg_isa = eval "*$pkg\::ISA\{ARRAY}";
	if ($pkg_isa && grep { /Exporter/ } @$pkg_isa) {
		eval "package $pkg; sub import { $pkg->export_to_level(1,\@_); }";
		die $@ if $@;
	}
}

sub override ($$) {	## no critic (ProhibitSubroutinePrototypes)
	my ($name, $replacement_sub) = @_;

	# do nothing if requested so
	return if $ENV{DISABLE_BSDPAN};

	# if name is unqualified, try to guess the right namespace
	unless ($name =~ /::/) {
		my $pkg = caller;
		croak("BSDPAN::Override can only operate for other BSDPAN modules")
		    unless $pkg =~ s/^BSDPAN:://;
		$name = "$pkg\::$name";
	}

	# do nothing if $name is already overridden
	return if $overridden{$name};

	# get the package $name belongs to
	my $pkg = $name; $pkg =~ s/::[^:]*$//;

	# do we need to protect against SelfLoader?
	my $sl_autoload = eval "*$pkg\::AUTOLOAD{CODE}";
	if ($sl_autoload) {
	   	require SelfLoader;
		$sl_autoload = 0
		    if $sl_autoload != \&SelfLoader::AUTOLOAD;
	}

	# get the reference to the original sub
	my $name_addr = eval "*$name\{CODE}";

        #
	# Substitute the symbol table entry with the replacement sub.
	#
	if ($name_addr) {
		# temporarily disable warnings
		local $SIG{__WARN__} = sub {};
		if ($sl_autoload) {
			# Ouch!  Don't ask.  :-)
			eval <<EOF;
*$name = sub {
	\$replacement_sub->( sub {
		\$SelfLoader::AUTOLOAD = "$name";
		local \$SIG{__WARN__} = sub {};
		my \@r = \$sl_autoload->(\@_);
		my \$real_addr = eval "*$name\{CODE}";
		my \$repsub2 = \$replacement_sub;
		eval "*\$name = sub {
			\\\$repsub2->(
				\\\$real_addr, \\\@_) };";
		\@r;
		}, \@_)
};
EOF
		} else {
			eval "*$name = sub {
				\$replacement_sub->(\$name_addr, \@_) };";
		}
		die "$@\n" if $@;
		$overridden{$name} = 1;
	} else {
		croak("Cannot override `$name': there is no such thing");
	}
}

1;
__END__
=head1 NAME

BSDPAN::Override - Perl module for overriding subs in other modules

=head1 SYNOPSIS

  package BSDPAN::Some::Perl::Module;
  use BSDPAN::Override;
  ...
  sub my_sub {
     my $orig = shift;
     ...
     &$orig;
     ...
  }
  ...
  BEGIN { override 'some_sub', \&my_sub; }

=head1 DESCRIPTION

BSDPAN::Override provides a way for other BSDPAN modules to override the
functionality of arbitrary Perl modules.

=head1 AUTHOR

Anton Berezin, tobez@tobez.org

=head1 SEE ALSO

C<perl(1)>, L<BSDPAN>.

=cut
