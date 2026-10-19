#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use File::Find;
use JSON::PP;
use Digest::SHA;
use Cwd qw(abs_path);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
my ($mode,$root,$manifest)=@ARGV;
die "用法：verify-tree.pl --record|--verify 应用目录 清单路径\n" unless defined($manifest) && $mode =~ /^--(?:record|verify)$/ && -d $root && !-l $root;
$root=abs_path($root);my %entries;
find({no_chdir=>1,follow=>0,wanted=>sub {
 my $p=$File::Find::name;return if $p eq $root;my $rel=substr($p,length($root)+1);
 my @st=lstat($p);die "无法读取文件属性\n" unless @st;
 my $record={mode=>sprintf('%04o',$st[2]&07777)};
 if(-l _){$record->{type}='link';$record->{target}=readlink($p);die "无法读取链接\n" unless defined $record->{target};}
 elsif(-d _){$record->{type}='dir';}
 elsif(-f _){$record->{type}='file';$record->{size}=$st[7];open my $f,'<:raw',$p or die "无法读取文件：$!\n";$record->{sha256}=Digest::SHA->new(256)->addfile($f)->hexdigest;close $f or die "关闭文件失败\n";}
 else{die "应用内含不支持的特殊文件\n";}
 $entries{$rel}=$record;
}},$root);
my $json=JSON::PP->new->canonical;
if($mode eq '--record'){
 die "清单已存在，停止覆盖\n" if -e $manifest || -l $manifest;
 open my $out,'>:raw',$manifest or die "无法保存清单\n";chmod 0600,$manifest;print {$out} $json->encode({schema=>1,entries=>\%entries}) or die "写入清单失败\n";close $out or die "关闭清单失败\n";
 print "已记录整包文件、权限和符号链接清单。\n";
}else{
 open my $in,'<:raw',$manifest or die "无法读取备份清单\n";local $/;my $saved=decode_json(<$in>);close $in;
 die "备份或应用内容、权限、文件列表已变化，停止操作。\n" unless $saved->{schema}==1 && $json->encode($saved->{entries}) eq $json->encode(\%entries);
 print "整包清单校验通过。\n";
}
