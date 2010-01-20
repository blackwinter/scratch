#! /usr/bin/perl

# sto2dbm: merge sto(s) into midos dbm / 3240805

use strict;
use warnings;

my $usage = "usage: $0 <file.dbm> <field>=<file.sto> ...";
die "$usage\n" unless @ARGV && @ARGV >= 2;

my ($dbm, @arg) = @ARGV;

die "not a dbm file '$dbm'!\n$usage\n" unless $dbm =~ m/\.dbm$/i;
die "can't find dbm file '$dbm'!\n"    unless -r $dbm;

my %sto_hash = ();
my %dbm_hash = ();

foreach my $arg (@arg) {
  my ($field, $sto) = split('=', $arg, 2);
  die "invalid argument: $arg\n" unless $field && $sto;

  unless ($sto =~ m/\.sto$/i && -r $sto) {
    warn "invalid sto file: $sto! skipping...\n";
    next;
  }

  open(STO, "< $sto") or die "can't open sto file '$sto': $!\n";

  while (my $line = <STO>) {
    $line =~ s/\s*\r?\n//;
    $line =~ s/^\s*//;
    next unless length $line;

    my ($id, $terms) = split(/\s*\*\s*/ => $line, 2);

    $sto_hash{$field}->{$id} = $terms;
  }

  close STO;
}

die "nothing to do!\n" unless %sto_hash;

open(DBM, "< $dbm") or die "can't open dbm file '$dbm': $!\n";

my ($cur_id, $i) = ('', 0);
while (my $line = <DBM>) {
  $line =~ s/\s*\r?\n//;
  $line =~ s/^\s*//;
  next unless length $line;

  if    ($line =~ m/^(\w+):(.*)$/) {
    my ($f, $v) = ($1, $2);

    # first field stores id!?
    $cur_id = $2 unless length $cur_id;

    die "[$.] $cur_id: $f: $dbm_hash{$cur_id}->{$f}" if exists $dbm_hash{$cur_id}->{$f};

    # to store fields in correct order
    my $j = sprintf("%02d", ++$i);

    $dbm_hash{$cur_id}->{"$j.$f"} = $v;
  }
  elsif ($line eq '&&&') {
    ($cur_id, $i) = ('', 0);
  }
  else {
    die "[$.] $line\n";
  }
}

close DBM;

open(DBM, "> $dbm") or die "can't open dbm file '$dbm' for writing: $!\n";

foreach my $id (sort keys %dbm_hash) {
  foreach my $f (sort keys %{$dbm_hash{$id}}) {
    (my $g = $f) =~ s/^\d+\.//;

    my $v = (exists $sto_hash{$g}->{$id}) ? $sto_hash{$g}->{$id} : $dbm_hash{$id}->{$f};

    print DBM "$g:$v\n" if length $v;
  }

  print DBM "&&&\n\n";
}

close DBM;

exit 0;

