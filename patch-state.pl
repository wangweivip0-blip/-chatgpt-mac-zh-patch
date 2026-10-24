#!/usr/bin/perl
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
my($app)=@ARGV;exit 2 unless defined $app;
open my $f,'<:raw',"$app/Contents/Resources/app.asar" or exit 2;
read($f,my $h,16)==16 or exit 2;my @n=unpack('V4',$h);exit 2 unless $n[0]==4 && $n[3]>0 && $n[3]<100_000_000 && $n[1]>=8 && $n[3]<=$n[1]-8;
read($f,my $j,$n[3])==$n[3] or exit 2;my $d=eval {decode_json($j)};exit 2 unless $d;
my $files=$d->{files}{webview}{files}{assets}{files}//{};my($patched,$original)=(0,0);
for my $name(grep {/^(?:app-initial|initialize-app-host-services)-.*\.js$/} keys %$files){my $v=$files->{$name};next if $v->{unpacked} || $v->{size}>100_000_000;seek($f,8+$n[1]+$v->{offset},0) or exit 2;read($f,my $b,$v->{size})==$v->{size} or exit 2;my $ig=$v->{integrity};
if(!$ig || $ig->{algorithm} ne 'SHA256' || !$ig->{blockSize} || $ig->{blockSize}!~/^\d+$/ || sha256_hex($b) ne $ig->{hash}){print STDERR "界面模块摘要不匹配：$name\n";exit 2;}
my @blocks;
for(my $at=0;$at<length($b);$at+=$ig->{blockSize}){push @blocks,sha256_hex(substr($b,$at,$ig->{blockSize}));}
if(encode_json(\@blocks) ne encode_json($ig->{blocks})){print STDERR "界面模块分块摘要不匹配：$name\n";exit 2;}
print "检查界面模块：$name（文件与分块摘要通过）\n";$patched+=()=$b=~/!0\/\*offline-zh\*\//g;$original+=()=$b=~/\?\.get\(`enable_i18n`,!1\)/g;}
exit 0 if $patched==1 && $original==0;
exit 1 if $patched==0 && $original==1;
exit 2;
