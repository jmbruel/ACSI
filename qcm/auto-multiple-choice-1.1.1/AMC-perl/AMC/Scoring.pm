# -*- perl -*-
#
# Copyright (C) 2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Scoring;

use AMC::Basic;
use AMC::DataModule::scoring qw/:question/;

sub new {
    my (%o)=(@_);

    my $self={'onerror'=>'stderr',
	      'seuil'=>0,
	      'data'=>'',
	      'default_strategy'=>{},
	      '_capture'=>'',
	      '_scoring'=>'',
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    bless $self;

    if($self->{'data'}) {
      $self->{'_capture'}=$self->{'data'}->module('capture');
      $self->{'_scoring'}=$self->{'data'}->module('scoring');
    }

    $self->set_default_strategy();

    return($self);
}

sub error {
    my ($t)=@_;
    debug $t;
    if($self->{'onerror'} =~ /\bstderr\b/i) {
	print STDERR "$t\n";
    }
    if($self->{'onerror'} =~ /\bdie\b/i) {
	die $t;
    }
}

###################
# derived methods #
###################

sub ticked {
  my ($self,$student,$copy,$question,$answer)=@_;
  return($self->{'_capture'}
	 ->ticked($student,$copy,$question,$answer,$self->{'seuil'}));
}

# tells if the answer given by the student is the correct one (ticked
# if it has to be, or not ticked if it has not to be).
sub answer_is_correct {
    my ($self,$student,$copy,$question,$answer)=@_;
    return($self->ticked($student,$copy,$question,$answer)
	   == $self->{'_scoring'}->correct_answer($student,$question,$answer));
}

#################
# score methods #
#################

# reads a scoring strategy string, and returns a hash with parameters
# values.
#
# $s is the scoring strategy string
#
# $defaut is the default scoring strategy hash reference, as returned
# by degroupe for the default scoring strategy.
#
# $vars is a hash reference with variables values to be substituted in
# the scoring parameters values.
sub degroupe {
    my ($self,$s,$defaut,$vars)=(@_);
    my %r=(%$defaut);
    for my $i (split(/,+/,$s)) {
	$i =~ s/^\s+//;
	$i =~ s/\s+$//;
	if($i =~ /^([^=]+)=([-+*\/0-9a-zA-Z\.\(\)?:|&=<>!\s]+)$/) {
	    $r{$1}=$2;
	} else {
	    $self->error("Marking scale syntax error: $i within $s") if($i);
	}
    }
    # substitute variables values, and then evaluate the value.
    for my $k (keys %r) {
	my $v=$r{$k};
	for my $vv (keys %$vars) {
	    $v=~ s/\b$vv\b/$vars->{$vv}/g;
	}
	$self->error("Syntax error (unknown variable): $v") if($v =~ /[a-z]/i);
	my $calc=eval($v);
	$self->error("Syntax error (operation) : $v") if(!defined($calc));
	debug "Evaluation : $r{$k} => $v => $calc" if($r{$k} ne $calc);
	$r{$k}=$calc;
    }
    #
    return(%r);
}

sub set_default_strategy {
  my ($self,$strategy_string)=@_;
  $self->{'default_strategy'}=
    {$self->degroupe($strategy_string,
		     {'e'=>0,'b'=>1,'m'=>0,'v'=>0,'d'=>0,'auto'=>-1},{})};
}

# returns the score for a particular student-sheet/question, applying
# the given scoring strategy.
sub score_question {
    my ($self,$etu,$copy,$question_data,$correct)=@_;
    my $answers=$question_data->{'answers'};

    my $xx='';
    my $raison='';
    my $vars={'NB'=>0,'NM'=>0,'NBC'=>0,'NMC'=>0};
    my %b_q=();

    my $n_ok=0;
    my $n_coche=0;
    my $ticked_adata='';
    my $n_tous=0;
    my $n_plain=0;
    my $ticked_noneof='';

    for my $a (@$answers) {
	my $c=$a->{'correct'};
	my $t=($correct ? $c : $a->{'ticked'});

	debug("[$etu:$copy/".$a->{'question'}.":".$a->{'answer'}."] $t ($c)\n");

	$n_ok+=($c == $t ? 1 : 0);
	$n_coche+=$t;
	$ticked_adata=$a if($t);
	$n_tous++;

	if($a->{'answer'}==0) {
	  $ticked_noneof=$a->{'ticked'};
	} else {
	    my $bn=($c ? 'B' : 'M');
	    my $co=($t ? 'C' : '');
	    $vars->{'N'.$bn}++;
	    $vars->{'N'.$bn.$co}++ if($co);

	    $n_plain++;
	}
    }

    # set variables from ticked answers set.VAR=VALUE
    for my $an (@$answers) {
	my $c=$an->{'correct'};
	my $t=($correct ? $c : $an->{'ticked'});
	if($t) {
	    my %as=$self->degroupe($an->{'strategy'},{},$vars);
	    for my $k (map { s/^set\.//; $_; }
		       grep { /^set\./ } (keys %as)) {
		if(defined($vars->{$k})) {
		    debug("[A] Variable $k set twice!");
		    $raison='E';
		} else {
		    debug("[A] Variable $k set to ".$as{'set.'.$k});
		    $vars->{$k}=$as{'set.'.$k};
		}
	    }
	}
    }

    # question wide variables
    $vars->{'N'}=$n_plain;
    $vars->{'IMULT'}=($question_data->{'type'}==QUESTION_MULT ? 1 : 0);
    $vars->{'IS'}=1-$vars->{'IMULT'};

    # question wide default values for some variables

    my %qs_var=$self->degroupe($question_data->{'default_strategy'}
			       .",".$question_data->{'strategy'},
			       $self->{'default_strategy'},
			       $vars);

    for my $k (map { s/^default\.//; $_; }
	       grep { /^default\./ } (keys %qs_var)) {
	if(!defined($vars->{$k})) {
	    debug("[Q] Variable $k set to default value ".$qs_var{'default.'.$k});
	    $vars->{$k}=$qs_var{'default.'.$k};
	}
    }

    # question wide variables set by scoring set.VAR=VALUE

    %qs_var=$self->degroupe($question_data->{'default_strategy'}
			    .",".$question_data->{'strategy'},
			    $self->{'default_strategy'},
			    $vars);

    for my $k (map { s/^set\.//; $_; }
	       grep { /^set\./ } (keys %qs_var)) {
	debug("[Q] Variable $k set to ".$qs_var{'set.'.$k});
	$vars->{$k}=$qs_var{'set.'.$k};
    }

    # get scoring strategy

    %b_q=$self->degroupe($question_data->{'default_strategy'}
			 .",".$question_data->{'strategy'},
			 $self->{'default_strategy'},
			 $vars);

    if($raison eq 'E') {
	$xx=$b_q{'e'};
    }

    if($n_coche==0) {
	# no ticked boxes
	$xx=$b_q{'v'};
	$raison='V';
    }

    # required values for some variables

    if(!$raison) {
	for my $k (map { s/^requires\.//; $_; }
		   grep { /^requires\./ && $qs_var{$_} } (keys %qs_var)) {
	    if(!defined($vars->{$k})) {
		debug("[Q] Variable $k is required but unset!");
		$xx=$b_q{'e'};
		$raison='E';
	    }
	}
    }

    if(!$raison) {
      if($vars->{'IMULT'}) {
	# MULTIPLE QUESTION

	$xx=0;

	if($b_q{'haut'}) {
	    $b_q{'d'}=$b_q{'haut'}-$n_plain;
	    $b_q{'p'}=0 if(!defined($b_q{'p'}));
	} elsif($b_q{'mz'}) {
	    $b_q{'d'}=$b_q{'mz'};
	    $b_q{'p'}=0 if(!defined($b_q{'p'}));
	    $b_q{'b'}=0;$b_q{'m'}=-( abs($b_q{'mz'})+abs($b_q{'p'})+1 );
	}

	if($n_coche !=1 && (!$correct) && $ticked_noneof) {
	    # incompatible answers: the student has ticked one
	    # plain answer AND the answer "none of the
	    # above"...
	    $xx=$b_q{'e'};
	    $raison='E';
	} elsif(defined($b_q{'formula'})) {
	  # a formula is given to compute the score directly

	  $xx=$b_q{'formula'};
	} else {
	  # standard case: adds the 'b' or 'm' scores for each answer
	  for my $a (@$answers) {
	    if($a->{'answer'} != 0) {
	      $code=($correct || ($a->{'ticked'}==$a->{'correct'})
		     ? "b" : "m");
	      my %b_qspec=$self->degroupe($a->{'strategy'},
					  \%b_q,$vars);
	      debug("Delta(".$a->{'answer'}."|$code)=$b_qspec{$code}");
	      $xx+=$b_qspec{$code};
	      $b_q{'force'}=$b_qspec{$code.'force'}
		if(defined($b_qspec{$code.'force'}));
	    }
	  }
	}

	if($raison !~ /^[VE]/i) {
	  if(defined($b_q{'force'})) {
	    $xx=$b_q{'force'};
	    $raison = 'F';
	  } else {
	    # adds the 'd' shift value
	    $xx+=$b_q{'d'};

	    # applies the 'p' floor value
	    if(defined($b_q{'p'})) {
	      if($xx<$b_q{'p'}) {
		$xx=$b_q{'p'};
		$raison='P';
	      }
	    }
	  }
	}
    } else {
	# SIMPLE QUESTION

	if(defined($b_q{'mz'})) {
	    $b_q{'b'}=$b_q{'mz'};
	    $b_q{'m'}=$b_q{'d'} if(defined($b_q{'d'}));
	}

	if($n_coche>1) {
	    # incompatible answers: there are more than one
	    # ticked boxes
	    $xx=$b_q{'e'};
	    $raison='E';
	} elsif(defined($b_q{'formula'})) {
	  # a formula is given to compute the score directly

	  $xx=$b_q{'formula'};
	} else {
	    # standard case
	    $sb=$ticked_adata->{'strategy'};
	    $sb =~ s/^\s*,+//;
	    $sb =~ s/,+\s*$//;
	    if($sb ne '') {
		# some value is given as a score for the
		# ticked answer
		$xx=$sb;
	    } else {
		# take into account the scoring strategy for
		# the question: 'auto', or 'b'/'m'
		$xx=($b_q{'auto'}>-1
		     ? $ticked_adata->{'answer'}+$b_q{'auto'}-1
		     : ($n_ok==$n_tous ? $b_q{'b'} : $b_q{'m'}));
	    }
	}
      }
    }

    debug "MARK: score=$xx ($raison)";

    return($xx,$raison,\%b_q);
}

# returns the score associated with correct answers for a question.
sub score_correct_question {
    my ($self,$etu,$question_data)=@_;
    return($self->score_question($etu,0,$question_data,1));
}

# returns the maximum score for a question: MAX parameter value, or,
# if not present, the score_correct_question value.
sub score_max_question {
   my ($self,$etu,$question_data)=@_;
   my ($x,$raison,$b)=($self->score_question($etu,0,$question_data,1));
   if(defined($b->{'MAX'})) {
       return($b->{'MAX'},'M',$b);
   } else {
       return($x,$raison,$b);
   }
}

1;
