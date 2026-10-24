#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use JSON::PP;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use File::Copy qw(copy);
use POSIX qw(strftime);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
umask 0077;
my $mode = shift(@ARGV) // '--check';
die "用法：locale-tool.pl --check|--apply|--restore [应用.app路径]\n" unless $mode =~ /^--(?:check|apply|restore)$/;
my $app = shift @ARGV;
if (!defined $app) { ($app) = grep {-d $_} ('/Applications/Codex.app', '/Applications/ChatGPT.app', "$ENV{HOME}/Applications/Codex.app", "$ENV{HOME}/Applications/ChatGPT.app"); }
my $home = $ENV{CODEX_HOME} // "$ENV{HOME}/.codex";
die "CODEX_HOME 必须为绝对路径。\n" unless File::Spec->file_name_is_absolute($home);
my $config = "$home/config.toml";
my $backup_root = "$home/macos-zh-inplace-config-backups";
sub read_bytes { my ($p)=@_; open my $h, '<:raw', $p or die "无法读取 $p：$!\n"; local $/; my $s=<$h>; close $h; return $s // ''; }
sub write_bytes { my ($p,$s)=@_; open my $h, '>:raw', $p or die "无法写入 $p：$!\n"; print {$h} $s or die "写入失败：$!\n"; close $h or die "关闭失败：$!\n"; }
sub atomic_config { my ($s,$perm)=@_; my ($fh,$tmp)=tempfile('.locale-XXXXXX', DIR=>$home, UNLINK=>0); binmode $fh; print {$fh} $s or die "写入临时文件失败\n"; close $fh or die "关闭临时文件失败\n"; chmod($perm,$tmp) or die "权限设置失败\n"; rename($tmp,$config) or die "替换配置失败：$!\n"; }
sub stopped {
 system('/usr/bin/pgrep','-f','/Contents/MacOS/(Codex|ChatGPT)( |$)');
 my $status=$?;
 die "无法检查应用进程，请确认 pgrep 可用。\n" unless $status==0 || $status==256;
 die "请先用 Command-Q 完全退出 Codex / ChatGPT，再运行此操作。\n" if $status==0;
}
sub inspect_app {
 die "未找到应用。可在终端传入 .app 的完整路径。\n" unless defined($app) && -d $app;
 my $plist="$app/Contents/Info.plist";
 my @cmd=('/usr/libexec/PlistBuddy','-c','Print :CFBundleIdentifier',$plist);
 open my $ph,'-|',@cmd or die "无法检查应用标识\n"; my $id=<$ph>//''; close $ph; chomp $id;
 die "该应用并非 com.openai.codex，停止操作。\n" unless $id eq 'com.openai.codex';
 my $asar="$app/Contents/Resources/app.asar";
 open my $f,'<:raw',$asar or die "无法读取 app.asar；该版本布局可能不同。\n";
 read($f,my $h,16)==16 or die "ASAR 文件头不完整\n";
 my @n=unpack('V4',$h); die "ASAR 索引尺寸异常\n" if $n[3]>100_000_000 || $n[1]<8;
 read($f,my $json,$n[3])==$n[3] or die "ASAR 索引不完整\n";
 my $idx=decode_json($json); my $assets=$idx->{files}{webview}{files}{assets}{files}//{};
 my @cn=sort grep {/^zh-(?:CN|Hans)-.*\.js$/} keys %$assets;
 my $menu=$idx->{files}{'native-menu-locales'}{files}{'zh-CN.json'};
 die "缺少中文菜单或界面文件；本工具不能给该版本补齐资源。\n" unless $menu && @cn;
 print "应用：$app\n中文菜单：存在\n中文界面模块：".scalar(@cn)." 份\n配置：$config\n";
 close $f;
}
die "不支持符号链接形式的配置文件，请手动检查后操作。\n" if -l $config;
if ($mode eq '--restore') {
 stopped();
 my $dir=read_bytes("$backup_root/latest"); chomp $dir;
 die "备份路径异常\n" unless $dir =~ /^\Q$backup_root\E\/backup-[A-Za-z0-9_-]+$/ && -d $dir;
 die "配置在设置中文后已改变；为保留后续修改，不自动覆盖。请参考说明手动恢复语言项。\n" unless -f $config && read_bytes($config) eq read_bytes("$dir/after.toml");
 my $meta=decode_json(read_bytes("$dir/state.json"));
 if ($meta->{existed}) { atomic_config(read_bytes("$dir/before.toml"),$meta->{mode}); }
 else { unlink($config) or die "移除新增配置失败：$!\n"; }
 unlink("$backup_root/latest");
 print "已恢复运行工具前的配置。重新打开应用即可。\n";
 exit;
}
inspect_app();

my $before=-f $config ? read_bytes($config) : '';
# 仅处理常规 TOML 写法；复杂形式交由应用设置界面处理，避免误改。
die "配置含多行字符串，本工具保守停止；请在应用设置中改语言。\n" if $before =~ /(?:"""|''')/;
die "配置采用特殊 desktop 写法，请在应用设置中改语言。\n" if $before =~ /^\h*(?:["']desktop["']|desktop)\h*=/m || $before =~ /^\h*\[\h*["']desktop["']/m;
die "desktop 点分键含特殊空格，请通过应用设置修改语言。\n" if $before =~ /^\h*desktop(?:\h+\.|\.\h+)/m;
my @lines=split(/\n/,$before,-1); my $section=''; my @sections; my @keys; my $section_count=0;
for my $i (0..$#lines) {
 my $l=$lines[$i];
 if ($l =~ /^\h*\[([^\]\r]+)\]\h*(?:#.*)?\r?$/) { $section=$1; $section =~ s/^\s+|\s+$//g; push @sections,[$i,$section]; $section_count++ if $section eq 'desktop'; }
 elsif ($l =~ /^\h*\[/) { die "配置含复杂表定义，请在应用设置中改语言。\n"; }
 if (($section eq 'desktop' && $l =~ /^\h*(?:localeOverride|"localeOverride"|'localeOverride')\h*=/) || ($section eq '' && $l =~ /^\h*desktop\.localeOverride\h*=/)) { push @keys,$i; }
 elsif ($l !~ /^\h*#/ && $l =~ /(?:["']desktop["']\s*\.|desktop\s*\.\s*["']localeOverride|\[desktop\.localeOverride\])/ ) { die "语言项采用特殊写法，请手动处理。\n"; }
}
die "发现重复的 desktop 段或语言项，请先修复配置。\n" if $section_count>1 || @keys>1;
if ($mode eq '--check' && @keys) {
 my $language_line=$lines[$keys[0]];
 if($language_line =~ /=\h*["']([A-Za-z0-9_-]{1,30})["']/){print "当前语言项：$1\n";}
 else{print "当前语言项不是简单字符串，未输出其内容。\n";}
}
if ($mode eq '--check') { print "检查通过。".(@keys ? "发现已有语言项（未输出其他配置）。" : "尚未找到语言项。")."\n检查不会修改任何文件。\n"; exit; }
stopped();
my $after;
if (@keys) { my $i=$keys[0]; my $prefix=$lines[$i] =~ /^\h*desktop\./ ? 'desktop.localeOverride' : 'localeOverride'; $lines[$i]="$prefix = \"zh-CN\""; $after=join("\n",@lines); }
elsif ($section_count) { my ($start)=map {$_->[0]} grep {$_->[1] eq 'desktop'} @sections; splice @lines,$start+1,0,'localeOverride = "zh-CN"'; $after=join("\n",@lines); }
elsif ($before =~ /^\h*desktop\h*\./m) { my $at=@sections ? $sections[0][0] : scalar(@lines); splice @lines,$at,0,'desktop.localeOverride = "zh-CN"'; $after=join("\n",@lines); }
else { $after=$before; $after.="\n" unless $after eq '' || $after =~ /\n\z/; $after.="\n[desktop]\nlocaleOverride = \"zh-CN\"\n"; }
if ($after eq $before) { print "已经设置为简体中文，无需修改。\n"; exit; }
make_path($home,{mode=>0700}) unless -d $home;
make_path($backup_root,{mode=>0700}) unless -d $backup_root;
my $dir="$backup_root/backup-".strftime('%Y%m%d-%H%M%S',localtime)."-$$"; make_path($dir,{mode=>0700});
my $existed=-f $config ? 1 : 0; my $perm=$existed ? ((stat($config))[2]&0777) : 0600;
write_bytes("$dir/before.toml",$before); write_bytes("$dir/after.toml",$after);
write_bytes("$dir/state.json",encode_json({existed=>$existed,mode=>$perm}));
die "配置被其他进程更改，已停止。\n" if (-f $config ? read_bytes($config) : '') ne $before;
atomic_config($after,$perm);
write_bytes("$backup_root/latest","$dir\n");
print "已设置 localeOverride = zh-CN。\n备份：$dir\n请重新打开应用，验证菜单与设置是否显示中文。\n";
