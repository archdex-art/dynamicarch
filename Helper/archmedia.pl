#!/usr/bin/perl
# DynamicArch media bridge loader.
#
# macOS 15.4 restricted MediaRemote.framework to Apple platform binaries and
# processes holding com.apple.mediaremote.* entitlements, which no third-party
# app can obtain. /usr/bin/perl *is* a platform binary, so loading our bridge
# into perl and calling MediaRemote from there is allowed by the OS while
# keeping every line of the logic ours.
#
# Usage: /usr/bin/perl archmedia.pl /path/to/ArchMediaBridge.dylib serve|get

use strict;
use warnings;
use DynaLoader;

my $lib = shift @ARGV or die "usage: archmedia.pl <bridge.dylib> <serve|get>\n";
my $fn  = shift @ARGV // 'serve';
die "unknown entry point: $fn\n" unless $fn =~ /^(serve|get)$/;

my $handle = DynaLoader::dl_load_file($lib, 0)
  or die "failed to load bridge: $lib\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "arch_media_$fn")
  or die "bridge is missing arch_media_$fn\n";

DynaLoader::dl_install_xsub("main::entry", $symbol);
entry();
