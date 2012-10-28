#
# Copyright (C) 2009-2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export;

use AMC::Basic;
use AMC::Data;
use AMC::NamesFile;

use_gettext;

my %sorting=('l'=>['n:student.line'],
	     'm'=>['n:mark','s:student.name','n:student.line'],
	     'i'=>['n:student','n:copy','n:student.line'],
	     'n'=>['s:student.name','n:student.line'],
	    );

sub new {
    my $class = shift;
    my $self  = {
	'fich.datadir'=>'',
	'fich.noms'=>'',

	'noms'=>'',

	'noms.encodage'=>'',
	'noms.separateur'=>'',
	'noms.useall'=>1,
	'noms.abs'=>'ABS',
	'noms.identifiant'=>'',

	'out.rtl'=>'',

	'sort.keys'=>['s:student.name','n:student.line'],

	'marks'=>[],
    };
    bless ($self, $class);
    return $self;
}

sub set_options {
    my ($self,$domaine,%f)=@_;
    for(keys %f) {
	my $k=$domaine.'.'.$_;
	if(defined($self->{$k})) {
	    debug "Option $k = $f{$_}";
	    $self->{$k}=$f{$_};
	} else {
	    debug "Unusable option <$domaine.$_>\n";
	}
    }
}

sub opts_spec {
    my ($self,$domaine)=@_;
    my @o=();
    for my $k (grep { /^$domaine/ } (keys %{$self})) {
	my $kk=$k;
	$kk =~ s/^$domaine\.//;
	push @o,$kk,$self->{$k} if($self->{$k});
    }
    return(@o);
}

sub load {
    my ($self)=@_;
    die "Needs data directory" if(!-d $self->{'fich.datadir'});

    $self->{'_data'}=AMC::Data->new($self->{'fich.datadir'});
    $self->{'_scoring'}=$self->{'_data'}->module('scoring');
    $self->{'_assoc'}=$self->{'_data'}->module('association');

    if($self->{'fich.noms'} && ! $self->{'noms'}) {
	$self->{'noms'}=AMC::NamesFile::new($self->{'fich.noms'},
					    $self->opts_spec('noms'),
					   );
    }
}

sub pre_process {
    my ($self)=@_;

    $self->{'sort.keys'}=$sorting{lc($1)}
      if($self->{'sort.keys'} =~ /^\s*([lmin])/i);
    $self->{'sort.keys'}=[] if(!$self->{'sort.keys'});

    $self->load();

    $self->{'_scoring'}->begin_read_transaction('EXPP');

    my $lk=$self->{'_assoc'}->variable('key_in_list');
    my %keys=();
    my @marks=();
    my @post_correct=$self->{'_scoring'}->postcorrect_sc;

    # Get all students from the marks table

    my $sth=$self->{'_scoring'}->statement('marks');
    $sth->execute;
  STUDENT: while(my $m=$sth->fetchrow_hashref) {
      next STUDENT if($m->{student}==$post_correct[0] &&
		      $m->{'copy'}==$post_correct[1]);

      $m->{'abs'}=0;
      $m->{'student.copy'}=studentids_string($m->{'student'},$m->{'copy'});

      # Association key for this sheet
      $m->{'student.key'}=$self->{'_assoc'}->get_real($m->{'student'},$m->{'copy'});
      $keys{$m->{'student.key'}}=1;

      # find the corresponding name
      my ($n)=$self->{'noms'}->data($lk,$m->{'student.key'});
      if($n) {
	$m->{'student.name'}=$n->{'_ID_'};
	$m->{'student.line'}=$n->{'_LINE_'};
	$m->{'student.all'}={%$n};
      } else {
	for(qw/name line/) {
	  $m->{"student.$_"}='?';
	}
      }
      push @marks,$m;
    }

    # Now, add students with no mark (if requested)

    if($self->{'noms.useall'}) {
      for my $i ($self->{'noms'}->liste($lk)) {
	if(!$keys{$i}) {
	  my ($name)=$self->{'noms'}->data($lk,$i);
	  push @marks,
	    {'student'=>'',
	     'copy'=>'',
	     'student.copy'=>'',
	     'abs'=>1,
	     'student.key'=>$name->{$lk},
	     'mark'=>$self->{'noms.abs'},
	     'student.name'=>$name->{'_ID_'},
	     'student.line'=>$name->{'_LINE_'},
	     'student.all'=>{%$name},
	    };
	}
      }
    }

    # sorting as requested

    debug "Sorting with keys ".join(", ",@{$self->{'sort.keys'}});
    $self->{'marks'}=[sort { $self->compare($a,$b); } @marks];

    $self->{'_scoring'}->end_transaction('EXPP');

}

sub compare {
    my ($self,$xa,$xb)=@_;
    my $r=0;

    for my $k (@{$self->{'sort.keys'}}) {
	my $key=$k;
	my $mode='s';

	if($k =~ /^([ns]):(.*)/) {
	  $mode=$1;
	  $key=$2;
	  if($mode eq 'n') {
	    $r=$r || ( $xa->{$key} <=>
		       $xb->{$key} );
	  } else {
	    $r=$r || ( $xa->{$key} cmp
		       $xb->{$key} );
	  }
	}
    }
    return($r);
}

sub export {
    my ($self,$fichier)=@_;

    debug "WARNING: Base class export to $fichier\n";
}

1;

