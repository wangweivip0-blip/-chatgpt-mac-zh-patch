#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use JSON::PP;
use Digest::SHA qw(sha256_hex sha256);
use File::Basename qw(basename);
use Encode qw(encode_utf8);
use Cwd qw(abs_path);
use FindBin qw($Bin);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
my ($mode,$app,$backup)=@ARGV;
die "用法：patch-asar.pl --inspect|--patch 应用.app路径\n" unless defined($app) && $mode =~ /^--(?:inspect|patch)$/;
die "原位修改必须提供独立的完整应用备份路径。\n" if $mode eq '--patch' && (!defined($backup) || !-f "$backup/Contents/Resources/app.asar" || abs_path($backup) eq abs_path($app));
if ($mode eq '--patch') {
 die "必须先取得安装位置操作锁。\n" unless -d "$app.zh-repair.lock";
 for my $candidate ($backup,$app) {
  system($^X,"$Bin/verify-tree.pl",'--verify',$candidate,"$backup.manifest.json")==0 or die "原安装或完整备份校验失败，未修改。\n";
 }
}
my $asar="$app/Contents/Resources/app.asar";
open my $f,($mode eq '--patch'?'+<:raw':'<:raw'),$asar or die "无法打开 ASAR：$!\n";
read($f,my $head,16)==16 or die "ASAR 头不完整\n";
my @n=unpack('V4',$head);
die "不支持的 ASAR 头\n" unless $n[0]==4 && $n[3]>0 && $n[3]<100_000_000 && $n[1]>=8 && $n[3]<=$n[1]-8;
read($f,my $header,$n[3])==$n[3] or die "ASAR 索引不完整\n";
if ($mode eq '--patch') {
 open my $original,'<:raw',"$backup/Contents/Resources/app.asar" or die "无法读取备份索引\n";
 read($original,my $saved,16+$n[3])==16+$n[3] or die "备份索引不完整\n";
 close $original;
 die "备份与待修改应用不一致，停止。\n" unless $saved eq $head.$header;
}
my $idx=decode_json($header); my $base=8+$n[1];
my $assets=$idx->{files}{webview}{files}{assets}{files} // die "无已知界面资源目录\n";
my @locales=grep {/^zh-(?:CN|Hans)-.*\.js$/} keys %$assets;
die "目标应用没有内置简体中文资源，本工具不支持该版本。\n" unless @locales && $idx->{files}{'native-menu-locales'}{files}{'zh-CN.json'};
my @hits;
for my $name (sort grep {/^(?:app-initial|initialize-app-host-services)-.*\.js$/} keys %$assets) {
 my $entry=$assets->{$name}; die "不支持解包后的界面文件\n" if $entry->{unpacked};
 die "资源过大\n" if $entry->{size}>100_000_000;
 seek($f,$base+$entry->{offset},0) or die "定位资源失败\n";
 read($f,my $data,$entry->{size})==$entry->{size} or die "读取资源失败\n";
 while ($data =~ /([A-Za-z_\$][A-Za-z0-9_\$]*\?\.get\(`enable_i18n`,!1\))/g) {
  my $at=$-[0]; my $old=$1; my $context=substr($data,$at>700?$at-700:0,1500);
  die "找到开关但上下文不匹配，停止。\n" unless $context =~ /localeOverride/ && $context =~ /locale_source/;
  push @hits,{name=>$name,entry=>$entry,data=>$data,at=>$at,old=>$old};
 }
}
die "未找到唯一受支持的语言开关（可能已修复或版本不兼容），未修改。\n" unless @hits==1;
my $hit=$hits[0];my $v=$hit->{entry};my $data=$hit->{data};my $integrity=$v->{integrity};
die "缺少支持的 SHA256 校验信息\n" unless $integrity && $integrity->{algorithm} eq 'SHA256' && $integrity->{blockSize}>0;
die "源界面文件 SHA256 不匹配，停止。\n" unless sha256_hex($data) eq $integrity->{hash};
my $bs=$integrity->{blockSize}; my @oldblocks;
for(my $pos=0;$pos<length($data);$pos+=$bs){push @oldblocks,sha256_hex(substr($data,$pos,$bs));}
die "源分块校验不匹配\n" unless encode_json(\@oldblocks) eq encode_json($integrity->{blocks});
print "已识别中文资源与语言加载开关。\n目标模块：webview/assets/$hit->{name}\n";

my $replacement='!0/*offline-zh*/';
die "替换式超出原长度\n" if length($replacement)>length($hit->{old});
$replacement.=' ' x (length($hit->{old})-length($replacement));
my $patched=$data;substr($patched,$hit->{at},length($hit->{old}),$replacement);
die "资源长度发生变化\n" unless length($patched)==length($data);
my $newhash=sha256_hex($patched);my @newblocks;
for(my $pos=0;$pos<length($patched);$pos+=$bs){push @newblocks,sha256_hex(substr($patched,$pos,$bs));}
my %changes=($integrity->{hash}=>$newhash);
for my $i(0..$#oldblocks){
 next if $oldblocks[$i] eq $newblocks[$i];
 die "共享摘要的新值冲突，停止。\n" if exists($changes{$oldblocks[$i]}) && $changes{$oldblocks[$i]} ne $newblocks[$i];
 $changes{$oldblocks[$i]}=$newblocks[$i];
} 
my $newheader=$header;
my @target_digests=($integrity->{hash},@oldblocks);
for my $old(keys %changes){
 next if $old eq $changes{$old};
 my $expected=grep {$_ eq $old} @target_digests;
 my $count=()=$newheader=~/\Q$old\E/g;
 die "摘要还被目标文件以外的索引项引用，停止。\n" unless $expected>0 && $count==$expected;
 $newheader=~s/\Q$old\E/$changes{$old}/g;
}
die "索引长度改变\n" unless length($newheader)==length($header);
my $checked=decode_json($newheader)->{files}{webview}{files}{assets}{files}{$hit->{name}}{integrity};
die "新校验索引不一致\n" unless $checked->{hash} eq $newhash && encode_json($checked->{blocks}) eq encode_json(\@newblocks);
# 同步 Electron 框架中的完整性字典摘要，保留完整性验证开启。
my $plist="$app/Contents/Info.plist";
open my $pl,'-|','/usr/bin/plutil','-extract','ElectronAsarIntegrity','json','-o','-',$plist or die "无法读取应用完整性字典\n";
my $pljson=do {local $/;<$pl>};close $pl or die "无法解析应用完整性字典\n";
my $dict=decode_json($pljson);
die "Info.plist 与 ASAR 头摘要不一致\n" unless $dict->{'Resources/app.asar'}{hash} eq sha256_hex($header) && $dict->{'Resources/app.asar'}{algorithm} eq 'SHA256';
my $digest_input=join('',map {$_.$dict->{$_}{algorithm}.$dict->{$_}{hash}} sort keys %$dict);
my $olddigest=sha256($digest_input);
$dict->{'Resources/app.asar'}{hash}=sha256_hex($newheader);
my $newdigest=sha256(join('',map {$_.$dict->{$_}{algorithm}.$dict->{$_}{hash}} sort keys %$dict));
my $frameworks="$app/Contents/Frameworks";
opendir my $dh,$frameworks or die "找不到框架目录\n";
my @framework_names=grep {/^(?:Codex|Electron) Framework\.framework$/} readdir($dh);closedir $dh;
die "未找到唯一受支持的 Electron 框架\n" unless @framework_names==1;
my $binary_name=$framework_names[0];$binary_name=~s/\.framework$//;
my $binary="$frameworks/$framework_names[0]/$binary_name";
open my $bf,'<:raw',$binary or die "无法读取框架二进制\n";
my $bytes=do {local $/;<$bf>};close $bf;
my $sentinel='AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A';my @slots;
while($bytes=~/\Q$sentinel\E/g){my $pos=$-[0];my ($used,$ver)=unpack('CC',substr($bytes,$pos+32,2));die "框架摘要格式未知\n" unless $used==1 && $ver==1;die "框架摘要与原完整性字典不匹配\n" unless substr($bytes,$pos+34,32) eq $olddigest;push @slots,$pos+34;}
die "框架摘要槽数量不支持\n" unless @slots>=1 && @slots<=2;
undef $bytes;
if($mode eq '--inspect'){print "框架摘要校验通过。可进行备份后的原位修复；此次仅检查。\n";exit;}

# 所有检查完成后才写入目标应用；不移动任何文件偏移。
seek($f,16,0) or die "索引定位失败\n";print {$f} $newheader or die "索引写入失败\n";
seek($f,$base+$v->{offset},0) or die "资源定位失败\n";print {$f} $patched or die "资源写入失败\n";
close $f or die "ASAR 关闭失败\n";
my $headerhash=sha256_hex($newheader);
my $rc=system('/usr/libexec/PlistBuddy','-c',"Set :ElectronAsarIntegrity:Resources/app.asar:hash $headerhash",$plist);
die "更新应用 ASAR 完整性失败；请弃用这个目标应用。\n" unless $rc==0;
open my $out,'+<:raw',$binary or die "无法更新目标应用框架摘要\n";
for my $slot(@slots){seek($out,$slot,0) or die "框架定位失败\n";print {$out} $newdigest or die "框架摘要写入失败\n";}
close $out or die "框架关闭失败\n";
print "已在目标应用中启用本地语言加载，更新文件、分块、ASAR 头和框架校验。\n";
