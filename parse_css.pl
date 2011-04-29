#! /usr/bin/perl

##############################################################################
#                                                                            #
# parse_css -- Substitute variables in css file / 4240305 - 7170705          #
#                                                                            #
# Use like this:                                                             #
#   <link rel="stylesheet" type="text/css" href="$usage"></link>             #
#                                                                            #
# Copyright (C) 2005-2011 Jens Wille <jens.wille@gmail.com>                  #
#                                                                            #
# parse_css is free software: you can redistribute it and/or modify it under #
# the terms of the GNU Affero General Public License as published by the     #
# Free Software Foundation, either version 3 of the License, or (at your     #
# option) any later version.                                                 #
#                                                                            #
# parse_css is distributed in the hope that it will be useful, but WITHOUT   #
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or      #
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public        #
# License for more details.                                                  #
#                                                                            #
# You should have received a copy of the GNU Affero General Public License   #
# along with parse_css. If not, see <http://www.gnu.org/licenses/>.          #
#                                                                            #
##############################################################################

use strict;
use warnings;

use CGI::Carp qw(fatalsToBrowser);
use CGI qw(param url);
use LWP::Simple;

(my $url  = url()) =~ s{\?\z}{};
my $base  = url(-base => 1);
my $usage = "usage: $url?{local=<local_css_url>|remote=<remote_css_url>}[&type=<type>][&strip=(0|1)]";

my %query   = ();
my $css_url = '';
my $type    = '1';
my $strip   = 1;

die "$usage\n" unless param();

if    ($css_url = param('local')) {
  $css_url =~ s{\A$base}{}i;
  die "not a local file!\n$usage\n"  if $css_url =~ m{\Ahttp://}i;
  $css_url = $base . $css_url;
}
elsif ($css_url = param('remote')) {
  die "not a remote file!\n$usage\n" if $css_url =~ m{\A(?:$base|/)}i;
}
else {
  die "$usage\n";
}
die "not a css file $css_url!\n" unless $css_url =~ m{\.css\z};

my $css = get($css_url);
die "css file $css_url not found!\n" unless $css;

$type  = defined param('type')  ? param('type')  : $type;
$strip = defined param('strip') ? param('strip') : $strip;

# type=0
# send original file

if ($type eq '1') {
  # variable definition:
  # #<var># = <value>;
  my %vars = ($css =~ m{#(.*?)#\s*=\s*(.*);}g);

  # variable use:
  # %<var>%
  foreach (keys %vars) { 
    $css =~ s{%$_%}{$vars{$_}}g;
  }
}

if ($strip) {
  $css =~ s{/\*.*?\*/}{}sg;
  $css =~ s{^\s*(.*?:)\s*}{$1}mg;
  $css =~ s{(?<!\})\n}{}g;
}

print "Content-type: text/css\n\n";
print $css;
