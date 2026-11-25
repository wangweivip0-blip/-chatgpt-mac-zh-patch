#!/usr/bin/perl
use strict;use warnings;use utf8;use JSON::PP;
use FindBin qw($Bin);use lib $Bin;
use LanguageLayout qw(language_modules read_checked);
binmode STDOUT, ':encoding(UTF-8)';binmode STDERR, ':encoding(UTF-8)';
my($app)=@ARGV;my $state=eval {
 die "缺少应用路径\n" unless defined $app;
 open my $f,'<:raw',"$app/Contents/Resources/app.asar" or die "无法读取ASAR：$!\n";
 read($f,my $head,16)==16 or die "ASAR头不完整\n";my @n=unpack('V4',$head);
 die "未知ASAR结构\n" unless $n[0]==4 && $n[3]>0 && $n[3]<100_000_000 && $n[1]>=8 && $n[3]<=$n[1]-8;
 read($f,my $j,$n[3])==$n[3] or die "ASAR索引不完整\n";my $idx=decode_json($j);
 my($patched,$original)=(0,0);
 for my $module(language_modules($idx,$f,8+$n[1])) {
  my $name=$module->{name};my $data=read_checked($f,8+$n[1],$module->{entry},"webview/assets/$name");
  print "检查界面模块：$name（文件与分块摘要通过）\n";
  $patched+=()=$data=~/!0\/\*offline-zh\*\//g;
  $original+=()=$data=~/\?\.get\((["`])enable_i18n\1,!1\)/g;
 }
 print "已知补丁标记数：$patched；原始语言开关数：$original\n";
 $patched==1 && $original==0 ? 0 : $patched==0 && $original==1 ? 1 : 2;
};
if($@){print STDERR $@;exit 2;}exit $state;
