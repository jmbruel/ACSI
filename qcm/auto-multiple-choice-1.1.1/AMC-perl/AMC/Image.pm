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

package AMC::Image;

use AMC::Basic;
use IPC::Open2;

sub new {
    my ($fichier,%o)=(@_);
    my $self={'fichier'=>$fichier,
	      'ipc_in'=>'',
	      'ipc_out'=>'',
	      'ipc'=>'',
	      'args'=>['%f'],
	      'mode'=>'auto',
	      'traitement'=>'',
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    if(! $self->{'traitement'}) {
      if($self->{'mode'} eq 'auto') {
	if(-f amc_specdir('libexec').'/AMC-detect') {
	  $self->{'mode'}='opencv';
	} else {
	  $self->{'mode'}='manual';
	}
      }
      if($self->{'mode'} eq 'opencv') {
	$self->{'traitement'}=amc_specdir('libexec').'/AMC-detect';
      } elsif($self->{'mode'} eq 'manual') {
	$self->{'traitement'}=amc_specdir('libexec').'/AMC-traitement-image';
      }
    }

    if(! -f $self->{'traitement'}) {
      die "AMC::Image: No program to execute";
    }

    bless $self;

    return($self);
}

sub set {
    my ($self,%oo)=(@_);
    for my $k (keys %oo) {
	$self->{$k}=$oo{$k} if(defined($self->{$k}));
    }
}

sub mode {
    my ($self)=(@_);
    return($self->{'mode'});
}

sub commande {
    my ($self,@cmd)=(@_);
    my @r=();

    if(!$self->{'ipc'}) {
	debug "Exec traitement-image..."; 
	my @a=map { ( $_ eq '%f' ? $self->{'fichier'} : $_ ) }
	(@{$self->{'args'}});
	debug join(' ',$self->{'traitement'},@a);
	$self->{'times'}=[times()];
	$self->{'ipc'}=open2($self->{'ipc_out'},$self->{'ipc_in'},
			     $self->{'traitement'},@a);
	debug "PID=".$self->{'ipc'}." : ".$self->{'ipc_in'}." --> ".$self->{'ipc_out'};
    }

    debug "CMD : ".join(' ',@cmd);

    print { $self->{'ipc_in'} } join(' ',@cmd)."\n";

    my $o;
  GETREPONSE: while($o=readline($self->{'ipc_out'})) {
      chomp($o);
      debug "|> $o";
      last GETREPONSE if($o =~ /_{2}END_{2}/);
      push @r,$o;
  }

    return(@r);
}

sub ferme_commande {
    my ($self)=(@_);
    if($self->{'ipc'}) {
	debug "Image sending QUIT";
	print { $self->{'ipc_in'} } "quit\n";
	waitpid $self->{'ipc'},0;
	$self->{'ipc'}='';
	$self->{'ipc_in'}='';
	$self->{'ipc_out'}='';
	my @tb=times();
	debug sprintf("Image finished: parent times [%7.02f,%7.02f]",
		      $tb[0]+$tb[1]-$self->{'times'}->[0]-$self->{'times'}->[1],$tb[2]+$tb[3]-$self->{'times'}->[2]-$self->{'times'}->[3]);
    }
}

sub DESTROY {
    my ($self)=(@_);
    $self->ferme_commande();
}

1;
