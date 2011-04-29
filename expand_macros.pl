#! /usr/bin/perl

##################################################################################
#                                                                                #
# expand_macros.pl -- recursively expand greenstone macros / 1080805 - 1230106   #
#                                                                                #
# Copyright (C) 2005-2011 Jens Wille <j_wille at gmx.net>                        #
#                                                                                #
# expand_macros is free software: you can redistribute it and/or modify it under #
# the terms of the GNU Affero General Public License as published by the Free    #
# Software Foundation, either version 3 of the License, or (at your option) any  #
# later version.                                                                 #
#                                                                                #
# expand_macros is distributed in the hope that it will be useful, but WITHOUT   #
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS  #
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more   #
# details.                                                                       #
#                                                                                #
# You should have received a copy of the GNU Affero General Public License along #
# with expand_macros. If not, see <http://www.gnu.org/licenses/>.                #
#                                                                                #
##################################################################################

#
# expand_macros.pl reads in specified greenstone macro files and prints the
# definitions of requested macros and recursively the definitions of macros
# used within these definitions.
#
# see <http://wiki.greenstone.org/wiki/index.php/All_about_macros> for more info.
#
#
# FEATURES:
#
# - generic:
#
#   - additional/collection-specific macro files can be included
#
#   - macros set within the server can be included (though this might not be
#     of much help without reading the respective source file)
#
# - "interactive browse mode" where you can select which macro (and from which
#   package) to display next.
#
#   - readline support and persistent history
#
#   - interactive commands
#
#   - read files from within interactive browse mode
#
# - batch mode only:
#
#   - search for macros that use certain macros ("reverse" search)
#
#   - search for strings (regular expressions) in macro definitions
#
#
# TODO:
#
# - add "reverse search" and "string search" for browse mode
#
# - handle macro options better (v, c, l, ...?)
#
# - implement some kind of "persistent" macro db (so that it doesn't need to be
#   built each and every time)
#
#
# KNOWN ISSUES:
#
# - for a sufficiently large file (> 12288 bytes == 12 k) (paged-)read will quit
#   the program if not scrolled until the end of the file => SIGPIPE: broken pipe!
#   SOLVED: the PIPE signal will simply be IGNOREd
#

use strict;
use warnings;

use Getopt::Long          qw(GetOptions);

use File::Basename        qw(basename dirname);
use File::Spec::Functions qw(catdir catfile curdir);

use IO::Handle            qw(autoflush);
STDOUT->autoflush(1);

use Term::ReadLine;


### progname and version

my $NAME    = basename $0;
my $VERSION = '0.22';


### global patterns

# my understanding of greenstone macro names:
#   - enclosed in underscores ('_')
#   - starts with a letter ([:alpha:])
#   - followed by alphanumeric characters ([:alnum:])
#     (consequently, it doesn't start with a number and
#     particularly isn't a macro parameter, i.e. something like _1_)
#   - also we might need to take care of escaped underscores ('\_')
#
#   => does this fit??? (see '<gsdl-source>/src/lib/display.cpp' for details,
#      in particular the 'displayclass::loadparammacros' method)
my $MACRO_PATTERN       = '[[:alpha:]][[:alnum:]]*';

# package names: letters
my $PACKAGE_NAME        = '[[:alpha:]]+';

# package specification: package name followed by a colon (':')
my $PACKAGE_PATTERN     = $PACKAGE_NAME . ':';

# beginning/end of macro specification: underscore ('_'), not escaped,
# i.e. not preceded by a backslash ('\')
# (need to double-escape backslash here!)
my $MACRO_AFFIX         = '(?<!\\\)_';

# beginning of macro definition: opening curly bracket ('{')
my $DEFINITION_START    = '\{';

# end of macro definition: closing curly bracket ('}'), not escaped,
# i.e. not preceded by a backslash ('\')
# (need to double-escape backslash here!)
my $DEFINITION_END      = '(?<!\\\)\}';

# package declaration: 'package' (plus package name)
my $PACKAGE_DECLARATION = 'package';


### command line arguments

# variable initialisation and default values
my %ARG = (
  'verbose'     => 0,
  'version'     => 0,
  'depth'       => 0,
  'short'       => 0,
  'reverse'     => 0,
  'interactive' => 0,
  'paged'       => 0,
  'pager'       => $ENV{'PAGER'} || 'less',
  'histfile'    => catfile($ENV{'HOME'} || curdir, '.expand_macros.history'),
  'histsize'    => 100,
  'macro_dirs'  => [catdir($ENV{'GSDLHOME'}, 'macros')],
  'source_dir'  => $ENV{'GSDLSOURCE'} || '',
  'args'        => []
);

# global vars
my $TERM         = '';
my $CURRENT_FILE = '';

# usage information and help text
my $USAGE = <<HERE_USAGE;
usage:
    $NAME [generic-options] [-s] [-d <depth>] [-r] {_[<package>:]<macro>_|<query>} ...
    $NAME [generic-options] {-b|-i} [-p]
    $NAME [-h|-?|--help]

    generic options are: [-v] [-e <directory>,...] [-n <version>]
HERE_USAGE

my $HELP = <<HERE_HELP;
$NAME: recursively expand greenstone macros (v$VERSION)

$USAGE

generic options:

    -h, -?, --help                   display this help and exit
    -v,     --verbose                output some extra information/warnings

    {-e|--extra} <directory>,...     paths to extra macro directories, comma-separated list
                                     [default directory: '$ARG{'macro_dirs'}[0]']

            --source <directory>     path to greenstone source directory, so that macros which are
                                     set within the server will be included
                                     [default: '$ARG{'source_dir'}']
                                     NOTE: you can set an environment variable GSDLSOURCE instead

    {-n|--show-version} <version>    print only macro definitions for specified version (0=graphic/1=text)
                                     [default: '$ARG{'version'}', set to '-1' for 'all']

    -s,     --short                  short output, i.e. only macro names, no content


batch mode:

    {-d|--depth} <depth>             how deep to recurse through macros
                                     [default: '$ARG{'depth'}', set to '-1' for 'unlimited']

    -r,     --reverse                reverse search, recursively outputs the macros which use the specified macro

    all non-option arguments will be treated as
      - macro names (denoted by surrounding underscores '_')
        or
      - regular expressions to search for in macro definitions (otherwise)

    (you can restrict your macro name query to a certain package by prepending the macro name with '<package-name>:')

    EXAMPLES:

      get definition of the 'pagescriptextra' macro
      > $NAME _pagescriptextra_

      get definition of the 'pagescriptextra' macro, package 'query' only
      > $NAME _query:pagescriptextra_

      get definition of the 'pagescriptextra' macro, package 'query' only -- and recursively get definitions of
      macros used within that definition (up to level 2)
      > $NAME -d 2 _query:pagescriptextra_

      get all the macros that use the 'pagescriptextra' macro (names only)
      > $NAME -r -s _pagescriptextra_


interactive browse mode:

    -b, -i, --browse                 interactive browse mode, allows you to select what to display next

    -p,     --paged                  data output will be passed to a pager
                                     [default: '$ARG{'pager'}']
            --pager <pager>          pass paged output to specified pager instead of above named default

            --histfile <file>        path to history file to keep history between sessions
                                     [default: '$ARG{'histfile'}']
            --histsize <num>         maximum number of lines to keep in histfile
                                     [default: '$ARG{'histsize'}']
                                     NOTE: in case you don\'t want the history to be stored you may set
                                           <histfile> to '' or <histsize> to '0'
                                           (however, this does not remove any existing history files)


NOTE: for this script to run your greenstone environment needs to be set up (GSDLHOME set)
HERE_HELP

my $HELP_INTERACTIVE = <<HERE_HELP;
$NAME: expand greenstone macros in ***interactive browse mode*** (v$VERSION)


usage instructions:

    - commands are equal to command line options, except that they start with a dot '.'
      (NOTE: not all command line options are available as commands, see list below)

    - commands that take an optional argument ([...]) will print their current value if
      that argument is omitted (you can also use '.c' or '.config' to get a full overview)

    - you can run several commands at once by separating them with semicolons

    - you can quit the program at any time by hitting <ctrl>+d (<ctrl>+z on windows), or
      by typing '.q', or '.quit'


commands:

    .h, .?, .help                    display this help

    .q,     .quit                    exit program

    .                                redisplay current stage

    ..                               return to previous stage (same as leaving empty)

    ..., .t, .top                    return to top to enter new macro name

    {.n|.show-version} [<version>]   print only macro definitions for specified version (0=graphic/1=text)
                                     [default: '0', set to '-1' for 'all']

    .s,     .short                   short output, i.e. only macro names, no content

    .p,     .paged                   data output will be passed to a pager
                                     [default: '$ARG{'pager'}']
            .pager [<pager>]         pass paged output to specified pager instead of above named default

    .r,     .read [<file>]           display the contents of the specified file (by default the last file we came across)
    .pr,    .paged-read [<file>]     same, but paged (without turning on paged mode permanently)

    .c,     .config                  display current configuration
HERE_HELP

# allow for bundling of options
Getopt::Long::Configure ("bundling");

# parse arguments
GetOptions( 'help|h|?'         => sub { print "$HELP\n"; exit 0 },
            'verbose|v'        => \$ARG{'verbose'},
            'only-version|n=i' => \$ARG{'version'},
            'extra|e=s'        => \@{$ARG{'macro_dirs'}},
            'source=s'         => \$ARG{'source_dir'},
            'depth|d=i'        => \$ARG{'depth'},
            'short|s'          => \$ARG{'short'},
            'reverse|r'        => \$ARG{'reverse'},
            'browse|b|i'       => \$ARG{'interactive'},
            'paged|p'          => \$ARG{'paged'},
            'pager=s'          => \$ARG{'pager'},
            'histfile=s'       => \$ARG{'histfile'},
            'histsize=i'       => \$ARG{'histsize'},
            '<>'               => sub { push(@{$ARG{'args'}} => @_) } )
  or die "$USAGE\n";


### some sanity checks (dunno which one to check first ;-)

# need one of our "actions": batch, query or interactive
# ("batch" requiring at least one macro name or regexp specified)
unless (@{$ARG{'args'}} || $ARG{'interactive'}) {
  warn "$USAGE";

  warn <<HERE_WARN unless $ENV{'GSDLHOME'};

GSDLHOME not set!

for this script to run your greenstone environment needs to be set up. please
change into the directory where greenstone has been installed and run/source
the appropriate setup script.
HERE_WARN

  die "\n";
}

# need GSDLHOME for default macro directory
# (does also allow to have the script in gsdl bin path)
die "GSDLHOME not set! please change into the directory where greenstone has been installed and run/source the appropriate setup script.\n"
  unless $ENV{'GSDLHOME'};

## need one of our "actions": batch, query or interactive
# ("batch" requiring at least one macro name or regexp specified)
#die "$USAGE\n"
#  unless @{$ARG{'args'}} || $ARG{'interactive'};


### action!

# build hash of macro information
my %macro_db = build_db();
die "macro db empty!\n"
  unless %macro_db;

unless ($ARG{'interactive'}) {
  # batch mode

  my $n = 0;
  foreach my $arg (@{$ARG{'args'}}) {
    if ($arg =~ s/^$MACRO_AFFIX((?:$PACKAGE_PATTERN)?$MACRO_PATTERN)$MACRO_AFFIX$/$1/) {
      # macro

      print "*** macro: $arg", ($ARG{'reverse'} ? ' (reverse) ' : ' '), "***\n\n";

      unless ($ARG{'reverse'}) {
        # "normal" search

        get_macro($arg);
      }
      else {
        # "reverse" search

        # get the macros that use the specified macro
        my @refs = get_r_macros($arg);
        print "no macro referencing '$arg'\n\n"
          unless @refs;

        # now recurse those macros
        get_macro($_)
          foreach @refs;
      }
    }
    else {
      # query

      print "*** query: $arg", ($ARG{'reverse'} ? ' (reverse) ' : ' '), "***\n\n";

      # get the macros that match the specified query
      my @macros = get_r_macros($arg, 1);
      print "no matches for '$arg'\n", ($ARG{'short'} ? '' : "\n")
        unless @macros;

      # now print those macros
      get_macro($_)
        foreach @macros;
    }

    # print separator _between_ requested macros (i.e. everytime but the last time)
    # (need to add extra newline for short display)
    print(($ARG{'short'} ? "\n" : ''), '-' x 80, "\n\n")
      unless ++$n >= @{$ARG{'args'}};
  }
}
else {
  # interactive browse mode

  # ignore 'broken pipe' error
  $SIG{'PIPE'} = 'IGNORE';

  # get the pager executable (no need to test if not in "paged" mode)
  get_pager()
    if $ARG{'paged'};

  # create new Term::ReadLine object
  $TERM = Term::ReadLine->new($NAME);

  # don't want the prompt underlined
  $TERM->ornaments(0);
  # don't want autohistory (can't set autohistory explicitly, so use this "workaround")
  $TERM->MinLine(undef);

  # restore history
  readhist();

  # print help hint
  print <<HERE_HINT;
entered '$NAME' in ***interactive browse mode*** (v$VERSION)
[you can get help at any time by typing '.h', '.?', or '.help']

HERE_HINT

  # repeat until explicit exit
  while (1) {
    my $macro = prompt("enter macro name (without package specification) [leave empty to quit]\n> ");

    # remove surrounding '_'
    $macro =~ s/^_//;
    $macro =~ s/_$//;

    exit 0 unless length $macro;                    # normal exit
    next   if     $macro eq '0' || $macro eq '-1';  # a command was executed

    # now get all packages for given macro, and begin recursion...
    recurse_packages($macro);
  }

  # can't expect anything down here to be executed
}

END {
  if ($ARG{'interactive'}) {
    # save history
    savehist();
  }
}


### that's it ;-)

exit 0;


### subroutines

# <sub build_db>
# build hash of macro information ("macro db")
#
# hash structure:
#   macro
#   -> package
#      -> {'0=graphic'|'1=text'}
#         -> 'file'
#         -> 'line'
#         -> 'content'
#
# usage:
#   %macro_db = build_db()
#
#  => macro_db: returned hash ("macro db")
#
sub build_db {
  my %macro_db = ();
  my @dm_list  = ();
  my ($n, $m) = (0, 0);

  # get all macro files (*.dm) from specified directories
  foreach my $dir (@{$ARG{'macro_dirs'}}) {
    opendir(DIR, "$dir")
      or die "can't read macro directory '$dir': $!\n";

    push(@dm_list => map { $_ = catfile($dir, $_) } grep { /\.dm$/ } readdir(DIR));

    closedir DIR;
  }

  # now parse each macro file and build hash
  foreach my $dm (sort @dm_list) {
    open(DM, "< $dm")
      or die "can't open macro file '$dm': $!\n";

    my ($name, $content, $version, $curpkg, $contd)
     = ('',    '',       '0',      '',      0);

    while (my $line = <DM>) {
      chomp($line);
      next unless length $line;      # skip empty lines
      next if     $line =~ /^\s*$/;  # skip "empty" lines
      next if     $line =~ /^\s*#/;  # skip comments (hope this doesn't affect
                                     # cases we actually wanted to keep)

      if    ($line =~ /^$PACKAGE_DECLARATION\s*($PACKAGE_NAME)/) {
        # remember the current package we are in
        $curpkg = $1;
      }
      elsif ($line =~ /$MACRO_AFFIX($MACRO_PATTERN)$MACRO_AFFIX\s*(\[v=1\])?\s*$DEFINITION_START\s*(.*)/) {
        # start of macro definition
        $n++;

        $name    = $1;
        $version = (defined $2 && $2 eq '[v=1]') ? '1' : '0';
        $content = $3 || '';

        # don't include unnecessary version, unless we're interactive (where version may change during session)
        next if $ARG{'version'} ne '-1' && $version ne $ARG{'version'} && ! $ARG{'interactive'};

        if (exists $macro_db{$name}->{$curpkg}->{$version}) {
          # everytime a macro definition already exists, it's simply
          # overwritten - but we can give a warning
          # (this might also serve debugging purposes)
          $m++;

          warn <<HERE_WARN if $ARG{'verbose'};
duplicate definition of macro '$curpkg:$name' [v=$version] at '$dm', line $.
(previously defined at $macro_db{$name}->{$curpkg}->{$version}->{'file'}, line $macro_db{$name}->{$curpkg}->{$version}->{'line'})
HERE_WARN
        }

        # store the information we got so far
        $macro_db{$name}->{$curpkg}->{$version}->{'file'}    = $dm;
        $macro_db{$name}->{$curpkg}->{$version}->{'line'}    = $.;
        $macro_db{$name}->{$curpkg}->{$version}->{'content'} = [$content] if length $content;

        # is the macro definition already finished?
        $contd = ($content =~ s/\s*$DEFINITION_END.*//) ? 0 : 1;
      }
      elsif ($contd) {
        # continuation of macro definition

        # store additional content
        push(@{$macro_db{$name}->{$curpkg}->{$version}->{'content'}} => $line);

        # is the macro definition already finished?
        $contd = ($line =~ s/\s*$DEFINITION_END.*//) ? 0 : 1;
      }
      else {
        # something else...

        ($name, $content) = ('', '');
      }
    }

    close DM;
  }

  # get server macros (overwriting already read macros)
  if (length $ARG{'source_dir'}) {
    if (-r $ARG{'source_dir'}) {
      my $recpt_dir = catdir($ARG{'source_dir'}, 'src', 'src', 'recpt');
      my @cpp_list  = ();

      opendir(DIR, "$recpt_dir")
        or die "can't read receptionist's source directory '$recpt_dir': $!\n";

      push(@cpp_list => map { $_ = catfile($recpt_dir, $_) } grep { /\.cpp$/ } readdir(DIR));

      close DIR;

      foreach my $cpp (@cpp_list) {
        open(CPP, "< $cpp")
          or die "can't open source file '$cpp': $!\n";

        my $args  = '';
        my $contd = 0;
        while (my $line = <CPP>) {
          next unless $line =~ /disp\.setmacro\s*\((.*)/ || $contd;

          unless (defined $1) {
            $contd = 1;
            next;
          }

          my $string = $1;

          if    ($string =~ s/\);\s*$//) {
            $args .= $string;
            my ($name, $package, $value) = split(/\s*,\s*/ => $args, 3);

            $name    =~ s/^\s*["']?//;
            $name    =~ s/["']?\s*$//;
            $package =~ s/^\s*["']?//;
            $package =~ s/["']?\s*$//;

            $package = 'Global'
              if $package eq 'displayclass::defaultpackage';

            $macro_db{$name}->{$package}->{'0'}->{'file'}    = 'SERVER: ' . $cpp;
            $macro_db{$name}->{$package}->{'0'}->{'line'}    = $.;
            $macro_db{$name}->{$package}->{'0'}->{'content'} = [$value];

            $args = '';
            ++$n;
            $contd = 0;
          }
          elsif ($contd) {
            $args .= ' ' . $string;
          }
          else {
            $contd = 1;
          }
        }

        close CPP;
      }
    }
    else {
      warn "can't find source directory '$ARG{'source_dir'}'! server macros will not be included\n";
    }
  }

  # print some statistics
  print "$n total macro definitions, $m duplicates\n"
    if $ARG{'verbose'};

  # we stored all information there is so we can return it
  return %macro_db;
}
# </sub build_db>

# <sub get_macro>
# recursively print macro information
#
# usage:
#   get_macro($macro[, $level])
#
#   macro:    macro name (optionally including package specification)
#   level:    recursion level (optional)
#
#   => VOID CONTEXT
#
sub get_macro {
  my ($macro, $level) = @_;
  $level ||= 0;

  # indent output according to recursion level
  my $indent  = '    ' x $level;

  # get all the packages which our macro is defined in
  ($macro, my @packages) = get_packages($macro, $indent);
  return unless @packages;

  # macro definitions may occur in several packages so we display them all
  # (unless a certain package was explicitly specified)
  foreach my $pkg (@packages) {
    foreach my $version (sort keys %{$macro_db{$macro}->{$pkg}}) {
      print "$indent* $pkg:$macro [v=$version] ($macro_db{$macro}->{$pkg}->{$version}->{'file'}, line $macro_db{$macro}->{$pkg}->{$version}->{'line'})\n";

      my $content = '';
      # some macros are defined, but don't have any content
      if (defined $macro_db{$macro}->{$pkg}->{$version}->{'content'}) {
        # for batch display we condense the output a little bit...
        map { s/^\s*//; s/\s*$// } @{$macro_db{$macro}->{$pkg}->{$version}->{'content'}};
        # ...and put it on a single line
        $content = join(' ' => @{$macro_db{$macro}->{$pkg}->{$version}->{'content'}});
      }
      print "$indent  { $content }\n\n"
        unless $ARG{'short'};
        # short display only, i.e. no content
        # of the macro's definition

      # only go (deeper) into referenced macros if we
      # haven't reached the specified recursion level
      if ($ARG{'depth'} eq '-1' || $level < $ARG{'depth'}) {
        # get (referencing|referenced) macros...
        my @refs = $ARG{'reverse'}
                 ? get_r_macros($macro)
                 : get_macros($content);

        # ...and recurse above them (with increased recursion level)
        foreach my $ref (@refs) {
          get_macro($ref, $level + 1);
        }
      }
    }
  }
}
# </sub get_macro>

# <sub get_macros>
# returns a list of macros extracted from a content string
# or a boolean value if a macro name was specified
#
# usage:
#   @macros  = get_macros($content)
#   $boolean = get_macros($content, $macro)
#
#   content: content string
#   macro:   macro name
#
#   => macros:  list of macros
#   => boolean: boolean value (true = 1 / false = empty list)
#
sub get_macros {
  my ($content, $macro) = @_;
  my @macro_list = ();
  my %seen       = ();

  # get each macro reference in the string
  # (for macro name considerations see above)
  while ($content =~ /$MACRO_AFFIX((?:$PACKAGE_PATTERN)?$MACRO_PATTERN)$MACRO_AFFIX/g) {
    my $m = $1;

                           # we want to skip some macros that have no content anyway (defined
                           # from within the server) - unless we're doing a "reverse" search
    next if $seen{$m}++ || ($m =~ /^(cgiarg.*|histvalue\d+|if|httpimg|gwcgi|(decoded)?compressedoptions)$/i
                            && ! $ARG{'reverse'});

    if (defined $macro) {
      # is this the macro we wanted? then the current
      # macro uses it => return true
      return 1 if $m =~ /^(?:$PACKAGE_PATTERN)?$macro$/;
    }
    else {
      # add macro to our list
      push(@macro_list => $m);
    }
  }

  # return the list of used macros
  # (this evaluates to false (empty list) if there are no further
  # macro calls or if this macro doesn't use the sought-after macro)
  return sort @macro_list;
}
# </sub get_macros>

# <sub get_r_macros>
# returns a list of macro names which reference ("use") the
# specified macro or match the query
#
# usage:
#   @macros = get_r_macros($macro)
#   @macros = get_r_macros($query, $is_query)
#
#   macro:    macro name
#   query:    query string (regular expression)
#   is_query: boolean value to indicate whether arg is a query or a macro
#
#   => macros: list of macros
#
sub get_r_macros {
  my ($arg, $query) = @_;
  $query ||= 0;
  my %refs = ();

  # need to test each single macro's...
  foreach my $m (sort keys %macro_db) {
    # ...each single package
    foreach my $p (sort keys %{$macro_db{$m}}) {
      foreach my $v (sort keys %{$macro_db{$m}->{$p}}) {
        my $pm = "$p:$m";  # include package information in the macro name!

        # does this macro have any content?
        if (defined $macro_db{$m}->{$p}->{$v}->{'content'}) {
          # stringify content!
          my $content = join(' ' => @{$macro_db{$m}->{$p}->{$v}->{'content'}});

          if ($query) {
            # search regexp
            $refs{$pm}++ if $content =~ /$arg/;
          }
          else {
            # search macro
            $refs{$pm}++ if get_macros($content, $arg);
          }
        }
      }
    }
  }

  # now we have all the macros which use our sought-after
  return sort keys %refs;
}
# </sub get_r_macros>

# <sub recurse_packages>
# recurse all packages for a given macro
#
# usage:
#   recurse_packages($macro)
#
#   macro:    macro name (any package specification will be dropped)
#
#   => VOID CONTEXT
#
sub recurse_packages {
  my ($macro) = @_;

  # repeat until explicit break/exit
  while (1) {
    # get all the packages which our macro is defined in
    #($macro, my @packages) = get_packages($macro);
    #return unless @packages;
    my @packages = ();

    my $n = 0;
    my $package = '';
    # ask for user's selection...
    do {
      # get all the packages which our macro is defined in
      ($macro, @packages) = get_packages($macro);
      return unless @packages;

      # ask for user's selection...
      print "select package for macro '$macro' [leave empty to return]\n";
      foreach my $pkg (@packages) {
        printf "    [%d]%s %s\n", ++$n, " " x (4 - length $n), $pkg;
      }
      $package = prompt();
      $n = 0;
    # ...until we return...
    } until ($package eq '' || $package eq '-1'
         # ...or a valid number is provided
         || ($package =~ /^\d+$/ && $package > 0 && $package <= @packages));

    return unless length $package;          # return to previous stage
    return '-1'   if     $package eq '-1';  # return to top

    # set selected package
    $package = $packages[$package - 1];

    foreach my $version (sort keys %{$macro_db{$macro}->{$package}}) {
                  # all versions
      next unless $ARG{'version'} eq '-1'
                  # desired version
               || $version eq $ARG{'version'}
                  # fallback to 'graphic'
               || ($version eq '0' && ! exists $macro_db{$macro}->{$package}->{'1'});

                    # some macros are defined, but don't have any content
      my $content = defined $macro_db{$macro}->{$package}->{$version}->{'content'}
                    # now we want to retain the original structure
                  ? join("\n" => @{$macro_db{$macro}->{$package}->{$version}->{'content'}})
                  : '';

      ($CURRENT_FILE = $macro_db{$macro}->{$package}->{$version}->{'file'}) =~ s/^SERVER: //;

      my $content_string = "* $package:$macro [v=$version] ($macro_db{$macro}->{$package}->{$version}->{'file'}, line $macro_db{$macro}->{$package}->{$version}->{'line'})\n";
      $content_string   .= "{ $content }\n"
        unless $ARG{'short'};

      print_output($content_string);

      # now on to the macros referenced within this one
      my $return = recurse_macros($content);

      return $return if defined $return;
    }
  }
}
# </sub recurse_packages>

# <sub get_packages>
# returns list of packages for specified macro, also returns
# modified macro name (without surrounding '_' and package specification)
#
# usage:
#   ($macro, @packages) = get_packages($macro)
#
#   macro:    macro name
#
#   => macro:    modified macro name
#   => packages: list of packages
#
sub get_packages {
  my ($macro, $indent) = @_;
  $indent ||= '';

  # save original macro name (including package specification)
  my $omacro = $macro;

  my @packages = ();

  if ($macro =~ /^($PACKAGE_PATTERN)?$MACRO_PATTERN$/) {
    # valid macro name

    # strip off package specification
    my $package = ($macro =~ s/^($PACKAGE_NAME)://) ? $1 : '';

    if (exists $macro_db{$macro}) {
      # valid/existing macro

      unless ($ARG{'interactive'}) {
        if (length $package) {
          # account for package specification

          @packages = ($package)
            if exists $macro_db{$macro}->{$package};
        }
        else {
          # get all packages otherwise

          @packages = sort keys %{$macro_db{$macro}};
        }
      }
      else {
        foreach my $pkg (sort keys %{$macro_db{$macro}}) {
          push(@packages => $pkg)
               # all versions
            if $ARG{'version'} eq '-1'
               # desired version
            || exists $macro_db{$macro}->{$pkg}->{$ARG{'version'}}
               # fallback to 'graphic'
            || exists $macro_db{$macro}->{$pkg}->{'0'};
        }
      }
    }
  }
  else {
    # invalid macro name

    warn "invalid macro name '$macro'!\n";
    return;  # skip it
  }

  # no packages - no definition
  unless (@packages) {
    print "$indent- $omacro\n$indent  no definition for macro!\n\n";
    return;  # skip it
  }

  # return modified macro name and packages found
  return $macro, sort @packages;
}
# </sub get_packages>

# <sub recurse_macros>
# recurse all macros for a given content string
#
# usage:
#   recurse_macros($content)
#
#   content:  content string
#
#   => VOID CONTEXT
#
sub recurse_macros {
  my ($content) = @_;

  # repeat until explicit break/exit
  while (1) {
    # get all the macros referenced within the current one
    my @macros = get_macros($content);
    return unless @macros;

    my $n = 0;
    my $macro = ''; 
    # ask for user's selection...
    do {
      print "select macro [leave empty to return]\n";
      foreach my $m (@macros) {
        printf "    [%d]%s %s\n", ++$n, " " x (4 - length $n), $m;
      }
      $macro = prompt();
      $n = 0;
    # ...until we return...
    } until ($macro eq '' || $macro eq '-1'
         # ...or a valid number is provided
         || ($macro =~ /^\d+$/ && $macro > 0 && $macro <= @macros));

    return unless length $macro;          # return to previous stage
    return '-1'   if     $macro eq '-1';  # return to top

    # set selected macro
    $macro = $macros[$macro - 1];

    # now we want all the macro's packages again
    my $return = recurse_packages($macro);

    return $return if defined $return;
  }
}
# </sub recurse_macros>

# <sub prompt>
# prompt for user input
#
# usage:
#   $reply = prompt([$prompt])
#
#   prompt:  optional prompt (default: '> ')
#
#   => reply: user input
#
sub prompt {
  my $prompt = shift || '> ';
  my $term   = $TERM;

  # read user input
  my $reply = $term->readline($prompt);

  if (defined $reply) {
    # add input to history, unless it's just a number
    $term->addhistory($reply)
      if $reply =~ /[[:alpha:]]/;

    if ($reply =~ s/^\s*["']*\s*\././) {
      # execute command
      my $return = parse_command($reply);

      return $return if defined $return;
    }
    else {
      return $reply;
    }
  }

  # allow for exiting by hitting <ctrl>+d,
  # or quitting by command (.q, .quit)
  die "\n";
}
# </sub prompt>

# <sub print_output>
# print output, paged or not
#
# usage:
#   print_output($output)
#   print_output(@output)
#
#   output: text to print
#
#   => VOID CONTEXT
#
sub print_output {
  my $output = join('' => @_);

  if ($ARG{'paged'}) {
    # pass output to pager
    open(PAGER, "| $ARG{'pager'}")
      or die "can't open pipe to '$ARG{'pager'}': $!";

    print PAGER "$output";

    close PAGER;
  }
  else {
    # print to standard out...
    print "\n$output\n";

    # ...and wait for user reaction to continue
    wait_for_user();
  }
}
# </sub print_output>

# <sub wait_for_user>
# wait for user reaction to continue
#
# usage:
#   wait_for_user()
#
#   => VOID CONTEXT
#
sub wait_for_user {
  print "[press key to continue]";
  print "\n" if <STDIN>;
}
# </sub wait_for_user>

# <sub parse_command>
# prompt for user input
#
# usage:
#   parse_command($command_line)
#
#   command_line: command string
#
#   => VOID CONTEXT
#
sub parse_command {
  my $command_line = shift;
  my @commands = split(/\s*;\s*/ => $command_line);

  my $return = 0;

  foreach my $command (@commands) {
    my $msg = "command executed: '$command'";

    $command =~ s/^\.//;
    $command =~ s/^(\w+)["']*/$1/;
    $command =~ s/\s*$//;

    if    ($command =~ /^(h|\?|help)$/) {
      print "$HELP_INTERACTIVE\n";

      # wait for user reaction to continue
      wait_for_user();

      next;
    }
    elsif ($command =~ /^(q|quit)$/) {
      return undef;
    }
    elsif ($command =~ /^(\.)$/) {
      $return = '';

      next;
    }
    elsif ($command =~ /^(\..|t|top)$/) {
      $return = '-1';

      next;
    }
    elsif ($command =~ /^(n|show-version)(?:\s+["']*(0|1|-1)["']*)?$/) {
      $ARG{'version'} = $2
        if defined $2;

      $msg = "'version' " . (defined $2 ? '' : 'is currently ') . "set to: '$ARG{'version'}'";
    }
    elsif ($command =~ /^(s|short)$/) {
      $ARG{'short'} = ! $ARG{'short'};

      $msg = "'short' output " . ($ARG{'short'} ? 'en' : 'dis') . "abled";
    }
    elsif ($command =~ /^(p|paged)$/) {
      $ARG{'pager'} = get_pager();
      $ARG{'paged'} = ! $ARG{'paged'}
        if -x $ARG{'pager'};

      $msg = "'paged' output " . ($ARG{'paged'} ? 'en' : 'dis') . "abled";
    }
    elsif ($command =~ /^(pager)(?:\s+["']*(\w+)["']*)?$/) {
      $ARG{'pager'} = get_pager($2)
        if defined $2;

      $msg = "'pager' " . (defined $2 ? '' : 'is currently ') . "set to: '$ARG{'pager'}'";
    }
    elsif ($command =~ /^(p|paged-)?(r|read)(?:\s+(["']?.+["']?))?$/) {
      my $paged = $1 || '';
      my $file  = $3 || $CURRENT_FILE;
      $CURRENT_FILE = $file;

      if (-r $file) {
        open(FILE, "< $file")
          or die "can't open file '$file': $!\n";

        my @lines = <FILE>;

        close FILE;

        my $previous_paged = $ARG{'paged'};
        $ARG{'paged'}      = 1 if $paged;

        #print_output("$file:\n\n", @lines);
        print_output(@lines);

        $ARG{'paged'}      = $previous_paged;

        next;
      }

      $msg = "can't find file '$file'";
    }
    elsif ($command =~ /^(c|config)$/) {
      my $short = $ARG{'short'} ? 'enabled' : 'disabled';
      my $paged = $ARG{'paged'} ? 'enabled' : 'disabled';

      $msg = <<HERE_MSG;
current configuration for '$NAME - interactive browse mode':

'version':         $ARG{'version'}
'short' output:    $short
'paged' output:    $paged
'pager':           $ARG{'pager'}
current file:      $CURRENT_FILE
HERE_MSG
    }
    elsif (length $command) {
      $msg = "invalid command: .$command";
    }
    else {
      # probably the '.' command
      $return = 0;

      next;
    }

    print "% $msg\n";
  }

  return $return;
}
# </sub parse_command>

# <sub readhist>
# read history from histfile
#
# usage:
#   readhist();
#
#   => VOID CONTEXT
#
sub readhist {
  my $term = $TERM;

  if (-r $ARG{'histfile'}) {
    open(HIST, "< $ARG{'histfile'}")
      or die "can't open histfile '$ARG{'histfile'}': $!\n";

    while (<HIST>) {
      chomp;
      $term->AddHistory($_);
    }

    close HIST;

    warn "history restored from '$ARG{'histfile'}'\n"
      if $ARG{'verbose'};
  }
  else {
    warn "history could not be restored (maybe no/wrong history file specified)\n"
      if $ARG{'verbose'};
  }
}
# </sub readhist>

# <sub savehist>
# save history to histfile
#
# usage:
#   savehist();
#
#   => VOID CONTEXT
#
sub savehist {
  return unless length $ARG{'histfile'} && $ARG{'histsize'};

  my $term = $TERM;

  return unless length $term;

  if (-w $ARG{'histfile'} || (! -e $ARG{'histfile'} && -w dirname $ARG{'histfile'})) {
    my @history = $term->GetHistory;

    # drop (consecutive) duplicate entries
    my @unified  = ();
    my $previous = '';
    foreach my $element (@history) {
      push(@unified => $element)
        unless $element eq $previous;
      $previous = $element;
    }
    @history = @unified;

    # cut history to specified maximum number of entries
    splice(@history, 0, @history - $ARG{'histsize'})
      if @history > $ARG{'histsize'};

    open(HIST, "> $ARG{'histfile'}")
      or die "can't open history file '$ARG{'histfile'}' for writing: $!\n";

    {
    local $, = "\n";

    print HIST @history, "";
    }

    close HIST;

    warn "history written to '$ARG{'histfile'}'\n"
      if $ARG{'verbose'};
  }
  else {
    warn "history could not be written (maybe no history file specified, or history file not writable)\n"
      if $ARG{'verbose'};
  }
}
# </sub savehist>

# <sub get_pager>
# get pager executable
#
# usage:
#   $pager = get_pager([$candidate]);
#
#   canidate: candidate for pager executable (defaulting to $ARG{'pager'})
#
#   => pager: pager executable
#
sub get_pager {
  my $candidate = shift || $ARG{'pager'};

  return $candidate if -x $candidate;

  # get first pager executable in PATH
  foreach my $path (split(':' => $ENV{'PATH'})) {
    return catfile($path, $candidate) if -x catfile($path, $candidate);
  }

  # still no executable!
  warn "can't find pager '$candidate'! disabling 'paged' output\n";
  $ARG{'paged'} = 0;

  return '-1';
}
# </sub get_pager>
