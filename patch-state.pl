#!/usr/bin/perl
use strict;
use warnings;
use JSON::PP;
my($app)=@ARGV;exit 2 unless defined $app;
open my $f,'<:raw',"$app/Contents/Resources/app.asar" or exit 2;
read($f,my $h,16)==16 or exit 2;my @n=unpack('V4',$h);exit 2 unless $n[0]==4 && $n[3]>0 && $n[3]<100_000_000;
read($f,my $j,$n[3])==$n[3] or exit 2;my $d=eval {decode_json($j)};exit 2 unless $d;
my $files=$d->{files}{webview}{files}{assets}{files}//{};my($patched,$original)=(0,0);
for my $name(grep {/^app-initial-.*\.js$/} keys %$files){my $v=$files->{$name};next if $v->{unpacked} || $v->{size}>100_000_000;seek($f,8+$n[1]+$v->{offset},0) or exit 2;read($f,my $b,$v->{size})==$v->{size} or exit 2;$patched+=()=$b=~/!0\/\*offline-zh\*\//g;$original+=()=$b=~/\?\.get\(`enable_i18n`,!1\)/g;}
exit 0 if $patched==1 && $original==0;
exit 1 if $patched==0 && $original==1;
exit 2;
