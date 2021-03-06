# -*- perl -*-
#
# Copyright (C) 2008-2012 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

package AMC::Basic;

use Locale::gettext ':libintl_h';

use File::Temp;
use File::Spec;
use IO::File;
use Fcntl qw(:flock :seek);
use XML::Writer;
use XML::Simple;
use POSIX qw/strftime/;
use Encode;
use Module::Load;
use Module::Load::Conditional qw/check_install/;
use Glib;

use constant {
    COMBO_ID => 1,
    COMBO_TEXT => 0,
};

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    @ISA         = qw(Exporter);
    @EXPORT      = qw( &perl_module_search &amc_specdir &get_sty &file2id &id2idf &get_ep &get_epo &get_epc &get_qr &file_triable &sort_from_columns &sort_string &sort_num &attention &model_id_to_iter &commande_accessible &magick_module &magick_perl_module &debug &debug_and_stderr &debug_pm_version &set_debug &get_debug &debug_file &abs2proj &proj2abs &use_gettext &clear_old &new_filename &pack_args &unpack_args &__ &__p &translate_column_title &translate_id_name &pageids_string &studentids_string &format_date &cb_model &COMBO_ID &COMBO_TEXT &check_fonts &amc_user_confdir &use_amc_plugins &find_latex_file);
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

# ---------------------------------------------------
# for path guess with local installation

my $amc_base_path;

if($ENV{'AMCBASEDIR'}) {
    $amc_base_path=$ENV{'AMCBASEDIR'};
} else {
    $amc_base_path=__FILE__;
    $amc_base_path =~ s|/Basic\.pm$||;
    $amc_base_path =~ s|/AMC$||;
    $amc_base_path =~ s|/perl$||;
}

sub amc_adapt_path {
    my %oo=@_;
    my @p=();
    my $r='';
    push @p,$oo{'path'} if($oo{'path'});
    push @p,map { "$amc_base_path/$_" } (@{$oo{'locals'}}) if($oo{'locals'});
    push @p,@{$oo{'alt'}} if($oo{'alt'});
    if($oo{'file'}) {
      TFILE: for(@p) { if( -f "$_/$oo{'file'}" )
		       { $r="$_/$oo{'file'}";last TFILE; } }
    } else {
      TDIR: for(@p) { if( -d ) { $r=$_;last TDIR; } }
    }
    return $r;
}

# ---------------------------------------------------

%install_dirs=(
    'lib'=>"/usr/lib/AMC",
    'libexec'=>"/usr/lib/AMC/exec",
    'libperl'=>"/usr/lib/AMC/perl",
    'icons'=>"/usr/share/auto-multiple-choice/icons",
    'models'=>"/usr/share/auto-multiple-choice/models",
    'doc/auto-multiple-choice'=>"/usr/share/doc/auto-multiple-choice-doc",
    );

sub amc_specdir {
    my ($class)=@_;
    if($install_dirs{$class}) {
	return(amc_adapt_path(
		   'path'=>$install_dirs{$class},
		   'locals'=>[$class,'.'],
	       ));
    } else {
	die "Unknown class for amc_specdir: $class";
    }
}

sub perl_module_search {
  my ($prefix)=@_;
  $prefix =~ s/::/\//g;
  my %mods=();
  for my $r (@INC) {
    my $loc=$r.'/'.$prefix;
    if(-d $loc) {
      opendir(my $dh, $loc);
      for(grep { /\.pm$/i && -f "$loc/$_" } readdir($dh)) {
	s/\.pm$//i;
	$mods{$_}=1;
      }
      closedir $dh;
    }
  }
  return(sort { $a cmp $b } keys %mods);
}

# peut-on acceder a cette commande par exec ?
sub commande_accessible {
    my $c=shift;
    $c =~ s/(?<=[^\s])\s.*//;
    $c =~ s/^\s+//;
    if($c =~ /^\//) {
	return (-x $c);
    } else {
	$ok='';
	for (split(/:/,$ENV{'PATH'})) {
	    $ok=1 if(-x "$_/$c");
	}
	return($ok);
    }
}

my $gm_ok=commande_accessible('gm');

sub magick_module {
    my ($m)=@_;
    if($gm_ok) {
	return('gm',$m);
    } else {
	return($m);
    }
}

my $magick_pmodule='';

sub magick_perl_module {
    my ($dont_load_it)=@_;
    if(!$magick_pmodule) {
      TEST: for my $m (qw/Graphics::Magick Image::Magick/) {
	  if(check_install(module=>$m)) {
	      $magick_pmodule=$m;
	      last TEST;
	  }
      }
	if($magick_pmodule && !$dont_load_it) {
	    load($magick_pmodule);
	    debug_pm_version($magick_pmodule);
	}
    }
    return($magick_pmodule);
}

# gets style file location

sub get_sty {
    my @r=();
    open(WH,"-|","kpsewhich","-all","automultiplechoice.sty")
	or die "Can't exec kpsewhich: $!";
    while(<WH>) {
	chomp;
	push @r,$_;
    }
    close WH;
    return(@r);
}

sub file2id {
    my $f=shift;
    if($f =~ /^[a-z]*-?([0-9]+)-([0-9]+)-([0-9]+)/) {
	return(sprintf("+%d/%d/%d+",$1,$2,$3));
    } else {
	return($f);
    }
}

sub id2idf {
    my ($id,%oo)=@_;
    $id =~ s/[\+\/]+/-/g;
    $id =~ s/^-+//;
    $id =~ s/-+$//;
    $id =~ s/([0-9]+-[0-9]+)-.*/$1/ if($oo{'simple'});
    return($id);
}

sub get_qr {
    my $k=shift;
    if($k =~ /([0-9]+)\.([0-9]+)/) {
	return($1,$2);
    } else {
	die "Unparsable Q/A key: $k";
    }
}

sub get_epo {
    my $id=shift;
    if($id =~ /^\+?([0-9]+)\/([0-9]+)\/([0-9]+)\+?$/) {
        return($1,$2);
    } else {
        return();
    }
}

sub get_epc {
    my $id=shift;
    if($id =~ /^\+?([0-9]+)\/([0-9]+)\/([0-9]+)\+?$/) {
        return($1,$2,$3);
    } else {
        return();
    }
}

sub get_ep {
    my $id=shift;
    my @r=get_epo($id);
    if(@r) {
        return(@r);
    } else {
        die "Unparsable ID: $id";
    }
}

sub file_triable {
    my $f=shift;
    if($f =~ /^[a-z]*-?([0-9]+)-([0-9]+)-([0-9]+)/) {
	return(sprintf("%50d-%30d-%40d",$1,$2,$3));
    } else {
	return($f);
    }
}

sub sort_num {
    my ($liststore, $itera, $iterb, $sortkey) = @_;
    my $a = $liststore->get ($itera, $sortkey);
    my $b = $liststore->get ($iterb, $sortkey);
    $a='' if(!defined($a));
    $b='' if(!defined($b));
    my $para=$a =~ s/^\((.*)\)$/$1/;
    my $parb=$b =~ s/^\((.*)\)$/$1/;
    $a=0 if($a !~ /^-?[0-9.]+$/);
    $b=0 if($b !~ /^-?[0-9.]+$/);
    return($parb <=> $para || $a <=> $b);
}

sub sort_string {
    my ($liststore, $itera, $iterb, $sortkey) = @_;
    my $a = $liststore->get ($itera, $sortkey);
    my $b = $liststore->get ($iterb, $sortkey);
    $a='' if(!defined($a));
    $b='' if(!defined($b));
    return($a cmp $b);
}

sub sort_from_columns {
  my ($liststore, $itera, $iterb, $sortkeys) = @_;
  my $r=0;
 SK:for my $c (@$sortkeys) {
    my $a = $liststore->get ($itera, $c->{'col'});
    my $b = $liststore->get ($iterb, $c->{'col'});
    if($c->{'type'} =~ /^n/) {
      $a=0 if(!defined($a));
      $b=0 if(!defined($b));
      $r=$a <=> $b;
    } else {
      $a='' if(!defined($a));
      $b='' if(!defined($b));
      $r=$a cmp $b;
    }
    last SK if($r!=0);
  }
  return($r);
}

sub attention {
    my @l=();
    my $lm=0;
    for my $u (@_) { push  @l,split(/\n/,$u); }
    for my $u (@l) { $lm=length($u) if(length($u)>$lm); }
    print "\n";
    print "*" x ($lm+4)."\n";
    for my $u (@l) {
	print "* ".$u.(" " x ($lm-length($u)))." *\n";
    }
    print "*" x ($lm+4)."\n";
    print "\n";
}

sub bon_id {

    #print join(" --- ",@_),"\n";

    my ($l,$path,$iter,$data)=@_;

    my ($result,%constraints)=@$data;

    my $ok=1;
    for my $col (keys %constraints) {
      $ok=0 if($l->get($iter,$col) ne $constraints{$col})
    }

    if($ok) {
	$$result=$iter->copy;
	return(1);
    } else {
	return(0);
    }
}

sub model_id_to_iter {
    my ($cl,%constraints)=@_;
    my $result=undef;
    $cl->foreach(\&bon_id,[\$result,%constraints]);
    return($result);
}

# aide au debogage

my $amc_debug='';
my $amc_debug_fh='';
my $amc_debug_filename='';

sub set_debug_file {
    if(!$amc_debug_fh) {
	$amc_debug_fh = new File::Temp(TEMPLATE =>'AMC-DEBUG-XXXXXXXX',
				       SUFFIX => '.log',
				       UNLINK=>0,
				       DIR=>File::Spec->tmpdir);
	$amc_debug_filename=$amc_debug_fh->filename;
	$amc_debug_fh->autoflush(1);
	open(STDERR,">&",$amc_debug_fh);

 	# versions diverses...

	print $amc_debug_fh "This is AutoMultipleChoice, version 1.1.1 (svn:1104)\n";
	print $amc_debug_fh "Perl : $^X\n";

 	print $amc_debug_fh "\n".("=" x 40)."\n\n";
 	if(commande_accessible('convert')) {
 	    open(VERS,"-|",'convert','-version');
 	    while(<VERS>) { chomp; print $amc_debug_fh "$_\n"; }
 	    close(VERS);
 	} else {
 	    print $amc_debug_fh "ImageMagick: not found\n";
 	}

 	print $amc_debug_fh ("=" x 40)."\n\n";
 	if(commande_accessible('gm')) {
 	    open(VERS,"-|",'gm','-version');
 	    while(<VERS>) { chomp; print $amc_debug_fh "$_\n"; }
 	    close(VERS);
 	} else {
 	    print $amc_debug_fh "GraphicsMagick: not found\n";
 	}
 	print $amc_debug_fh ("=" x 40)."\n\n";

    }
}

sub debug_file {
    return($amc_debug ? $amc_debug_filename : '');
}

sub debug {
    my @s=@_;
    return if(!$amc_debug);
    for my $l (@s) {
	my @t = times();
	$l=sprintf("[%7d,%7.02f] ",$$,$t[0]+$t[1]+$t[2]+$t[3]).$l;
	$l=$l."\n" if($l !~ /\n$/);
	if($amc_debug_fh) {
	    flock($amc_debug_fh, LOCK_EX);
	    $amc_debug_fh->sync;
	    seek($amc_debug_fh, 0, SEEK_END);
	    print $amc_debug_fh $l;
	    flock($amc_debug_fh, LOCK_UN);
	} else {
	    print $l;
	}
    }
}

sub debug_and_stderr {
    my @s=@_;
    debug(@s);
    for(@s) {
	print STDERR "$_\n";
    }
}

sub debug_pm_version {
     my ($module)=@_;
     my $version;
     if (defined($version = $module->VERSION())) {
         debug "[VERSION] $module: $version";
     }
}

sub set_debug {
    my ($debug)=@_;
    if($debug =~ /\// && -f $debug) {
	# c'est un nom de fichier
	$amc_debug_fh=new IO::File;
	$amc_debug_fh->open($debug,">>");
	$amc_debug_fh->autoflush(1);
	$amc_debug_filename=$debug;
	$debug=1;
	open(STDERR,">>&",$amc_debug_fh);
	$amc_debug=1;
	debug("[".$$."]>>");
    }
    $amc_debug=$debug;
    set_debug_file() if($amc_debug && !$amc_debug_fh);
}

sub get_debug {
    return($amc_debug);
}

# noms de fichiers absolus ou relatifs

sub abs2proj {
    my ($surnoms,$fich)=@_;
    if(defined($fich) && $fich) {

	$fich =~ s/\/{2,}/\//g;

      CLES:for my $s (sort { length($surnoms->{$b}) <=> length($surnoms->{$a}) } grep { $_ && $surnoms->{$_} } (keys %$surnoms)) {
	  my $rep=$surnoms->{$s};
	  $rep.="/" if($rep !~ /\/$/);
	  $rep =~ s/\/{2,}/\//g;
	  if($fich =~ s/^\Q$rep\E\/*//) {
	      $fich="$s/$fich";
	      last CLES;
	  }
      }

	return($fich);
    } else {
	return('');
    }
}

sub proj2abs {
    my ($surnoms,$fich)=@_;
    if(defined($fich)) {
	if($fich =~ /^\//) {
	    return($fich);
	} else {
	    $fich =~ s/^([^\/]*)//;
	    my $code=$1;
	    if(!$surnoms->{$code}) {
		$fich=$code.$fich;
		$code=$surnoms->{''};
	    }
	    my $rep=$surnoms->{$code};
	    $rep.="/" if($rep !~ /\/$/);
	    $rep.=$fich;
	    $rep =~ s/\/{2,}/\//g;
	    return($rep);
	}
    } else {
	return('');
    }
}

sub clear_old {
    my ($type,@f)=@_;
    for my $file (@f) {
	if(-f $file) {
	    debug "Clearing old $type file: $file";
	    unlink($file);
	} elsif(-d $file) {
	    debug "Clearing old $type directory: $file";
	    opendir(my $dh, $file) || debug "ERROR: can't opendir $file: $!";
	    my @content = grep { -f $_ } map { "$file/$_" } readdir($dh);
	    closedir $dh;
	    debug "Removing ".(1+$#content)." files.";
	    unlink(@content);
	}
    }
}

sub new_filename_compose {
    my ($prefix,$suffix,$n)=@_;
    my $file;
    do {
	$n++;
	$file=$prefix."_".sprintf("%04d",$n).$suffix;
    } while(-e $file);
    return($file);
}

sub new_filename {
    my ($file)=@_;
    if(! -e $file) {
	return($file);
    } elsif($file =~ /^(.*)_([0-9]+)(\.[a-z0-9]+)$/i) {
	return(new_filename_compose($1,$3,$2));
    } elsif($file =~ /^(.*)(\.[a-z0-9]+)$/i) {
	return(new_filename_compose($1,$2,0));
    } else {
	return(new_filename_compose($file,'',0));
    }
}

sub pack_args {
    my @args=@_;
    $pack_fh = new File::Temp(TEMPLATE =>'AMC-PACK-XXXXXXXX',
			      SUFFIX => '.xml',
			      UNLINK=>1,
			      DIR=>File::Spec->tmpdir);
    binmode($pack_fh,':utf8');
    my $writer = new XML::Writer(OUTPUT=>$pack_fh,
				 ENCODING=>'UTF-8',
				 DATA_MODE=>1,
				 DATA_INDENT=>2);
    $writer->xmlDecl('UTF-8');
    $writer->startTag('arguments');
    for(@args) { $writer->dataElement('arg',$_); }
    $writer->endTag('arguments');
    my $fn=$pack_fh->filename;
    $pack_fh->close;
    return('--xmlargs',$fn);
}

sub unpack_args {
    my @args=@_;
    if($args[0] eq '--xmlargs') {
	shift(@args);
	my $file=shift(@args);
	my $xa=XMLin($file,'ForceArray'=>1,'SuppressEmpty'=>'')->{'arg'};
	unshift(@args,@$xa);
    }
    return(@args);
}

my $localisation;
my %titles=();
my %id_names=();

sub use_gettext {
    $localisation=Locale::gettext->domain("auto-multiple-choice");
    # For portable installs
    if(! -f ($localisation->dir()."/fr/LC_MESSAGES/auto-multiple-choice.mo")) {
	$localisation->dir(amc_adapt_path(
			       'locals'=>['locale'],
			       'alt'=>[$localisation->dir()],
			   ));
    }

    init_translations();
}

sub init_translations {
    %titles=(
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'nom'=>__p("Name [name column title in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'note'=>__p("Mark [mark column title in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'copie'=>__p("Sheet [sheet number column title in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'total'=>__p("Score [total score column title in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'max'=>__p("Max [maximum score column title in exported spreadsheet]"),
	);
    %id_names=(
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'max'=>__p("max [maximum score row name in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'moyenne'=>__p("mean [means of scores row name in exported spreadsheet]"),
	);
}

sub translate_column_title {
    my ($k)=@_;
    return($titles{$k} ? $titles{$k} : $k);
}

sub translate_id_name {
    my ($k)=@_;
    return($id_names{$k} ? $id_names{$k} : $k);
}

sub format_date {
  my ($time)=@_;
  return(decode('UTF-8',strftime("%x %X",localtime($time))));
}

sub pageids_string {
  my ($student,$page,$copy,%oo)=@_;
  my $s=$student.'/'.$page
    .($copy ? ':'.$copy : '');
  $s =~ s/[^0-9]/-/g if($oo{'path'});
  return($s);
}

sub studentids_string {
  my ($student,$copy)=@_;
  $student='' if(!defined($student));
  return($student.($copy ? ':'.$copy : ''));
}

sub __($) { return($localisation->get(shift)); }
sub __p($) {
    my $str=$localisation->get(shift);
    $str =~ s/\s+\[.*\]\s*$//;
    return($str);
}

### modeles combobox

sub cb_model {
    my @texte=(@_);
    my $cs=Gtk2::ListStore->new ('Glib::String','Glib::String');
    my $k;
    my $t;
    while(($k,$t)=splice(@texte,0,2)) {
	$cs->set($cs->append,
		 COMBO_ID,$k,
		 COMBO_TEXT,$t);
    }
    return($cs);
}

sub check_fonts {
  my ($spec)=@_;
  if($spec->{'type'} =~ /fontconfig/i && @{$spec->{'family'}}) {
    if(commande_accessible("fc-list")) {
      my $ok=0;
      for my $f (@{$spec->{'family'}}) {
	open FC,"-|","fc-list",$f,"family";
	while(<FC>) { chomp();$ok=1 if(/./); }
	close FC;
      }
      return(0) if(!$ok);
    }
  }
  return(1);
}

sub amc_user_confdir {
  return(Glib::get_home_dir().'/.AMC.d');
}

sub use_amc_plugins {
  my $plugins_dir=amc_user_confdir.'/plugins';
  if(opendir(my $dh,$plugins_dir)) {
    push @INC,grep { -d $_ }
      map { "$plugins_dir/$_/perl" } readdir($dh);
    closedir $dh;
  } else {
    debug "Can't open plugins dir $plugins_dir: $!";
  }
}

sub find_latex_file {
  my ($file)=@_;
  return() if(!commande_accessible("kpsewhich"));
  open KW,"-|","kpsewhich","-all","$file";
  chomp(my $p=<KW>);
  close(KW);
  return($p);
}

1;
