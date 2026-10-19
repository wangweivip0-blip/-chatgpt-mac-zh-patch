#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use File::Find;
use Cwd qw(abs_path);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
my ($root)=@ARGV;
die "需要指定完整 .app 目录\n" unless defined($root) && -d $root;
$root=abs_path($root);
die "仅支持 .app 安装包\n" unless $root =~ /\.app\z/ && -f "$root/Contents/Info.plist";
my %blocked=map {$_=>1} ('com.apple.FinderInfo','com.apple.ResourceFork');
my($removed,$visited)=(0,0);
find({no_chdir=>1,follow=>0,wanted=>sub {
 my $path=$File::Find::name;
 return if -l $path; # 不跟随符号链接，防止改动安装包外部的目标。
 return unless -f $path || -d $path;
 $visited++;
 open my $list,'-|','/usr/bin/xattr',$path or die "无法读取扩展属性\n";
 my @attrs=<$list>;close $list or die "扩展属性读取失败；停止签名准备。\n";
 for my $attr(@attrs){
  $attr =~ s/[\r\n]+\z//;
  next unless $blocked{$attr};
  system('/usr/bin/xattr','-d',$attr,$path)==0 or die "清理签名冲突元数据失败。\n";
  $removed++;
 }
}},$root);
print "签名准备完成：检查 $visited 个文件/目录，仅移除 $removed 项 FinderInfo/ResourceFork 元数据。\n";
print "其他扩展属性（包括隔离属性）未主动移除。\n";
