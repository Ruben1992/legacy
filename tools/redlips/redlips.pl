#!/usr/bin/perl
# vim:tw=82:ts=2

# redlips.pl - red live intrusion prevention system
# -------------------------------------------------
# redlips.pl is a frontend for viewing and modifying packets
# in real time. It suits best as a layer 7 filter in capture
# the flag style linux deathmatchs.
#
# Features
# --------
# modification of tcp and udp packets with perl regular expressions
# colorized sniffing
#
#

# License
# -------
# Copyright (C) 2006 Felix Groebert <redlips@baraddur.de>
# version 0.1
# Homepage: https://roulette.das-labor.org/svn/tools/redlips/redlips.pl
# Download: https://roulette.das-labor.org/svn/tools/redlips/redlips.pl
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# Security Warning
# ----------------
# Due to an eval of user-defined perl code (regular expressions) the user can
# execute system() calls. Do not setuid this script and do not screen it away
# for everyone to attach.
#
# Bugs
# ----
# Please send bug reports to <redlips@baraddur.de>.
#
# FAQ
# ---
# Q: Whats wrong "Failed to send netlink message: Connection refused"?
# A: modprobe ip_queue
#
# Requirements
# ------------
# Linux kernel with CONFIG_IP_NF_QUEUE
# iptables
# IPTables::IPv4::IPQueue 1.25
# NetPacket::IP
# Net::RawSock http://www.hsc.fr/ressources/outils/rawsock/index.html.enk
# Term::ShellUI (maybe also Term::ReadLine::Gnu)
#
# Contributors
# ------------
# Felix Groebert <redlips@baraddur.de>
# Dennis
# Joern
# Tim
#
# Usage
# -----
# sudo perl redlips.pl
#   type "help" to get a list of commands
#   if you need to kill it, kill with -9 or ctrl-c
#
# Debug Level Categories
# ----------------------
# 1 ui
# 2 ip_queue
# 3 redlips process
# 4 packet manipulation
# 5 packet info
# 6 rules
# 7 reserved
# 8 reserved
# 9 reserved
#
#
# ChangeLog
# ---------
# 0.1
#   - initial release
#
#
# Urgent Todo
# -----------
#
#
# Todo
# ----
# better dump_ascii (indent \n, check for binary proto)
# internal tcp proxy
# acronym for red
# no more eval, lex?
# nfnetlink_queue (passemble instead of pinject, no dependency on rawsock)
# oo
# manage iptables rules with IPTables::IPv4
#   -> no duplicate --jump QUEUE
#   mark modules
#   mark modified packets (with iptables / evil bit)
#   working traffic when app not running!
# ipv6
# shellui: need closing quote (atp 1234 s/a'sdf/asdf/)
# *** glibc detected *** double free or corruption (!prev): 0x086bde88 ***
#
#

#
# init
#
package redlips;
use strict;
use threads;
use threads::shared;

$^W = 1;

use IPTables::IPv4::IPQueue qw(:constants);
use NetPacket::IP;
use NetPacket::ICMP;
use NetPacket::UDP;
use NetPacket::TCP;
use Net::RawSock;
use IO::Handle;
use Term::ShellUI;
use constant TIMEOUT => 1_000_000 * 2;    # 2 seconds

#
# config
#

# general options
my %o = (
  do_iptables => 1,                       # alter iptables
  ipt_script  => "ipt",                   # run this script with {start|stop}
  mode        => "forward",               # local or forward
  ui          => "shell",                 # shell or curses
  debug_level => 9,
  logfile     => "lips.log",
  history     => "history",
  sstr => "\x00",  # substitution string for length modification in tcp  packets
  rule_splitter => "\x00\x01\x00",
);

# colors
my %c = (
  normal      => "\x1b\x5b" . "m",
  string      => "\x1b\x5b" . "33m",
  debug       => "\x1b\x5b" . "31m",
  src_ip      => "\x1b\x5b" . "35m",
  src_port    => "\x1b\x5b" . "36m",
  dest_ip     => "\x1b\x5b" . "35m",
  dest_port   => "\x1b\x5b" . "36m",
  mark        => "\x1b\x5b" . "37m:",
  unimportant => "\x1b\x5b" . "37m"
);

#
# init
#
my @r;
my $packet_counter = 0;
my $queue;

open( L, ">>" . $o{logfile} ) or die $!;    # appending logfile
autoflush L 1;
bug("----------------starting redlips----------------",3);

$SIG{'INT'}  = \&signal_catcher;
$SIG{'KILL'} = \&signal_catcher;

ipt("start");

#
# rules
#
#radd("tcp any:any <> any:any s/felix/xilef/i");
#radd("tcp any:any <> any:any s/qwer/ytrewq/i");
#radd("tcp any:any <> any:any s/asdf/as/i");
#radd("tcp 127.0.0.1:any > any:111 s/felix/xilef/i");
#radd("tcp any:any <> any:any s/66666/ssssss/i");
#radd("tcp any:any <> any:any s/44444/vvvv/i");
#radd("tcp any:any > any:any s/foobar/barfoo/i");
#radd("tcp any:any <> any:any s/asdf/qwerty/i");
#radd("tcp any:any <> any:any s/\\d/Z/gi");
#radd("tcp any:any <> any:any s/asdf(as/df/i");    # invalid
#radd("udp any:any <> any:any s/AAAAA/BBBBBB/i");

#
# threads
#
my $packet_loop_flag : shared  = 1;
my $shared_rules : shared      = 0;
my $shared_rules_flag : shared = 0;

my $thread_ui      = threads->create( $o{ui} );
my $thread_packets = threads->create("packets");

$thread_ui->join();
$packet_loop_flag = 0;
$thread_packets->join();

ipt("stop");    # also check signal_catcher
print "exiting from shell command...\n";
bug( "exiting from shell command", 3 );
close L;
exit;

#
# ui
#
sub shell {
  my $term = new Term::ShellUI(
    commands => {
      "p"     => { syn => "print", },
      "print" => {
        desc    => "print current rules (short: p)",
        minargs => 0,
        maxargs => 0,
        proc    => sub {
          my $rule;
          my $i = 0;
          for $rule ( 0 .. $#r ) {
            print "[$i]\t"
              . $r[$rule][0] . " "
              . $r[$rule][1] . ":"
              . $r[$rule][2] . " "
              . $r[$rule][3] . " "
              . $r[$rule][4] . ":"
              . $r[$rule][5] . " "
              . $r[$rule][6] . "\n";
            $i++;
          }
          }
      },
      "atp"       => { syn => "addtoport", },
      "addtoport" => {
        desc => "add a rule beginning with \"tcp any:any > any:\" (short: atp)",
        minargs => 2,
        method  => sub {
          my $cmd = $_[1]{rawline};
          $cmd =~ s/^\w*\s(.*)$/$1/;
          radd("tcp any:any > any:$cmd");
          set_shared_rules();    # sync the threads
          }
      },
      "add" => {
        desc    => "add a rule",
        minargs => 5,
        method  => sub {
          my $cmd = $_[1]{rawline};
          $cmd =~ s/^\w*\s(.*)$/$1/;
          radd("$cmd");
          set_shared_rules();    # sync the threads
          }
      },
      "flush" => {
        desc    => "flush all rules",
        minargs => 0,
        maxargs => 0,
        proc    => sub {
          splice( @r, 0, $#r + 1 );
          set_shared_rules();    # sync the threads
          }
      },
      "del" => {
        desc    => "delete a rule",
        minargs => 1,
        maxargs => 1,
        proc    => sub {
          splice( @r, shift, 1 );
          set_shared_rules();    # sync the threads
          }
      },
      "save" => {
        desc    => "save current rules to a file",
        minargs => 1,
        maxargs => 1,
        proc    => sub {
          my $rule;
          open( F, ">" . shift ) or return;
          for $rule ( 0 .. $#r ) {
            print F $r[$rule][0] . " "
              . $r[$rule][1] . ":"
              . $r[$rule][2] . " "
              . $r[$rule][3] . " "
              . $r[$rule][4] . ":"
              . $r[$rule][5] . " "
              . $r[$rule][6] . "\n";
          }
          close F;
          }
      },
      "load" => {
        desc    => "add rules from a file",
        minargs => 1,
        maxargs => 1,
        proc    => sub {
          my $rule;
          open( F, "<" . shift ) or return;
          while (<F>) {
            radd($_);
          }
          close F;
          set_shared_rules();    # sync the threads
          }
      },
      "help" => {
        desc   => "print helpful information",
        args   => sub { shift->help_args( undef, @_ ); },
        method => sub { shift->help_call( undef, @_ ); }
      },
      "h" => {
        syn                     => "help",
        exclude_from_completion => 1
      },
      "quit" => {
        desc    => "Quit using redlips",
        minargs => 0,
        maxargs => 0,
        method  => sub { shift->exit_requested(1); },
      }
    },
    history_file                => $o{history},
    history_max                 => 10000,
    keep_quotes                 => 1,
    backslash_continues_command => 0,
  );
  bug( 'shellui: using ' . $term->{term}->ReadLine, 1 );
  $term->run();
  print "closing redlips shell...\n";
  return 0;
}

#
# main loop
#
sub packets {
  $queue = new IPTables::IPv4::IPQueue(
    copy_mode  => IPQ_COPY_PACKET,
    copy_range => 2048
    )
    or mydie( "init IPQueue", IPTables::IPv4::IPQueue->errstr );

  bug( "starting packet while loop", 2 );

  while ($packet_loop_flag) {
    my $msg = $queue->get_message(TIMEOUT);

    get_shared_rules();    # sync the threads

    if ( !defined $msg ) {
      next if IPTables::IPv4::IPQueue->errstr eq 'Timeout';
      bug( "iptables error: " . IPTables::IPv4::IPQueue->errstr, 2 );
      mydie( "get_message", IPTables::IPv4::IPQueue->errstr );
    }

    if ( $msg->data_len() ) {    # skip empty packets
      phandle($msg);
    }
  }
  print "closing redlips packet loop...\n";
  return 0;
}

#
# rule subs
#
sub radd {
  my $string = shift;
  my $quiet  = shift;
  my $hash   = {};

  chomp($string);

  if (
    $string =~ m/
        (tcp|udp)\s #proto
        (any|\d+\.\d+\.\d+\.\d+): # ip1
        (any|\d+)\s #port1
        (\>|\<\>)\s #direction
        (any|\d+\.\d+\.\d+\.\d+): # ip2
        (any|\d+)\s #port2
        (.*$) #regex
        /x
    )
  {
    if ( validateregex($7) ) {    # everything is valid
      bug( "adding rule: $string", 6 ) unless $quiet;
      push @r, [ $1, $2, $3, $4, $5, $6, $7 ];
      return 1;
    }
    else {
      bug( "error adding rule: regex incorrect ($string)", 6 ) unless $quiet;
    }
  }
  else {
    bug( "error adding rule: network option incorrect ($string)", 6 )
      unless $quiet;
  }

  return 0;
}

#
# sharing rules
#
sub set_shared_rules {
  my ( $return, $rule );

  for $rule ( 0 .. $#r ) {
    $return .=
        $r[$rule][0] . " "
      . $r[$rule][1] . ":"
      . $r[$rule][2] . " "
      . $r[$rule][3] . " "
      . $r[$rule][4] . ":"
      . $r[$rule][5] . " "
      . $r[$rule][6]
      . $o{rule_splitter};
  }

  $shared_rules_flag = 1;
  $shared_rules      = $return;
}

sub get_shared_rules {
  my ( $rule, $string, $newrule );
  my $exists = 0;

  if ($shared_rules_flag) {
    splice( @r, 0, $#r + 1 );    #remove old rules

    if ( defined($shared_rules) ) {    #might be empty
      foreach ( split( /$o{rule_splitter}/, $shared_rules ) ) {
        $newrule = $_;
        $exists  = 0;

        for $rule ( 0 .. $#r ) {
          $string =
              $r[$rule][0] . " "
            . $r[$rule][1] . ":"
            . $r[$rule][2] . " "
            . $r[$rule][3] . " "
            . $r[$rule][4] . ":"
            . $r[$rule][5] . " "
            . $r[$rule][6];
          $exists = 1 if ( $newrule eq $rule );
        }

        radd( $newrule, 1 ) unless $exists;    # this is pure bloat
      }
    }
  }

  $shared_rules_flag = 0;
  $shared_rules      = 0;
}

#
# helper subs
#
sub ipt {
  my $command = shift;
  my $chain;

  if ( $o{mode} eq "forward" ) {
    $chain = "-t filter -I FORWARD 1";
  }
  elsif ( $o{mode} eq "local" ) {
    $chain = "-t filter -I INPUT 1";
  }

  if ( $o{do_iptables} == 1 ) {
    bug( "modifying iptables rules", 3 );

    if ( $o{ipt_script} ) {
      system( "/bin/bash " . $o{ipt_script} ." " . $command );
    } else {
      if ( $command eq "start" ) {
        system( "/usr/local/sbin/iptables " . $chain . " -j QUEUE" );
      }
      elsif ( $command eq "stop" ) {
        $chain =~ s/-I/-D/;
        system( "/usr/local/sbin/iptables " . $chain );
      }
    }
  }
  else {
    bug( "not modifying iptables rules", 3 );
  }
}

sub signal_catcher {
  print "caught signal...\n";

  ipt("stop");
  close L;
  print "exiting cleanly...\n";
  exit;
}

sub mydie {
  my ( $error, $errorstring ) = @_;
  bug( "dying ($error): $errorstring", 3 );
  print "dying ($error): $errorstring\n";

  close L;
  ipt("stop");
  print "exiting cleanly...\n";
  exit 1;
}

sub validateregex {

  # http://www.perlmonks.org/?node_id=359606
  my $test = shift;
  my ( $code, $simple, $quanti, $regexp );

  $code = qr/(?: (?:
      [^{}]                  # not a curly brackets
  |   \{ (??{ $code }) \}    # balanced curly brackets
  )* )/x;

  $simple = qr/(?:
      \\ [pP] \{ \w+ \}                                       # \p{Prop}
  |   \\.                                                     # escape
  |   \[ (?: \\. | [^\]] )+ \]                                # [range]
  |   \( \? \# [^)]+ \)                                       # (?#text)
  |   \( \? [imsx]* -? [imsx]* (?: : (??{ $regexp }) )? \)    # (?imsx-imsx)
  |   \( \? (?: [:=!>] | <[=!] ) (??{ $regexp }) \)           # (?=pattern)
  |   \( \? \?? \{ (??{ $code }) \} \)                        # (?{ code })
  |   \( \? \( (?: \d+ | \? [=!<] (??{ $regexp }) | \? \{ (??{ $code }) \} ) \)
          (??{ $regexp }) (?: \| (??{ $regexp }) )? \)        # (?(1)y|n)
  |   \( (??{ $regexp }) \)                                   # parenthesis
  |   [^\\|()\[\]*+?{}]                                       # single char
  )/x;

  $quanti = qr/(?:
      (?: $simple (?: [+*?] \?? | \{ \d+ (?: , \d* )? \} \?? )?
  )* )/x;

  $regexp = qr/(?:
      $quanti (?: \| $quanti )*
  )/x;

  if ( $test =~ /^$regexp$/ ) {
    return 1;
  }
  else {
    return 0;
  }
}

sub bug {
  my $info  = shift;
  my $level = shift;
  if ( $info and $level le $o{debug_level} ) {
    print L $c{debug};
    print L ltime() . "[$$][debug$level] $info";
    print L $c{normal} . "\n";
  }
}

sub ltime {
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
    localtime(time);
  return "["
    . sprintf( "%.2d", $hour ) . ":"
    . sprintf( "%.2d", $min ) . ":"
    . sprintf( "%.2d", $sec ) . "]";
}

sub pc {
  $packet_counter = ( $packet_counter + 1 ) % 99999999;
  return "[p" . sprintf( "%.8d", $packet_counter ) . "]";
}

sub getevilbit {
  my $raw = shift;
  return substr( unpack( "B*", $raw ), 48, 16 );
}

sub setevilbit {
  my $raw = shift;
  my $bin = unpack( "B*", $raw );
  my $bit = ( substr( $bin, 51, 1 ) + 1 ) % 2;
  substr( $bin, 51, 1, $bit );
  return pack( "B*", $bin );
}

#
# dumper subs
#

# take a binary string and dump it in ascii or ^s
sub dump_ascii {
  my $input = shift;
  my ( $i, $char );
  my $return = $c{string};

  for ( $i = 0 ; $i < length $input ; $i++ ) {
    $char = substr( $input, $i, 1 );
    if ( ord $char > 31 and ord $char < 127 ) {
      $return = $return . $char;
    }
    elsif ( ord $char == 9 ) {
      $return = $return . "\\t";
    }
    elsif ( ord $char == 10 ) {
      $return = $return . "\\n";
    }
    elsif ( ord $char == 13 ) {
      $return = $return . "\\r";
    }
    else {
      $return = $return . "\\x" . sprintf( "%.2x", ord $char );
    }
  }
  return $return;
}

# print the ip, tp and data
sub dump_itd {
  my ( $msg, $ip, $tp, $new_data ) = @_;
  my ( $layers, $proto );

  $layers .=
      $c{src_ip}
    . $ip->{src_ip}
    . $c{mark}
    . $c{src_port}
    . $tp->{src_port}
    . $c{normal} . " > "
    . $c{dest_ip}
    . $ip->{dest_ip}
    . $c{mark}
    . $c{dest_port}
    . $tp->{dest_port} . " ";

  if ($new_data) {
    print L ltime()
      . pc()
      . "[mod] "
      . $layers
      . dump_ascii($new_data)
      . $c{normal} . "\n";
  }
  else {
    $proto = "[udp] " if ( $ip->{proto} == 58 );
    $proto = "[tcp] " if ( $ip->{proto} == 6 );
    print L ltime()
      . pc()
      . $proto
      . $layers
      . dump_ascii( $tp->{data} )
      . $c{normal} . "\n";
  }
}

#
# packet handling
#
sub pdrop {
  my $msg = shift;
  bug( "dropped " . $msg->packet_id, 5 );
  $queue->set_verdict( $msg->packet_id, NF_DROP );
}

sub paccept {
  my $msg = shift;
  bug( "acceptd " . $msg->packet_id, 5 );
  $queue->set_verdict( $msg->packet_id, NF_ACCEPT );
}

sub pinject {
  my ( $msg, $ip, $tp, $data ) = @_;
  my $raw;
  my $diff;
  my $nl;

  # watch out for tcp length manipulations and correct them
  if ( length($data) != length( $tp->{data} ) ) {
    bug(
      "found length modification (new "
        . length($data)
        . " vs orig "
        . length( $tp->{data} ) . ")",
      4
    );

    $nl = ( substr( $data, length($data) - 1, 1 ) eq "\n" ) ? 1 : 0;

    if ( length $data > length $tp->{data} ) {
      $diff = length($data) - length( $tp->{data} );
      substr( $data, length($data) - $diff - $nl, $diff, "" );
    }
    elsif ( length $data < length $tp->{data} ) {
      $diff = length( $tp->{data} ) - length($data);
      substr( $data, length($data) - 1 - $nl,
        1, ( substr( $data, length($data) - 1 - $nl, 1 ) . $o{sstr} x $diff ) );
    }
  }

  # construct the new packet
  $tp->{data} = $data;
  $ip->{data} = $tp->NetPacket::TCP::encode($ip) if ( $ip->{proto} == 6 );
  $ip->{data} = $tp->NetPacket::UDP::encode($ip) if ( $ip->{proto} == 58 );
  $raw        = $ip->encode;

  # print the modifications
  dump_itd( $msg, $ip, $tp, $data );

  # drop the original packet
  $queue->set_verdict( $msg->packet_id, NF_DROP );

  # and inject the raw copy
  bug( "injecting packet", 5 );

  #Net::RawSock::write_ip(setevilbit($raw));
  Net::RawSock::write_ip( ($raw) );
}

sub passemble {
  my ( $msg, $ip, $tp, $data ) = @_;
  my $raw;

  $tp->{data} = $data;
  $ip->{data} = $tp->NetPacket::TCP::encode($ip) if ( $ip->{proto} == 6 );
  $ip->{data} = $tp->NetPacket::UDP::encode($ip) if ( $ip->{proto} == 58 );
  $raw        = $ip->encode;

  dump_itd( $msg, $ip, $tp, $data );

  $queue->set_verdict( $msg->packet_id, NF_ACCEPT, length($raw), $raw );
}

sub phandle {
  my $msg = shift;
  my ( $rule_string, $rule, $data );
  my $ip = NetPacket::IP->decode( $msg->payload() );
  my $return;    # helper
  my $tp;        # transport layer object
  my $modified = 0;    # determines whether this packet was modified

  bug(
    "recieved "
      . $msg->data_len
      . " byte packet "
      . $msg->packet_id
      . " on device "
      . $msg->indev_name . "/"
      . $msg->outdev_name
      . " with hook "
      . $msg->hook
      . " and ip layer "
      . $ip->{src_ip} . " > "
      . $ip->{dest_ip},
    5
  );

  #bug(
  #      "get evil bit debug: "
  #    . getevilbit( $msg->payload() ) . " "
  #    . $ip->{flags} . "
  #" . $ip->{foffset}, 1
  #);

  # generate transport $tp object and print the contents
  #
  if ( $ip->{proto} == 58 ) {    # udp
    $tp = NetPacket::UDP->decode( $ip->{data} );
    if ( $tp->{data} ) {
      $data = $tp->{data};
      dump_itd( $msg, $ip, $tp );
    }
    else {
      bug( "skipping empty packet", 5 );
      paccept($msg);             # skipt empty packets
      return;
    }
  }
  elsif ( $ip->{proto} == 6 ) {    # tcp
    $tp = NetPacket::TCP->decode( $ip->{data} );
    if ( $tp->{data} ) {
      $data = $tp->{data};
      dump_itd( $msg, $ip, $tp );
    }
    else {
      bug( "skipping empty tcp packet", 5 );
      paccept($msg);
      return;
    }
  }
  else {
    bug( "skipping non tcp, non udp packet (proto " . $ip->{proto} . ")", 5 );
    paccept($msg);
    return;
  }

  # walk through rules
  #
  for $rule ( 0 .. $#r ) {
    $rule_string = " ( rule: "
      . $r[$rule][0] . " "
      . $r[$rule][1] . ":"
      . $r[$rule][2] . " "
      . $r[$rule][3] . " "
      . $r[$rule][4] . ":"
      . $r[$rule][5] . " "
      . $r[$rule][6] . " ) ";

    # check for protocol
    #
    if ( ( $r[$rule][0] eq "tcp" and $ip->{proto} == 58 )
      or ( $r[$rule][0] eq "udp" and $ip->{proto} == 6 ) )
    {
      bug( "skipping: wrong proto" . $rule_string, 6 );
      next;
    }

    # check for ip layer dest/src
    #
    unless (
      (
        $r[$rule][3] eq '<>'
        and (
          (
                ( $r[$rule][1] eq $ip->{src_ip}  or $r[$rule][1] eq "any" )
            and ( $r[$rule][4] eq $ip->{dest_ip} or $r[$rule][4] eq "any" )
          )
          or (  ( $r[$rule][4] eq $ip->{src_ip} or $r[$rule][4] eq "any" )
            and ( $r[$rule][1] eq $ip->{dest_ip} or $r[$rule][1] eq "any" ) )
        )
      )
      or (
        $r[$rule][3] eq '>'
        and ( ( $r[$rule][1] eq $ip->{src_ip} or $r[$rule][1] eq "any" )
          and ( $r[$rule][4] eq $ip->{dest_ip} or $r[$rule][4] eq "any" ) )
      )
      )
    {
      bug( "skipping: wrong network layer" . $rule_string, 6 );
      next;
    }

    # check for tp layer dest/src
    #
    unless (
      (
        $r[$rule][3] eq '<>'

        and (
          (
                ( $r[$rule][2] eq $tp->{src_port}  or $r[$rule][2] eq "any" )
            and ( $r[$rule][5] eq $tp->{dest_port} or $r[$rule][5] eq "any" )
          )
          or (  ( $r[$rule][5] eq $tp->{src_port} or $r[$rule][5] eq "any" )
            and ( $r[$rule][2] eq $tp->{dest_port} or $r[$rule][2] eq "any" ) )
        )
      )
      or (
        $r[$rule][3] eq '>'
        and ( ( $r[$rule][2] eq $tp->{src_port} or $r[$rule][2] eq "any" )
          and ( $r[$rule][5] eq $tp->{dest_port} or $r[$rule][5] eq "any" ) )
      )
      )
    {
      bug( "skipping: wrong transport layer" . $rule_string, 6 );
      next;
    }

    # network options match, now apply the regex
    $return = eval "\$data =~ $r[$rule][6]";

    if ( length $@ ) {
      bug( "skipping: error in eval $@" . $rule_string, 6 );
      next;
    }
    elsif ( $return gt 0 ) {
      bug( "rule applied successfully" . $rule_string, 6 );
      $modified = 1;
    }
    else {
      bug( "skipping: substitution not matching" . $rule_string, 6 );
      next;
    }
  }

  if ( $modified == 1 ) {
    pinject( $msg, $ip, $tp, $data );    # reassemble modified packet
  }
  else {
    paccept($msg);                       # accept non-modified packages
  }
}

#eof
