#! /usr/bin/perl
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

use encoding "utf-8";

use File::Copy;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;

use Module::Load;

use Getopt::Long;

use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Data;
use AMC::DataModule::scoring ':question';
use AMC::Queue;

use_gettext;
use_amc_plugins();

$VERSION_BAREME=2;

my $cmd_pid='';

my $queue='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-prepare : signal $signame, killing $cmd_pid...";
    kill 9,$cmd_pid if($cmd_pid);
    $queue->killall() if($queue);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $mode="mbs";
my $data_dir="";
my $bareme="";
my $convert_opts="-limit memory 512mb";
my $dpi=300;
my $calage='';

my $moteur_latex='latex';
my @moteur_args=();
my $moteur_topdf='';
my $prefix='';
my $filter='';
my $filtered_source='';

my $debug='';
my $latex_stdout='';

my $n_procs=0;
my $nombre_copies=0;

my $progress=1;
my $progress_id='';

my $out_calage='';
my $out_sujet='';
my $out_corrige='';

my $moteur_raster='poppler';

my $jobname="amc-compiled";

my $encodage_interne='UTF-8';

GetOptions("mode=s"=>\$mode,
	   "with=s"=>\$moteur_latex,
	   "data=s"=>\$data_dir,
	   "calage=s"=>\$calage,
	   "out-calage=s"=>\$out_calage,
	   "out-sujet=s"=>\$out_sujet,
	   "out-corrige=s"=>\$out_corrige,
	   "dpi=s"=>\$dpi,
	   "convert-opts=s"=>\$convert_opts,
	   "debug=s"=>\$debug,
	   "latex-stdout!"=>\$latex_stdout,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "prefix=s"=>\$prefix,
	   "n-procs=s"=>\$n_procs,
	   "n-copies=s"=>\$nombre_copies,
	   "raster=s"=>\$moteur_raster,
	   "filter=s"=>\$filter,
	   "filtered-source=s"=>\$filtered_source,
	   );

set_debug($debug);

debug("AMC-prepare / DEBUG") if($debug);

sub split_latex_engine {
  my ($engine)=@_;

  $moteur_latex=$engine if($engine);

  if($moteur_latex =~ /([^ ]+)\s+(.*)/) {
    $moteur_latex=$1;
    @moteur_args=split(/ +/,$2);
  }

  if($moteur_latex =~ /(.*)\+(.*)/) {
    $moteur_latex=$1;
    $moteur_topdf=$2;
  }
}

split_latex_engine();

$queue=AMC::Queue::new('max.procs',$n_procs);

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $source=$ARGV[0];

die "Nonexistent source file: $source" if(! -f $source);

my $base=$source;
$base =~ s/\.[a-zA-Z0-9]{1,4}$//gi;

$filtered_source=$base.'_filtered.tex' if(!$filtered_source);

$data_dir="$base-data" if(!$data_dir);

for(\$data_dir,\$source,\$filtered_source) {
    $$_=rel2abs($$_);
}

my $a_erreurs;
my @latex_errors=();
my @erreurs_msg=();
my %info_vars=();

sub verifie_q {
    my ($q,$t)=@_;

    return() if($info_vars{'postcorrect'});

    if($q) {
	if(!($q->{'mult'} || $q->{'partial'})) {
	    my $oui=0;
	    my $tot=0;
	    for my $i (grep { /^R/ } (keys %$q)) {
		$tot++;
		$oui++ if($q->{$i});
	    }
	    if($oui!=1 && !$q->{'indicative'}) {
		$a_erreurs++;
		push @erreurs_msg,"ERR: "
		    .sprintf(__("%d/%d good answers not coherent for a simple question")." [%s]\n",$oui,$tot,$t);
	    }
	}
    }
}

sub analyse_amclog {
    # check common errors in LaTeX about questions:
    # * same ID used multiple times for the same paper
    # * simple questions with number of good answers != 1
    my ($fich)=@_;

    my %analyse_data=();
    my %titres=();
    @erreurs_msg=();

    debug("Check AMC log : $fich");

    open(AMCLOG,$fich) or die "Unable to open $fich : $!";
    while(<AMCLOG>) {

	if(/AUTOQCM\[Q=([0-9]+)\]/) { 
	    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});
	    $analyse_data{'q'}={};
	    if($analyse_data{'qs'}->{$1}) {
		if($analyse_data{'qs'}->{$1}->{'partial'}) {
		    $analyse_data{'q'}=$analyse_data{'qs'}->{$1};
		    delete($analyse_data{'q'}->{'partial'});
		} else {
		    $a_erreurs++;
		    push @erreurs_msg,"ERR: "
			.sprintf(__("question ID used several times for the same paper: \"%s\"")." [%s]\n",$titres{$1},$analyse_data{'etu'});
		}
	    }
	    $analyse_data{'titre'}=$titres{$1};
	    $analyse_data{'qs'}->{$1}=$analyse_data{'q'};
	}
	if(/AUTOQCM\[QPART\]/) {
	    $analyse_data{'q'}->{'partial'}=1;
	}
	if(/AUTOQCM\[ETU=([0-9]+)\]/) {
	    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});
	    %analyse_data=('etu'=>$1,'qs'=>{});
	}
	if(/AUTOQCM\[NUM=([0-9]+)=([^\]]+)\]/) {
	    $titres{$1}=$2;
	    $analyse_data{'titres'}->{$2}=1;
	}
	if(/AUTOQCM\[MULT\]/) { 
	    $analyse_data{'q'}->{'mult'}=1;
	}
	if(/AUTOQCM\[INDIC\]/) { 
	    $analyse_data{'q'}->{'indicative'}=1;
	}
	if(/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
	    my $rep="R".$1;
	    if(defined($analyse_data{'q'}->{$rep})) {
		$a_erreurs++;
		push @erreurs_msg,"ERR: "
		    .sprintf(__("Answer number ID used several times for the same question: %s")." [%s]\n",$1,$analyse_data{'titre'});
	    }
	    $analyse_data{'q'}->{$rep}=($2 eq 'B' ? 1 : 0);
	}
	if(/AUTOQCM\[VAR:([0-9a-zA-Z.-]+)=([^\]]+)\]/) {
	    $info_vars{$1}=$2;
	}
    
    }
    close(AMCLOG);
    
    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});

    debug(@erreurs_msg);
    print join('',@erreurs_msg);

    debug("AMC log $fich : $a_erreurs errors.");
}

sub execute {
    my %oo=(@_);

    my $n_run=0;
    my $rerun=0;
    my $format='';

    for my $ext (qw/pdf dvi ps/) {
	if(-f "$jobname.$ext") {
	    debug "Removing old $ext";
	    unlink("$jobname.$ext");
	}
    }

    do {

	$n_run++;
	
	$a_erreurs=0;
	@latex_errors=();
    
	debug "%%% Compiling: pass $n_run";

	$cmd_pid=open(EXEC,"-|",@{$oo{'command'}});
	die "Can't exec ".join(' ',@{$oo{'command'}}) if(!$cmd_pid);

	while(<EXEC>) {
	    #LaTeX Warning: Label(s) may have changed. Rerun to get cross-references right.
	    $rerun=1 if(/^LaTeX Warning:.*Rerun to get cross-references right/);
	    $format=$1 if(/^Output written on .*\.([a-z]+) \(/);

	    if(/^\!\s*(.*)$/) {
	      my $e=$1;
	      $e .= "..." if($e !~ /\.$/);
	      push @latex_errors,$e;
	    }
	    print STDERR $_ if(/^.+$/);
	    print $_ if($latex_stdout && /^.+$/);
	}
	close(EXEC);
	$cmd_pid='';

    } while($rerun && $n_run<=1 && ! $oo{'once'});

    # transformation dvi en pdf si besoin...

    $format='dvi' if($moteur_latex eq 'latex');
    $format='pdf' if($moteur_latex eq 'pdflatex');
    $format='pdf' if($moteur_latex eq 'xelatex');

    print "Output format: $format\n";
    debug "Output format: $format\n";

    if($format eq 'dvi') {
	if(-f "$jobname.dvi") {
	    $moteur_topdf='dvipdfm'
		if(!$moteur_topdf);
	    if(!commande_accessible($moteur_topdf)) {
		debug_and_stderr
		    "WARNING: command $moteur_topdf not available";
		$moteur_topdf=choose_command('dvipdfmx','dvipdfm','xdvipdfmx',
					     'dvipdf');
	    }
	    if($moteur_topdf) {
		debug "Converting DVI to PDF with $moteur_topdf ...";
		if($moteur_topdf eq 'dvipdf') {
		    system($moteur_topdf,"$jobname.dvi","$jobname.pdf");
		} else {
		    system($moteur_topdf,"-o","$jobname.pdf","$jobname.dvi");
		}
		debug_and_stderr "ERROR $moteur_topdf: $?" if($?);
	    } else {
		debug_and_stderr
		    "ERROR: I can't find dvipdf/dvipdfm/xdvipdfmx command !";
	    }
	} else {
	    debug "No DVI";
	}
    }

}

my $f_tex;

sub do_filter {
  my $f_base;
  my $v;
  my $d;

  if($filter && $filter ne 'latex') {
    load("AMC::Filter::$filter");
    my $filter="AMC::Filter::$filter"->new();
    $filter->filter($source,$filtered_source);
    for($filter->errors()) {
      print "ERR: $_\n";
    }
    split_latex_engine($filter->{'project_options'}->{'moteur_latex_b'})
      if($filter->{'project_options'}->{'moteur_latex_b'});
  } else {
    $filtered_source=$source;
  }

  # on se place dans le repertoire du LaTeX
  ($v,$d,$f_tex)=splitpath($filtered_source);
  chdir(catpath($v,$d,""));
  $f_base=$f_tex;
  $f_base =~ s/\.tex$//i;

  $prefix=$f_base."-" if(!$prefix);
}

sub give_latex_errors {
    my ($context)=@_;
    if(@latex_errors) {
	print "ERR: <i>"
	    .sprintf(__("%d errors during LaTeX compiling")." (%s)</i>\n",(1+$#latex_errors),$context);
	for(@latex_errors) {
	    print "ERR>$_\n";
	}
	exit(1);
    }
}

sub transfere {
    my ($orig,$dest)=@_;
    if(-f $orig) {
	debug "Moving $orig --> $dest";
	move($orig,$dest);
    } else {
	debug "No source: removing $dest";
	unlink($dest);
    }
}

sub latex_cmd {
    my (%o)=@_;

    $o{'AMCNombreCopies'}=$nombre_copies if($nombre_copies>0);

    return($moteur_latex,
	   "--jobname=".$jobname,
	   @moteur_args,
	   "\\nonstopmode"
	   .join('',map { "\\def\\".$_."{".$o{$_}."}"; } (keys %o) )
	   ." \\input{\"$f_tex\"}");
}

sub check_moteur {
    if(!commande_accessible($moteur_latex)) {
	print "ERR: ".sprintf(__("LaTeX command configured is not present (%s). Install it or change configuration, and then rerun."),$moteur_latex)."\n";
	exit(1);
    }
}

if($mode =~ /f/) {
  # FILTER
  do_filter();
}

if($mode =~ /k/) {
    # CORRECTION INDIVIDUELLE

    do_filter();

    check_moteur();

    execute('command'=>[latex_cmd(qw/NoWatermarkExterne 1 NoHyperRef 1 CorrigeIndivExterne 1/)]);
    transfere("$jobname.pdf",($out_corrige ? $out_corrige : $prefix."corrige.pdf"));
    give_latex_errors(__"individual solution");
}

if($mode =~ /s/) {
    # SUJETS

    do_filter();

    check_moteur();

    my %opts=(qw/NoWatermarkExterne 1 NoHyperRef 1/);

    $out_calage=$prefix."calage.xy" if(!$out_calage);
    $out_corrige=$prefix."corrige.pdf" if(!$out_corrige);
    $out_sujet=$prefix."sujet.pdf" if(!$out_sujet);

    for my $f ($out_calage,$out_corrige,$out_sujet) {
	if(-f $f) {
	    debug "Removing already existing file: $f";
	    unlink($f);
	}
    }

    # 1) sujet et calage

    execute('command'=>[latex_cmd(%opts,'SujetExterne'=>1)]);
    analyse_amclog("$jobname.amc");
    transfere("$jobname.pdf",$out_sujet);
    give_latex_errors(__"question sheet");

    exit(1) if($a_erreurs>0);

    transfere("$jobname.xy",$out_calage);

    # transmission des variables

    print "Variables :\n";
    for my $k (keys %info_vars) {
	print "VAR: $k=".$info_vars{$k}."\n";
    }

    # 2) corrige

    execute('command'=>[latex_cmd(%opts,'CorrigeExterne'=>1)]);
    transfere("$jobname.pdf",$out_corrige);
    give_latex_errors(__"solution");
}

if($mode =~ /b/) {
    # BAREME

    print "********** Making marks scale...\n";

    do_filter();

    check_moteur();

    # compilation en mode calibration

    my %bs=();
    my %titres=();

    my $quest='';
    my $rep='';
    my $etu=0;

    my $delta=0;

    my $data=AMC::Data->new($data_dir);
    my $scoring=$data->module('scoring');
    my $capture=$data->module('capture');

    my $qs={};
    my $current_q={};

    $scoring->begin_transaction('ScEx');
    $capture->variable('annotate_source_change',time());
    $scoring->clear_strategy;

    execute('command'=>[latex_cmd(qw/CalibrationExterne 1 NoHyperRef 1/)],
	    'once'=>1);
    open(AMCLOG,"$jobname.amc") or die "Unable to open $jobname.amc : $!";
    while(<AMCLOG>) {
	debug($_) if($_);
	if(/AUTOQCM\[TOTAL=([\s0-9]+)\]/) { 
	    my $t=$1;
	    $t =~ s/\s//g;
	    if($t>0) {
		$delta=1/$t;
	    } else {
		print "*** TOTAL=$t ***\n";
	    }
	}
	if(/AUTOQCM\[FQ\]/) {
	  # end of question: register it (or update it)
	  $scoring->statement('NEWQuestion')
	    ->execute($etu,$quest,
		      ($current_q->{'multiple'} 
		       ? QUESTION_MULT : QUESTION_SIMPLE),
		      $current_q->{'indicative'},
		      $current_q->{'strategy'});
	  $qs->{$quest}=$current_q;
	  $quest='';
	  $rep='';
	}
	if(/AUTOQCM\[Q=([0-9]+)\]/) {
	  # beginning of question
	  $quest=$1;
	  $rep='';
	  if($qs->{$quest}) {
	      $current_q=$qs->{$quest};
	  } else {
	      $current_q={'multiple'=>0,
			  'indicative'=>0,
			  'strategy'=>'',
	      };
	  }
	}
	if(/AUTOQCM\[ETU=([0-9]+)\]/) {
	  # beginning of student sheet
	  $avance->progres($delta) if($etu ne '');
	  $etu=$1;
	  print "Sheet $etu...\n";
	  debug "Sheet $etu...\n";
	  $qs={};
	}
	if(/AUTOQCM\[NUM=([0-9]+)=([^\]]+)\]/) {
	  # association question-number<->question-title
	  $scoring->question_title($1,$2);
	}
	if(/AUTOQCM\[MULT\]/) {
	  # this question is a multiple-style one
	  $current_q->{'multiple'}=1;
	}
	if(/AUTOQCM\[INDIC\]/) {
	  # this question is an indicative one
	  $current_q->{'indicative'}=1;
	}
	if(/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
	  $rep=$1;
	  $scoring->statement('NEWAnswer')
	    ->execute($etu,$quest,$rep,($2 eq 'B' ? 1 : 0),'');
	}
	if(/AUTOQCM\[BR=([0-9]+)\]/) {
	  $scoring->replicate($1,$etu);
	}
	if(/AUTOQCM\[B=([^\]]+)\]/) {
	  if($quest) {
	    if($rep) {
	      $scoring->add_answer_strategy($etu,$quest,$rep,$1);
	    } else {
	      $current_q->{'strategy'}=
		  ($current_q->{'strategy'} 
		   ? $current_q->{'strategy'}.',' : '').$1;
	    }
	  } else {
	    $scoring->add_main_strategy($etu,$1);
	  }
	}
	if(/AUTOQCM\[BD(S|M)=([^\]]+)\]/) {
	  $scoring->default_strategy(($1 eq 'S' ? QUESTION_SIMPLE : QUESTION_MULT),
				  $2);
	}
	if(/AUTOQCM\[VAR:([0-9a-zA-Z.-]+)=([^\]]+)\]/) {
	  my $name=$1;
	  my $value=$2;
	  $name='postcorrect_flag' if ($name eq 'postcorrect');
	  $scoring->variable($name,$value);
	}
    }
    close(AMCLOG);
    $cmd_pid='';

    $scoring->end_transaction('ScEx');
}

$avance->fin();
