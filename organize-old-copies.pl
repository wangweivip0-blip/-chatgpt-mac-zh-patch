#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8 decode_utf8);
sub display { my($s)=@_;return eval {decode_utf8($s,1)} // $s; }
use File::Path qw(make_path);
use File::Basename qw(basename dirname);
use File::Spec;
use Cwd qw(abs_path);
use POSIX qw(strftime);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
my ($mode,$tool_parent,$history,@roots)=@ARGV;
die "用法：organize-old-copies.pl --preview|--apply 工具父目录 历史目录 应用目录...\n" unless defined($history) && $mode =~ /^--(?:preview|apply)$/;
die "历史目录必须以 .noindex 结尾\n" unless $history =~ /\.noindex\z/;
my $apply=$mode eq '--apply';
my $lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister';
sub registry {
 my($flag,$p)=@_;
 return unless $apply && -x $lsregister && !$ENV{CHATGPT_ZH_TEST};
 my @prefix;
 if($>==0){
  my $uid=$ENV{CODEX_ZH_ORIGINAL_UID}//'';
  die "缺少原用户信息，停止登记变更\n" unless $uid =~ /^\d+$/ && $uid>0;
  @prefix=('/usr/bin/sudo','-u',"#$uid",'/usr/bin/env','HOME='.($ENV{CODEX_ZH_ORIGINAL_HOME}//$ENV{HOME}));
 }
 system(@prefix,$lsregister,$flag,$p)==0 or print "提示：图标登记更新未完成，文件仍保留。\n";
}
sub is_codex {
 my($app)=@_;return 0 if -l $app || !-f "$app/Contents/Info.plist";
 open my $f,'-|','/usr/libexec/PlistBuddy','-c','Print :CFBundleIdentifier',"$app/Contents/Info.plist" or return 0;
 my $id=<$f>//'';close $f;chomp $id;return $id eq 'com.openai.codex';
}
my @extras;my @backups;
for my $root(@roots){
 next unless -d $root && !-l $root;
 opendir my $d,$root or die "无法读取应用目录\n";
 for my $name(readdir $d){
  next unless $name =~ /^(?:ChatGPT|Codex)\.app\.zh-(?:before-restore|restore)-\d+$/ || $name eq encode_utf8('Codex-离线中文.app');
  my $p="$root/$name";push @extras,$p if is_codex($p);
 }closedir $d;
}
if(-d $tool_parent){
 opendir my $d,$tool_parent or die "无法读取工具目录\n";
 for my $name(readdir $d){
  next unless $name =~ /^(?:Codex|ChatGPT)-macOS-/;
  my $tool="$tool_parent/$name";next if -l $tool || !-d $tool;
  opendir my $b,$tool or next;
  for my $part(readdir $b){
   next unless $part =~ /^\Q@{[encode_utf8('备份-')]}\E\d{8}-\d{6}-\d+$/;
   my $dir="$tool/$part";next if -l $dir || !-d $dir;
   my @apps=grep {is_codex($_)} ("$dir/ChatGPT.app","$dir/Codex.app");
   push @backups,[$tool,$dir,\@apps] if @apps;
  }closedir $b;
  my $oldcopy="$tool/".encode_utf8('Codex-离线中文.app');push @extras,$oldcopy if is_codex($oldcopy);
 }closedir $d;
}
print "已知旧恢复文件/副本：".scalar(@extras)."；待整理备份目录：".scalar(@backups)."\n";
for my $p(@extras){print "移入历史备份：".display($p)."\n";}
for my $b(@backups){print "备份目录改为不索引形式：".display($b->[1])."\n";}
exit unless $apply;
if(@extras){
 make_path($history,{mode=>0700}) unless -d $history;
 if($>==0){
  my $uid=$ENV{CODEX_ZH_ORIGINAL_UID}//'';my $gid=$ENV{CODEX_ZH_ORIGINAL_GID}//'';
  die "缺少原用户信息\n" unless $uid =~ /^\d+$/ && $uid>0 && $gid =~ /^\d+$/;
  chown($uid,$gid,$history,dirname($history)) or die "历史目录权限设置失败\n";
 }
 for my $p(@extras){
  my $dest="$history/".basename($p).'-'.strftime('%Y%m%d-%H%M%S',localtime)."-$$.bundle";
  die "目标已存在，停止覆盖\n" if -e $dest;
  # 必须先保留文件，再取消旧路径的图标登记。移动失败不会丢失旧登记。
  registry('-u',$p);
  if(system('/bin/mv',$p,$dest)!=0){registry('-f',$p);die "移动旧副本失败，原文件仍应保留，请查看系统报错\n";}
  registry('-u',$dest);
 }
}
for my $b(@backups){
 my($tool,$dir,$apps)=@$b;my $new="$dir.noindex";
 die "整理后的目录已存在，停止覆盖\n" if -e $new;
 my $latest="$tool/latest-backup.txt";my $selected=0;
 if(-f $latest){open my $f,'<:raw',$latest or die "无法读取旧备份记录\n";local $/;my $s=<$f>//'';close $f;$s =~ s/[\r\n]+\z//;$selected=$s eq $dir;}
 # 重命名之前确认需要更新的记录可以写入，避免新旧路径脱节。
 die "备份记录不可写，请使用管理员入口\n" if $selected && !-w $latest;
 for my $p(@$apps){registry('-u',$p);}
 unless(rename($dir,$new)){for my $p(@$apps){registry('-f',$p);}die "无法整理备份目录：$!\n";}
 if($selected){
  my $tmp="$tool/.latest-backup-$$";
  my $ok=eval {
   open my $out,'>:raw',$tmp or die "无法写记录";
   print {$out} "$new\n" or die "记录写入失败";
   close $out or die "记录关闭失败";
   rename($tmp,$latest) or die "记录替换失败";
   1;
  };
  unless($ok){unlink($tmp) if -f $tmp;rename($new,$dir) or die "备份记录失败且无法撤销目录改名\n";die "备份记录更新失败，目录已恢复原名\n";}
 }
 for my $p(@$apps){registry('-u',$p);registry('-u',"$new/".basename($p));}
}
for my $root(@roots){my $main="$root/ChatGPT.app";registry('-f',$main) if is_codex($main);}
print "整理完成：原 ChatGPT.app 未移动，未修改其补丁和语言配置，历史副本仍保留。\n";
