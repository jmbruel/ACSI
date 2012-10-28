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

use Getopt::Long;
use POSIX qw(ceil floor);
use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Scoring;
use AMC::Data;

use encoding 'utf8';

my $association="-";
my $seuil=0.1;

my $note_plancher='';
my $note_parfaite=20;
my $grain='0.5';
my $arrondi='';
my $delimiteur=',';
my $encodage_interne='UTF-8';
my $data_dir='';

my $postcorrect_student='';
my $postcorrect_copy='';

my $progres=1;
my $plafond=1;
my $progres_id='';

my $debug='';

GetOptions("data=s"=>\$data_dir,
	   "seuil=s"=>\$seuil,
	   "debug=s"=>\$debug,
	   "grain=s"=>\$grain,
	   "arrondi=s"=>\$type_arrondi,
	   "notemax=s"=>\$note_parfaite,
	   "plafond!"=>\$plafond,
	   "notemin=s"=>\$note_plancher,
	   "postcorrect-student=s"=>\$postcorrect_student,
	   "postcorrect-copy=s"=>\$postcorrect_copy,
	   "encodage-interne=s"=>\$encodage_interne,
	   "progression-id=s"=>\$progres_id,
	   "progression=s"=>\$progres,
	   );

set_debug($debug);

# fixes decimal separator ',' potential problem, replacing it with a
# dot.
for my $x (\$grain,\$note_plancher,\$note_parfaite) {
    $$x =~ s/,/./;
    $$x =~ s/\s+//;
}

# Implements the different possible rounding schemes.

sub arrondi_inf {
    my $x=shift;
    return(floor($x));
}

sub arrondi_central {
    my $x=shift;
    return(floor($x+0.5));
}

sub arrondi_sup {
    my $x=shift;
    return(ceil($x));
}

my %fonction_arrondi=('i'=>\&arrondi_inf,'n'=>\&arrondi_central,'s'=>\&arrondi_sup);

if($type_arrondi) {
    for my $k (keys %fonction_arrondi) {
	if($type_arrondi =~ /^$k/i) {
	    $arrondi=$fonction_arrondi{$k};
	}
    }
}

if(! -d $data_dir) {
    attention("No DATA directory: $data_dir");
    die "No DATA directory: $data_dir";
}

if($grain<=0) {
    $grain=1;
    $arrondi='';
    $type_arrondi='';
    debug("Nonpositive grain: rounding off");
}

my $avance=AMC::Gui::Avancement::new($progres,'id'=>$progres_id);

my $data=AMC::Data->new($data_dir);
my $capture=$data->module('capture');
my $scoring=$data->module('scoring');

my $bar=AMC::Scoring::new('onerror'=>'die',
			  'data'=>$data,
			  'seuil'=>$seuil);

$avance->progres(0.05);

$data->begin_transaction;

$capture->variable('annotate_source_change',time());
$scoring->clear_score;
$scoring->variable('darkness_threshold',$seuil);
$scoring->variable('mark_floor',$note_plancher);
$scoring->variable('mark_max',$note_parfaite);
$scoring->variable('ceiling',$plafond);
$scoring->variable('rounding',$type_arrondi);
$scoring->variable('granularity',$grain);
$scoring->variable('postcorrect_student',$postcorrect_student);
$scoring->variable('postcorrect_copy',$postcorrect_copy);

my $somme_notes=0;
my $n_notes=0;

my @a_calculer=@{$capture->dbh
		   ->selectall_arrayref($capture->statement('studentCopies'),{})};

my $delta=0.95;
$delta/=(1+$#a_calculer) if($#a_calculer>=0);

# postcorrect mode?
if($postcorrect_student) {
    $scoring->postcorrect($postcorrect_student,$postcorrect_copy,$seuil);
}

for my $sc (@a_calculer) {
  debug "MARK: --- SHEET ".studentids_string(@$sc);

  my $total=0;
  my $max_i=0;
  my %codes=();

  my $ssb=$scoring->student_scoring_base(@$sc,$seuil);

  $bar->set_default_strategy($ssb->{'main_strategy'});

  for my $question (keys %{$ssb->{'questions'}}) {
    my $q=$ssb->{'questions'}->{$question};

    debug "MARK: QUESTION $question TITLE ".$q->{'title'};

    debug "Unknown question data !" if(!defined($q));
    ($xx,$raison,$keys)=$bar->score_question(@$sc,$q);
    ($notemax)=$bar->score_max_question($sc->[0],$q);

    if ($q->{'title'} =~ /^(.*)\.([0-9]+)$/) {
      $codes{$1}->{$2}=$xx;
    }

    if ($q->{'indicative'}) {
      $notemax=1;
    } else {
      $total+=$xx;
      $max_i+=$notemax;
    }

    $scoring->new_score(@$sc,$question,$xx,$notemax,$raison);
  }

  # Final mark --

  # total qui faut pour avoir le max
  my %m=$bar->degroupe($ssb->{'main_strategy'},{},{});
  $max_i=$m{'SUF'} if(defined($m{'SUF'}));

  if ($max_i<=0) {
    debug "Warning: Nonpositive value for MAX.";
    $max_i=1;
  }

  # application du grain et de la note max
  my $x;

  if ($note_parfaite>0) {
    $x=$note_parfaite/$grain*$total/$max_i;
  } else {
    $x=$total/$grain;
  }
  $x=&$arrondi($x) if($arrondi);
  $x*=$grain;

  $x=$note_parfaite if($note_parfaite>0 && $plafond && $x>$note_parfaite);

  # plancher

  if ($note_plancher ne '' && $note_plancher !~ /[a-z]/i) {
    $x=$note_plancher if($x<$note_plancher);
  }

  #--

  $n_notes++;
  $somme_notes+=$x;

  $scoring->new_mark(@$sc,$total,$max_i,$x);

  for my $k (keys %codes) {
    my @i=(keys %{$codes{$k}});
    if ($#i>0) {
      my $v=join('',map { $codes{$k}->{$_} }
		 sort { $b <=> $a } (@i));
      $scoring->new_code(@$sc,$k,$v);
    }
  }

  $avance->progres($delta);
}

$data->end_transaction;

$avance->fin();
