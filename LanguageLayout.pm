package LanguageLayout;
use strict;use warnings;use utf8;
use Exporter 'import';use Digest::SHA qw(sha256_hex);use JSON::PP;use Scalar::Util qw(refaddr);
our @EXPORT_OK=qw(language_modules locale_evidence read_checked lookup_entry);
my %cache;
sub lookup_entry {
 my($index,$path)=@_;my $node=$index;
 for my $part(split m{/},$path){return undef unless ref($node) eq 'HASH' && ref($node->{files}) eq 'HASH';$node=$node->{files}{$part};return undef unless defined $node;}
 return $node;
}
sub read_bytes {
 my($fh,$base,$entry,$label)=@_;
 die "资源大小或位置未知：$label\n" unless ref($entry) eq 'HASH' && !$entry->{unpacked} && !$entry->{link} && defined($entry->{size}) && $entry->{size}=~/^\d+$/ && $entry->{size}<=100_000_000 && defined($entry->{offset}) && $entry->{offset}=~/^\d+$/;
 seek($fh,$base+$entry->{offset},0) or die "无法定位：$label\n";
 read($fh,my $bytes,$entry->{size})==$entry->{size} or die "读取不完整：$label\n";
 return $bytes;
}
sub read_checked {
 my($fh,$base,$entry,$label)=@_;my $bytes=read_bytes(@_);
 my $ig=$entry->{integrity};die "文件摘要不匹配：$label\n" unless $ig && $ig->{algorithm} eq 'SHA256' && defined($ig->{blockSize}) && $ig->{blockSize}=~/^\d+$/ && $ig->{blockSize}>0 && sha256_hex($bytes) eq $ig->{hash};
 my @blocks;for(my $at=0;$at<length($bytes);$at+=$ig->{blockSize}){push @blocks,sha256_hex(substr($bytes,$at,$ig->{blockSize}));}
 die "分块摘要不匹配：$label\n" unless encode_json(\@blocks) eq encode_json($ig->{blocks});
 return $bytes;
}
sub discover {
 my($idx,$fh,$base)=@_;die "需要索引和只读扫描句柄\n" unless $fh && defined $base;
 my $key=refaddr($idx);return $cache{$key} if $cache{$key};
 my $assets=lookup_entry($idx,'webview/assets');die "缺少界面资源目录\n" unless $assets && ref($assets->{files}) eq 'HASH';
 my(@files,@modules,@registries,@legacy);my $visited=0;
 my $walk; $walk=sub {my($tree,$prefix,$depth)=@_;die "目录深度超限，未完成扫描\n" if $depth>24;
  for my $name(sort keys %$tree){die "索引条目超限，未完成扫描\n" if ++$visited>200000;die "资源路径异常\n" if $name=~m{[/\\]} || $name eq '.' || $name eq '..';
   my $entry=$tree->{$name};if($entry->{files}){$walk->($entry->{files},$prefix.$name.'/', $depth+1)}elsif($name=~/\.(?:js|mjs|cjs)$/){push @files,[$prefix.$name,$entry]}
  }
 };
 $walk->($assets->{files},'',0);undef $walk;
 die "没有可扫描的界面JS资源\n" unless @files;
 my $bytes=0;my $original=0;my $patched=0;
 for my $file(@files){my($name,$entry)=@$file;
  die "资源布局不受支持，不能完成扫描：$name\n" unless defined($entry->{size}) && $entry->{size}=~/^\d+$/;
  $bytes+=$entry->{size};die "扫描总量超过350MiB，未完成扫描\n" if $bytes>350*1024*1024;
  my $data=read_bytes($fh,$base,$entry,"webview/assets/$name");my $matches=0;
  while($data=~/([A-Za-z_\$][A-Za-z0-9_\$]*\?\.get\((["`])enable_i18n\2,!1\))|(!0\/\*offline-zh\*\/)/g){
   my $is_original=defined($1);my $at=$-[0];my $start=$at>700?$at-700:0;my $context=substr($data,$start,1500);
   die "发现额外或未知上下文语言开关：$name；停止猜测\n" unless $context=~/localeOverride/ && $context=~/locale_source/;
   $is_original ? $original++ : $patched++;$matches++;
  }
  if($matches){read_checked($fh,$base,$entry,"webview/assets/$name");push @modules,{name=>$name,entry=>$entry};}
  # A registry proves registration, not that all dynamically imported translations exist.
  if($data=~/(["`])zh-CN\1\s*:\s*(["`])zh-Hans\2/ && $data=~/Object\.entries\(/ && $data=~/normalized/ && $data=~/load\s*:/ && index($data,'.json')>=0){
   read_checked($fh,$base,$entry,"webview/assets/$name");push @registries,$name;
  }
  if($name=~m{(?:^|/)zh-(?:CN|Hans)-[^/]+\.js$}){read_checked($fh,$base,$entry,"webview/assets/$name");push @legacy,$name;}
 }
 die "语言开关数量不唯一（原始$original，补丁$patched），未修改\n" unless @modules==1 && $original+$patched==1;
 my $result={modules=>\@modules,registries=>\@registries,legacy=>\@legacy,scanned=>scalar(@files),bytes=>$bytes};
 $cache{$key}=$result;return $result;
}
sub language_modules {my $result=discover(@_);return @{$result->{modules}};}
sub locale_evidence {
 my($index,$fh,$base)=@_;
 my $menu=lookup_entry($index,'native-menu-locales/zh-CN.json');die "缺少简体中文菜单\n" unless $menu;
 my $result=discover(@_);my $prefix='自动扫描'.$result->{scanned}.'个JS资源；';
 return $prefix.'发现旧版内置简体中文模块：'.join(', ',@{$result->{legacy}}) if @{$result->{legacy}};
 return $prefix.'发现简体中文注册表：'.join(', ',@{$result->{registries}}).'；翻译仍由原加载器加载，离线完整性待实机确认' if @{$result->{registries}};
 die "没有确认到内置中文模块或简体中文注册表；不会联网下载或凭空补齐翻译。\n";
}
1;
